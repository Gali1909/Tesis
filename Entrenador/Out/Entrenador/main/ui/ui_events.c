#include "ui.h"
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include "esp_log.h"
#include "bsp_illuminate.h"  // set_lcd_blight()
#include "wifi_manager.h"
#include "ui_wifi_popup.h"
#include "uart_bridge.h"    // uart_bridge_send_bluetooth()
#include "esp_now_comm.h"   // esp_now_send_idioma_receptor()
#include "esp_lvgl_port.h"  // lvgl_port_lock()/unlock() para el callback de sincronizacion

extern void open_edit_player_popup(lv_obj_t *btn);

static lv_obj_t *s_selected_btn = NULL;
static lv_obj_t *s_last_click_btn = NULL;
static uint32_t s_last_click_time = 0;

#define COLOR_BTN_NORMAL    0x1F2937
#define COLOR_BTN_SELECTED  0xE36F10

void slider_brillo_event_cb(lv_event_t * e)
{
    lv_obj_t *slider = lv_event_get_target(e);
    int32_t valor = lv_slider_get_value(slider); // 0-100 si el rango del slider esta en 0-100

    // 1) Actualizar el label con el porcentaje
    lv_label_set_text_fmt(ui_LabelBRILLO, "BRILLO DE LA PANTALLA: %d%%", (int)valor);

    // 2) Aplicar el brillo real al backlight
    esp_err_t err = set_lcd_blight((uint32_t)valor);
    if (err != ESP_OK) {
        ESP_LOGW("AJUSTES", "set_lcd_blight fallo (valor=%d): %s", (int)valor, esp_err_to_name(err));
    } else {
        ESP_LOGI("AJUSTES", "Brillo aplicado: %d%%", (int)valor);
    }
}

void slider_brillo_EN_event_cb(lv_event_t * e)
{
    lv_obj_t *slider = lv_event_get_target(e);
    int32_t valor = lv_slider_get_value(slider); // 0-100 si el rango del slider esta en 0-100

    // 1) Actualizar el label con el porcentaje
    lv_label_set_text_fmt(ui_LabelBRILLO1_EN, "SCREEN BRIGHTNESS: %d%%", (int)valor);

    // 2) Aplicar el brillo real al backlight
    esp_err_t err = set_lcd_blight((uint32_t)valor);
    if (err != ESP_OK) {
        ESP_LOGW("AJUSTES", "set_lcd_blight fallo (valor=%d): %s", (int)valor, esp_err_to_name(err));
    } else {
        ESP_LOGI("AJUSTES", "Brillo aplicado: %d%%", (int)valor);
    }
}

/*---------------------------------------------------------------
 * Resaltado del idioma seleccionado (botones ES/EN/IT/JA por
 * receptor, y ESPANOL/INGLES del idioma de pantalla).
 *
 * Genérico: funciona para cualquier grupo de botones "hermanos"
 * (mismo padre), sin importar si son 2 o 4 opciones, ni si es la
 * pantalla en español o en inglés. El botón tocado se pinta con
 * el color de acento y borde más grueso; los demás vuelven al
 * estilo normal.
 *--------------------------------------------------------------*/
#define COLOR_IDIOMA_NORMAL    0x1B2029
#define COLOR_IDIOMA_SELECTED  0x06D3E4

void ui_event_idioma_seleccionado(lv_event_t * e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_CLICKED) return;

    lv_obj_t *btn = lv_event_get_target(e);
    if (btn == NULL || !lv_obj_is_valid(btn)) return;

    lv_obj_t *parent = lv_obj_get_parent(btn);
    if (parent == NULL || !lv_obj_is_valid(parent)) return;

    uint32_t count = lv_obj_get_child_count(parent);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *sibling = lv_obj_get_child(parent, i);
        if (sibling == NULL || !lv_obj_is_valid(sibling)) continue;
        if (!lv_obj_check_type(sibling, &lv_button_class)) continue; /* saltar labels */

        bool selected = (sibling == btn);
        lv_obj_set_style_bg_color(sibling, lv_color_hex(selected ? COLOR_IDIOMA_SELECTED : COLOR_IDIOMA_NORMAL), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(sibling, selected ? 3 : 2, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_invalidate(sibling);
    }
}

/* Marca btn como "seleccionado" dentro de su grupo de hermanos sin
 * necesidad de un click (para el idioma ya activo al cargar la
 * pantalla, ej. ESPANOL en ui_Ajustes_ o INGLES en ui_Ajustes_EN). */
void ui_idioma_marcar_seleccionado(lv_obj_t *btn)
{
    if (btn == NULL || !lv_obj_is_valid(btn)) return;

    lv_obj_t *parent = lv_obj_get_parent(btn);
    if (parent == NULL || !lv_obj_is_valid(parent)) return;

    uint32_t count = lv_obj_get_child_count(parent);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *sibling = lv_obj_get_child(parent, i);
        if (sibling == NULL || !lv_obj_is_valid(sibling)) continue;
        if (!lv_obj_check_type(sibling, &lv_button_class)) continue;

        bool selected = (sibling == btn);
        lv_obj_set_style_bg_color(sibling, lv_color_hex(selected ? COLOR_IDIOMA_SELECTED : COLOR_IDIOMA_NORMAL), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(sibling, selected ? 3 : 2, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

/*---------------------------------------------------------------
 * Idioma configurado por receptor (persiste entre pantallas)
 *
 * ui_Ajustes_ y ui_Ajustes_EN son dos pantallas distintas: cada
 * vez que se cambia entre ellas, sus botones (lv_obj_t) se
 * destruyen y se vuelven a crear desde cero, así que no pueden
 * "recordar" nada por sí solos. Este arreglo estático SÍ persiste
 * (vive mientras el firmware corre), así que guarda qué idioma
 * quedó elegido para cada uno de los 3 receptores, sin importar
 * en qué pantalla (ES o EN) se hizo la selección. Por defecto,
 * los 3 receptores inician en español.
 *--------------------------------------------------------------*/
typedef enum {
    IDIOMA_ES = 0,
    IDIOMA_EN = 1,
    IDIOMA_IT = 2,
    IDIOMA_JA = 3
} idioma_t;

static idioma_t s_receptor_idioma[3] = { IDIOMA_ES, IDIOMA_ES, IDIOMA_ES };

/* Callback para los botones ES/EN/IT/JA de cada receptor.
 * user_data debe venir empaquetado como (receptor * 10 + idioma),
 * con receptor en 0..2 e idioma en 0..3 (ES=0, EN=1, IT=2, JA=3). */
void ui_event_idioma_receptor_seleccionado(lv_event_t * e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_CLICKED) return;

    lv_obj_t *btn = lv_event_get_target(e);
    if (btn == NULL || !lv_obj_is_valid(btn)) return;

    intptr_t packed = (intptr_t)lv_event_get_user_data(e);
    int receptor = (int)(packed / 10);
    int idioma   = (int)(packed % 10);
    if (receptor < 0 || receptor > 2 || idioma < 0 || idioma > 3) return;

    /* Guardar la seleccion para que sobreviva un cambio de pantalla */
    s_receptor_idioma[receptor] = (idioma_t)idioma;

    /* Avisar al receptor su idioma: 0 = espanol, 1 = ingles.
     * Es independiente del idioma de la pantalla (ES/EN): el user_data de
     * los botones es el mismo en ui_Ajustes_ y en ui_Ajustes_EN.
     * IT y JA todavia no se envian. */
    if (idioma == IDIOMA_ES || idioma == IDIOMA_EN) {
        esp_err_t err = esp_now_send_idioma_receptor((uint8_t)receptor, (uint8_t)idioma);
        if (err != ESP_OK) {
            ESP_LOGW("AJUSTES", "No se pudo enviar idioma al receptor %d: %s",
                     receptor + 1, esp_err_to_name(err));
        }
    }

    /* Resaltar el boton tocado entre sus hermanos (misma fila del receptor) */
    lv_obj_t *parent = lv_obj_get_parent(btn);
    if (parent == NULL || !lv_obj_is_valid(parent)) return;

    uint32_t count = lv_obj_get_child_count(parent);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *sibling = lv_obj_get_child(parent, i);
        if (sibling == NULL || !lv_obj_is_valid(sibling)) continue;
        if (!lv_obj_check_type(sibling, &lv_button_class)) continue;

        bool selected = (sibling == btn);
        lv_obj_set_style_bg_color(sibling, lv_color_hex(selected ? COLOR_IDIOMA_SELECTED : COLOR_IDIOMA_NORMAL), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(sibling, selected ? 3 : 2, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_invalidate(sibling);
    }
}

/* Aplica el idioma persistido de un receptor (0,1,2) resaltando el
 * boton correspondiente entre los 4 recien creados (ES/EN/IT/JA)
 * de esa fila. Se llama al iniciar cada pantalla (ES o EN), para
 * que el receptor conserve el idioma que tenia configurado aunque
 * se haya cambiado de pantalla. */
void ui_idioma_receptor_aplicar(int receptor, lv_obj_t *btn_es, lv_obj_t *btn_en, lv_obj_t *btn_it, lv_obj_t *btn_ja)
{
    if (receptor < 0 || receptor > 2) return;
    idioma_t actual = s_receptor_idioma[receptor];

    lv_obj_t *botones[4] = { btn_es, btn_en, btn_it, btn_ja };
    for (int i = 0; i < 4; i++) {
        lv_obj_t *b = botones[i];
        if (b == NULL || !lv_obj_is_valid(b)) continue;
        bool selected = (i == (int)actual);
        lv_obj_set_style_bg_color(b, lv_color_hex(selected ? COLOR_IDIOMA_SELECTED : COLOR_IDIOMA_NORMAL), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(b, selected ? 3 : 2, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

/*---------------------------------------------------------------
 * Sincronizacion del idioma de los receptores con la otra pantalla (S3)
 *
 * Cuando la S3 cambia el idioma del dispositivo, el C6 entrega una trama
 * UART_MSG_IDIOMA_SYNC y esp_now_comm.c llama a este callback. Aqui solo se
 * REFLEJA el cambio (estado + resaltado): los receptores ya fueron avisados
 * por la S3, asi que NO se llama a esp_now_send_idioma_receptor() (eso
 * generaria un eco entre las dos pantallas).
 *
 * Se ejecuta en la tarea UART, por eso todo va dentro de lvgl_port_lock().
 * receptor: 0..2, o 0xFF = los 3 receptores. idioma: 0=ES, 1=EN.
 *--------------------------------------------------------------*/
static void ui_idioma_repintar_filas_visibles(void)
{
    lv_obj_t *activa = lv_screen_active();
    if (activa == NULL) return;

    if (ui_Ajustes_ != NULL && activa == ui_Ajustes_) {
        ui_idioma_receptor_aplicar(0, ui_ButtonidoES,  ui_ButtonidoEN,  ui_ButtonidoIT,  ui_ButtonidoJA);
        ui_idioma_receptor_aplicar(1, ui_ButtonidoES1, ui_ButtonidoEN1, ui_ButtonidoIT1, ui_ButtonidoJA1);
        ui_idioma_receptor_aplicar(2, ui_ButtonidoES2, ui_ButtonidoEN2, ui_ButtonidoIT2, ui_ButtonidoJA2);
    } else if (ui_Ajustes_EN != NULL && activa == ui_Ajustes_EN) {
        ui_idioma_receptor_aplicar(0, ui_ButtonidoES1_EN, ui_ButtonidoEN1__EN, ui_ButtonidoIT1__EN, ui_ButtonidoJA1_EN);
        ui_idioma_receptor_aplicar(1, ui_ButtonidoES2_EN, ui_ButtonidoEN2_EN,  ui_ButtonidoIT2_EN,  ui_ButtonidoJA2_EN);
        ui_idioma_receptor_aplicar(2, ui_ButtonidoES3_EN, ui_ButtonidoEN3_EN,  ui_ButtonidoIT3_EN,  ui_ButtonidoJA3_EN);
    }
    /* Si no esta abierta ninguna pantalla de Ajustes no hay nada que repintar:
     * al abrirla, ui_idioma_receptor_aplicar() leera el estado ya actualizado. */
}

static void ui_idioma_remoto_cb(uint8_t receptor, uint8_t idioma)
{
    if (idioma > 1 || (receptor > 2 && receptor != 0xFF)) return;

    if (!lvgl_port_lock(0)) {
        ESP_LOGW("AJUSTES", "No se pudo tomar el lock de LVGL para sincronizar el idioma");
        return;
    }

    if (receptor == 0xFF) {
        for (int i = 0; i < 3; i++) s_receptor_idioma[i] = (idioma_t)idioma;
    } else {
        s_receptor_idioma[receptor] = (idioma_t)idioma;
    }
    ui_idioma_repintar_filas_visibles();

    lvgl_port_unlock();
}

/* Registrar una sola vez, despues de ui_init(). */
void ui_idioma_sync_init(void)
{
    esp_now_comm_set_idioma_remoto_cb(ui_idioma_remoto_cb);
}

/*---------------------------------------------------------------
 * Switch de WiFi (conexion normal del P4 a internet, independiente
 * del ESP-NOW hacia los receptores). El estado real vive en
 * wifi_manager.c, no aqui: este handler solo prende/apaga el radio
 * y abre/cierra el popup de seleccion de red.
 *--------------------------------------------------------------*/

/* Evita que, al reflejar en el switch el estado guardado durante el
 * init de cada pantalla (ui_wifi_switch_aplicar), se dispare de nuevo
 * este evento como si el usuario lo hubiera tocado. */
static bool s_wifi_switch_sync_en_curso = false;

void ui_event_switch_wifi(lv_event_t * e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED) return;
    if (s_wifi_switch_sync_en_curso) return;

    lv_obj_t *sw = lv_event_get_target(e);
    bool encendido = lv_obj_has_state(sw, LV_STATE_CHECKED);

    esp_err_t err = wifi_manager_set_enabled(encendido);

    if (encendido) {
        if (err != ESP_OK) {
            /* No se pudo encender de verdad: revertir el switch visualmente
             * (sin disparar este mismo evento de nuevo) para no dejarlo
             * mostrando "prendido" cuando en realidad wifi_manager sigue
             * apagado -- si no, el popup se queda para siempre en
             * "Buscando redes..." sin que nadie sepa por que. */
            ESP_LOGE("AJUSTES", "No se pudo encender el WiFi: %s", esp_err_to_name(err));
            s_wifi_switch_sync_en_curso = true;
            lv_obj_remove_state(sw, LV_STATE_CHECKED);
            s_wifi_switch_sync_en_curso = false;
            return;
        }
        ui_wifi_popup_open();
    } else {
        ui_wifi_popup_close();
    }
}

/* Aplica el estado actual del WiFi (encendido/apagado, SSID conectado) al
 * switch y label recien creados por SquareLine. NO dispara
 * ui_event_switch_wifi: cambiar de pantalla (ES/EN) no debe encender ni
 * apagar el WiFi, solo reflejar lo que ya hay -- igual que con el idioma
 * de cada receptor. */
void ui_wifi_switch_aplicar(lv_obj_t *sw, lv_obj_t *label_wifi)
{
    if (sw == NULL || !lv_obj_is_valid(sw)) return;

    s_wifi_switch_sync_en_curso = true;
    if (wifi_manager_is_enabled()) {
        lv_obj_add_state(sw, LV_STATE_CHECKED);
    } else {
        lv_obj_remove_state(sw, LV_STATE_CHECKED);
    }
    s_wifi_switch_sync_en_curso = false;

    if (label_wifi != NULL && lv_obj_is_valid(label_wifi)) {
        const char *ssid = wifi_manager_get_connected_ssid();
        if (wifi_manager_is_enabled() && ssid[0] != '\0') {
            lv_label_set_text_fmt(label_wifi, "Wi-Fi: %s", ssid);
        } else {
            lv_label_set_text(label_wifi, "Wi-Fi");
        }
    }
}

/*---------------------------------------------------------------
 * Switch de Bluetooth (BLE del modulo Wireless C6 externo, el mismo
 * que atiende ESP-NOW). El C6 no reporta de vuelta si de verdad quedo
 * encendido (solo vemos "BT_ON\n"/"BT_ERR\n" en el log de uart_bridge,
 * no hay callback hasta aca), asi que este switch asume que el comando
 * se aplico y guarda ese estado; si la trama se pierde, tocar el switch
 * de nuevo reintenta el comando.
 *--------------------------------------------------------------*/

static bool s_bluetooth_encendido = false;
static bool s_bt_switch_sync_en_curso = false;

void ui_event_switch_bluetooth(lv_event_t * e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED) return;
    if (s_bt_switch_sync_en_curso) return;

    lv_obj_t *sw = lv_event_get_target(e);
    bool encendido = lv_obj_has_state(sw, LV_STATE_CHECKED);

    esp_err_t err = uart_bridge_send_bluetooth(encendido);
    if (err != ESP_OK) {
        ESP_LOGW("AJUSTES", "No se pudo enviar comando de Bluetooth (%s): %s",
                 encendido ? "ON" : "OFF", esp_err_to_name(err));
    }

    s_bluetooth_encendido = encendido;
}

/* Aplica el estado guardado de Bluetooth al switch recien creado por
 * SquareLine, sin disparar ui_event_switch_bluetooth (igual que
 * ui_wifi_switch_aplicar): cambiar de pantalla ES/EN no debe encender
 * ni apagar el Bluetooth, solo reflejar lo que ya hay. */
void ui_bluetooth_switch_aplicar(lv_obj_t *sw)
{
    if (sw == NULL || !lv_obj_is_valid(sw)) return;

    s_bt_switch_sync_en_curso = true;
    if (s_bluetooth_encendido) {
        lv_obj_add_state(sw, LV_STATE_CHECKED);
    } else {
        lv_obj_remove_state(sw, LV_STATE_CHECKED);
    }
    s_bt_switch_sync_en_curso = false;
}

void reset_player_selection(void)
{
    if (s_selected_btn != NULL && lv_obj_is_valid(s_selected_btn)) {
        lv_obj_set_style_border_color(s_selected_btn, lv_color_hex(0x2D3542), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(s_selected_btn, 1, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_invalidate(s_selected_btn);
    }
    s_selected_btn = NULL;
}

lv_obj_t *get_button_main_label(lv_obj_t *btn)
{
    if (btn == NULL || !lv_obj_is_valid(btn)) return NULL;
    uint32_t count = lv_obj_get_child_count(btn);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *child = lv_obj_get_child(btn, i);
        if (child != NULL && lv_obj_check_type(child, &lv_label_class)) {
            return child;
        }
    }
    return NULL;
}

extern void handle_player_swap(lv_obj_t *btn_a, lv_obj_t *btn_b);

static void set_selection_highlight(lv_obj_t *btn, bool selected)
{
    if (btn == NULL || !lv_obj_is_valid(btn)) return;
    if (selected) {
        lv_obj_set_style_border_color(btn, lv_color_hex(COLOR_BTN_SELECTED), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(btn, 3, LV_PART_MAIN | LV_STATE_DEFAULT);
    } else {
        lv_obj_set_style_border_color(btn, lv_color_hex(0x2D3542), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(btn, 1, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    lv_obj_invalidate(btn);
}

static void clear_selection(void)
{
    reset_player_selection();
}

void on_player_btn_clicked(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_current_target(e);
    if (btn == NULL) btn = lv_event_get_target(e);
    if (btn == NULL || !lv_obj_is_valid(btn)) return;

    /* Debounce: el panel táctil puede generar dos eventos LV_EVENT_CLICKED
     * para un mismo toque físico (mismo botón, casi el mismo instante).
     * Se ignora el segundo disparo si llega muy rápido tras el primero. */
    if (btn == s_last_click_btn && lv_tick_elaps(s_last_click_time) < 150) {
        return;
    }
    s_last_click_btn = btn;
    s_last_click_time = lv_tick_get();

    /* Si se vuelve a presionar el mismo botón ya seleccionado, se deselecciona */
    if (s_selected_btn == btn) {
        clear_selection();
        return;
    }

    /* Si no hay ninguno seleccionado previamente, lo seleccionamos */
    if (s_selected_btn == NULL) {
        s_selected_btn = btn;
        set_selection_highlight(btn, true);
        return;
    }

    /* Intercambio de dos jugadores distintos */
    lv_obj_t *other = s_selected_btn;
    clear_selection();
    handle_player_swap(other, btn);
}

void on_player_btn_long_pressed(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_current_target(e);
    if (btn == NULL) btn = lv_event_get_target(e);
    if (btn == NULL || !lv_obj_is_valid(btn)) return;

    clear_selection();
    open_edit_player_popup(btn);
}

void player_btn_long_pressed(lv_event_t *e)
{
    on_player_btn_long_pressed(e);
}

/* ------------------------------------------------------------------
 * Perfil_Bat: cambio entre los 5 paneles de estadisticas
 *   TEMPORADA / ULTIMO JUEGO / ULTIMOS 5 / ULTIMOS 15 / DE POR VIDA
 * ------------------------------------------------------------------ */
enum { PB_TEMP, PB_ULT1, PB_ULT5, PB_ULT15, PB_DPV, PB_N };
static lv_obj_t *s_paneles[PB_N] = { NULL };

/* Oculta los cinco paneles y muestra solo el indicado. */
static void perfil_bat_mostrar(int idx)
{
    for (int i = 0; i < PB_N; i++) {
        if (s_paneles[i]) lv_obj_add_flag(s_paneles[i], LV_OBJ_FLAG_HIDDEN);
    }
    if (s_paneles[idx]) lv_obj_remove_flag(s_paneles[idx], LV_OBJ_FLAG_HIDDEN);
}

/* Se llama al final de ui_Perfil_Bat_screen_init(). Guarda los punteros
 * (se refrescan cada vez que se recrea la pantalla) y deja visible
 * solo el panel de TEMPORADA. */
void ui_perfil_bat_paneles_init(lv_obj_t *panel_temporada, lv_obj_t *panel_ultimo_juego,
                                lv_obj_t *panel_ultimos5, lv_obj_t *panel_ultimos15,
                                lv_obj_t *panel_por_vida)
{
    s_paneles[PB_TEMP]  = panel_temporada;
    s_paneles[PB_ULT1]  = panel_ultimo_juego;
    s_paneles[PB_ULT5]  = panel_ultimos5;
    s_paneles[PB_ULT15] = panel_ultimos15;
    s_paneles[PB_DPV]   = panel_por_vida;

    perfil_bat_mostrar(PB_TEMP);
}

void ui_event_btn_temporada(lv_event_t * e)    { if (lv_event_get_code(e) == LV_EVENT_CLICKED) perfil_bat_mostrar(PB_TEMP);  }
void ui_event_btn_ultimo_juego(lv_event_t * e) { if (lv_event_get_code(e) == LV_EVENT_CLICKED) perfil_bat_mostrar(PB_ULT1);  }
void ui_event_btn_ultimos5(lv_event_t * e)     { if (lv_event_get_code(e) == LV_EVENT_CLICKED) perfil_bat_mostrar(PB_ULT5);  }
void ui_event_btn_ultimos15(lv_event_t * e)    { if (lv_event_get_code(e) == LV_EVENT_CLICKED) perfil_bat_mostrar(PB_ULT15); }
void ui_event_btn_por_vida(lv_event_t * e)     { if (lv_event_get_code(e) == LV_EVENT_CLICKED) perfil_bat_mostrar(PB_DPV);   }
