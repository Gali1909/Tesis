// ui_wifi_popup.c
//
// Overlay de LVGL (no es una pantalla de SquareLine) creado sobre
// lv_layer_top(), asi que se ve igual sin importar si la pantalla activa
// es ui_Ajustes_ (ES) o ui_Ajustes_EN (EN).
//
// Los callbacks de wifi_manager (on_resultados_escaneo, on_cambio_estado)
// llegan aqui ya con el lock de LVGL tomado (ver notificar_estado() y las
// llamadas a s_scan_cb en wifi_manager.c), asi que las funciones de este
// archivo pueden llamar a la API de LVGL sin tomar el lock ellas mismas.

#include "ui_wifi_popup.h"
#include "wifi_manager.h"

#include <stdio.h>
#include <string.h>
#include "lvgl.h"

#define COLOR_FONDO_OVERLAY  0x000000
#define OPA_FONDO_OVERLAY    180
#define COLOR_PANEL          0x1B2029
#define COLOR_BOTON          0x1F2937
#define COLOR_TEXTO          0xE7E9EE
#define COLOR_ACCENTO        0x06D3E4

static lv_obj_t *s_overlay      = NULL;
static lv_obj_t *s_panel        = NULL;
static lv_obj_t *s_status_label = NULL;
static lv_obj_t *s_lista        = NULL;
static lv_obj_t *s_password_ta  = NULL;
static lv_obj_t *s_btn_conectar = NULL;
static lv_obj_t *s_btn_volver   = NULL;
static lv_obj_t *s_keyboard     = NULL;

static char s_ssid_elegido[WIFI_MANAGER_MAX_SSID_LEN] = {0};

/* Copia local de los ultimos resultados: los botones de la lista guardan
 * solo un indice (user_data), y con este arreglo se recupera el SSID y
 * si la red pide contrasena cuando se toca uno. */
static wifi_manager_ap_t s_redes_actuales[WIFI_MANAGER_MAX_SCAN_RESULTS];
static int s_cantidad_actual = 0;

static void mostrar_vista_lista(void);
static void mostrar_vista_password(const char *ssid);
static void cerrar_teclado(void);
static void intentar_conectar(const char *password);

/* ---------------- callbacks de botones/teclado ---------------- */

static void on_btn_cerrar_click(lv_event_t *e)
{
    (void)e;
    ui_wifi_popup_close();
}

static void on_btn_volver_click(lv_event_t *e)
{
    (void)e;
    mostrar_vista_lista();
}

static void on_btn_conectar_click(lv_event_t *e)
{
    (void)e;
    if (s_password_ta == NULL) return;
    intentar_conectar(lv_textarea_get_text(s_password_ta));
}

static void on_keyboard_event(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_READY) {
        intentar_conectar(s_password_ta != NULL ? lv_textarea_get_text(s_password_ta) : "");
    } else if (code == LV_EVENT_CANCEL) {
        mostrar_vista_lista();
    }
}

static void on_red_click(lv_event_t *e)
{
    int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (idx < 0 || idx >= s_cantidad_actual) return;

    wifi_manager_ap_t *red = &s_redes_actuales[idx];
    strncpy(s_ssid_elegido, red->ssid, sizeof(s_ssid_elegido) - 1);
    s_ssid_elegido[sizeof(s_ssid_elegido) - 1] = '\0';

    if (red->requires_password) {
        mostrar_vista_password(red->ssid);
    } else {
        if (s_status_label != NULL) {
            lv_label_set_text_fmt(s_status_label, "Conectando a %s...", red->ssid);
        }
        wifi_manager_connect(red->ssid, NULL);
    }
}

static void intentar_conectar(const char *password)
{
    if (s_ssid_elegido[0] == '\0') return;
    if (s_status_label != NULL) {
        lv_label_set_text_fmt(s_status_label, "Conectando a %s...", s_ssid_elegido);
    }
    wifi_manager_connect(s_ssid_elegido, password);
}

/* ---------------- callbacks de wifi_manager ---------------- */

static void on_resultados_escaneo(const wifi_manager_ap_t *redes, int cantidad)
{
    if (s_lista == NULL || !lv_obj_is_valid(s_lista)) return;

    s_cantidad_actual = 0;
    for (int i = 0; i < cantidad && i < WIFI_MANAGER_MAX_SCAN_RESULTS; i++) {
        s_redes_actuales[i] = redes[i];
        s_cantidad_actual++;
    }

    lv_obj_clean(s_lista);

    if (s_cantidad_actual == 0) {
        lv_list_add_text(s_lista, "No se encontraron redes cerca.");
        return;
    }

    for (int i = 0; i < s_cantidad_actual; i++) {
        char texto[48];
        snprintf(texto, sizeof(texto), "%.32s%s", s_redes_actuales[i].ssid,
                 s_redes_actuales[i].requires_password ? "" : "  (abierta)");

        lv_obj_t *btn = lv_list_add_button(s_lista, LV_SYMBOL_WIFI, texto);
        lv_obj_set_style_bg_color(btn, lv_color_hex(COLOR_BOTON), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(btn, lv_color_hex(COLOR_TEXTO), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_add_event_cb(btn, on_red_click, LV_EVENT_CLICKED, (void *)(intptr_t)i);
    }
}

static void on_cambio_estado(wifi_manager_state_t estado, const char *ssid)
{
    if (s_status_label == NULL || !lv_obj_is_valid(s_status_label)) return;

    switch (estado) {
        case WIFI_MANAGER_STATE_SCANNING:
            lv_label_set_text(s_status_label, "Buscando redes...");
            break;
        case WIFI_MANAGER_STATE_CONNECTING:
            lv_label_set_text_fmt(s_status_label, "Conectando a %s...", ssid);
            break;
        case WIFI_MANAGER_STATE_CONNECTED:
            lv_label_set_text_fmt(s_status_label, "Conectado a %s", ssid);
            cerrar_teclado();
            break;
        case WIFI_MANAGER_STATE_DISCONNECTED:
            lv_label_set_text_fmt(s_status_label, "No se pudo conectar a %s",
                                   (ssid != NULL && ssid[0] != '\0') ? ssid : "la red");
            break;
        case WIFI_MANAGER_STATE_OFF:
        default:
            lv_label_set_text(s_status_label, "");
            break;
    }
}

/* ---------------- vistas ---------------- */

static void cerrar_teclado(void)
{
    if (s_keyboard != NULL) {
        lv_obj_del(s_keyboard);
        s_keyboard = NULL;
    }
}

static void mostrar_vista_lista(void)
{
    cerrar_teclado();
    if (s_password_ta  != NULL) lv_obj_add_flag(s_password_ta, LV_OBJ_FLAG_HIDDEN);
    if (s_btn_conectar != NULL) lv_obj_add_flag(s_btn_conectar, LV_OBJ_FLAG_HIDDEN);
    if (s_btn_volver   != NULL) lv_obj_add_flag(s_btn_volver, LV_OBJ_FLAG_HIDDEN);
    if (s_lista        != NULL) lv_obj_remove_flag(s_lista, LV_OBJ_FLAG_HIDDEN);
}

static void mostrar_vista_password(const char *ssid)
{
    if (s_lista != NULL) lv_obj_add_flag(s_lista, LV_OBJ_FLAG_HIDDEN);

    if (s_password_ta != NULL) {
        lv_textarea_set_text(s_password_ta, "");
        lv_obj_remove_flag(s_password_ta, LV_OBJ_FLAG_HIDDEN);
    }
    if (s_btn_conectar != NULL) lv_obj_remove_flag(s_btn_conectar, LV_OBJ_FLAG_HIDDEN);
    if (s_btn_volver   != NULL) lv_obj_remove_flag(s_btn_volver, LV_OBJ_FLAG_HIDDEN);
    if (s_status_label != NULL) lv_label_set_text_fmt(s_status_label, "Contrasena de %s", ssid);

    cerrar_teclado();
    s_keyboard = lv_keyboard_create(s_overlay);
    lv_obj_set_size(s_keyboard, LV_PCT(100), 200);
    lv_obj_align(s_keyboard, LV_ALIGN_BOTTOM_MID, 0, 0);
    lv_keyboard_set_textarea(s_keyboard, s_password_ta);
    lv_obj_add_event_cb(s_keyboard, on_keyboard_event, LV_EVENT_READY, NULL);
    lv_obj_add_event_cb(s_keyboard, on_keyboard_event, LV_EVENT_CANCEL, NULL);
}

/* ---------------- API publica ---------------- */

void ui_wifi_popup_open(void)
{
    if (s_overlay != NULL) return; /* ya esta abierto */

    s_overlay = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_overlay);
    lv_obj_set_size(s_overlay, LV_PCT(100), LV_PCT(100));
    lv_obj_set_style_bg_color(s_overlay, lv_color_hex(COLOR_FONDO_OVERLAY), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(s_overlay, OPA_FONDO_OVERLAY, LV_PART_MAIN);
    lv_obj_add_flag(s_overlay, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_remove_flag(s_overlay, LV_OBJ_FLAG_SCROLLABLE);

    s_panel = lv_obj_create(s_overlay);
    lv_obj_set_size(s_panel, 460, 380);
    lv_obj_center(s_panel);
    lv_obj_set_style_bg_color(s_panel, lv_color_hex(COLOR_PANEL), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(s_panel, 255, LV_PART_MAIN);
    lv_obj_set_style_radius(s_panel, 12, LV_PART_MAIN);
    lv_obj_remove_flag(s_panel, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *titulo = lv_label_create(s_panel);
    lv_label_set_text(titulo, "Redes WiFi disponibles");
    lv_obj_set_style_text_color(titulo, lv_color_hex(COLOR_TEXTO), LV_PART_MAIN);
    lv_obj_align(titulo, LV_ALIGN_TOP_MID, 0, 8);

    lv_obj_t *btn_cerrar = lv_button_create(s_panel);
    lv_obj_set_size(btn_cerrar, 36, 36);
    lv_obj_align(btn_cerrar, LV_ALIGN_TOP_RIGHT, -6, 6);
    lv_obj_set_style_bg_color(btn_cerrar, lv_color_hex(COLOR_BOTON), LV_PART_MAIN);
    lv_obj_t *lbl_cerrar = lv_label_create(btn_cerrar);
    lv_label_set_text(lbl_cerrar, LV_SYMBOL_CLOSE);
    lv_obj_center(lbl_cerrar);
    lv_obj_add_event_cb(btn_cerrar, on_btn_cerrar_click, LV_EVENT_CLICKED, NULL);

    s_status_label = lv_label_create(s_panel);
    lv_label_set_text(s_status_label, "");
    lv_obj_set_style_text_color(s_status_label, lv_color_hex(COLOR_ACCENTO), LV_PART_MAIN);
    lv_obj_align(s_status_label, LV_ALIGN_TOP_MID, 0, 42);

    s_lista = lv_list_create(s_panel);
    lv_obj_set_size(s_lista, 420, 260);
    lv_obj_align(s_lista, LV_ALIGN_TOP_MID, 0, 74);
    lv_obj_set_style_bg_color(s_lista, lv_color_hex(COLOR_PANEL), LV_PART_MAIN);
    lv_list_add_text(s_lista, "Buscando redes...");

    s_password_ta = lv_textarea_create(s_panel);
    lv_textarea_set_password_mode(s_password_ta, true);
    lv_textarea_set_one_line(s_password_ta, true);
    lv_textarea_set_placeholder_text(s_password_ta, "Contrasena");
    lv_obj_set_width(s_password_ta, 380);
    lv_obj_align(s_password_ta, LV_ALIGN_TOP_MID, 0, 90);
    lv_obj_add_flag(s_password_ta, LV_OBJ_FLAG_HIDDEN);

    s_btn_conectar = lv_button_create(s_panel);
    lv_obj_set_size(s_btn_conectar, 160, 50);
    lv_obj_align(s_btn_conectar, LV_ALIGN_TOP_MID, -85, 150);
    lv_obj_set_style_bg_color(s_btn_conectar, lv_color_hex(COLOR_ACCENTO), LV_PART_MAIN);
    lv_obj_t *lbl_conectar = lv_label_create(s_btn_conectar);
    lv_label_set_text(lbl_conectar, "Conectar");
    lv_obj_center(lbl_conectar);
    lv_obj_add_event_cb(s_btn_conectar, on_btn_conectar_click, LV_EVENT_CLICKED, NULL);
    lv_obj_add_flag(s_btn_conectar, LV_OBJ_FLAG_HIDDEN);

    s_btn_volver = lv_button_create(s_panel);
    lv_obj_set_size(s_btn_volver, 160, 50);
    lv_obj_align(s_btn_volver, LV_ALIGN_TOP_MID, 85, 150);
    lv_obj_set_style_bg_color(s_btn_volver, lv_color_hex(COLOR_BOTON), LV_PART_MAIN);
    lv_obj_t *lbl_volver = lv_label_create(s_btn_volver);
    lv_label_set_text(lbl_volver, "Volver");
    lv_obj_center(lbl_volver);
    lv_obj_add_event_cb(s_btn_volver, on_btn_volver_click, LV_EVENT_CLICKED, NULL);
    lv_obj_add_flag(s_btn_volver, LV_OBJ_FLAG_HIDDEN);

    s_cantidad_actual = 0;
    s_ssid_elegido[0] = '\0';

    wifi_manager_set_state_callback(on_cambio_estado);
    wifi_manager_start_scan(on_resultados_escaneo);
}

void ui_wifi_popup_close(void)
{
    if (s_overlay == NULL) return;

    wifi_manager_set_state_callback(NULL);
    cerrar_teclado();
    lv_obj_del(s_overlay); /* borra tambien panel/lista/textarea/botones, son hijos */

    s_overlay      = NULL;
    s_panel        = NULL;
    s_status_label = NULL;
    s_lista        = NULL;
    s_password_ta  = NULL;
    s_btn_conectar = NULL;
    s_btn_volver   = NULL;
}
