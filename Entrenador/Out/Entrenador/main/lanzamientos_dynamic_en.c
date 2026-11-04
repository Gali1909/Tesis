// lanzamientos_dynamic_en.c
//
// Copia paralela de lanzamientos_dynamic.c, adaptada para la pantalla EN
// (ui_LanzamientosUbi_EN). Misma lógica exacta que la versión en español,
// pero apuntando a los objetos "_EN" y con su propio estado estático,
// para no compartir punteros con la pantalla en español.
//
// NOTA: este archivo es intencionalmente una copia -- no se modificó
// lanzamientos_dynamic.c/.h.

#include <stdbool.h>
#include <stdint.h>
#include "lanzamientos_dynamic.h"   /* para el tipo pitch_type_t (compartido, no depende del idioma) */
#include "lanzamientos_dynamic_en.h"
#include "esp_now_comm.h"  /* esp_now_send_pitch_signal / esp_now_send_cancelar */
#include "ui.h"    /* para ui_Boton_..._EN, ui_Zona1..9_EN, ui_Panelubicacion_EN, ui_Button_Enviar1_EN, ui_Button_CancelarLan_EN */

/*---------------------------------------------------------------
 * Estado de selección (propio de la pantalla EN)
 *--------------------------------------------------------------*/
static lv_obj_t   *s_selected_pitch_btn_en = NULL;
static lv_obj_t   *s_selected_zone_btn_en  = NULL;
static pitch_type_t s_selected_pitch_en    = PITCH_NONE;
static int8_t       s_selected_zone_en     = -1;

/*---------------------------------------------------------------
 * Estilo de botón seleccionado / no seleccionado
 *--------------------------------------------------------------*/
static void set_selected_style_en(lv_obj_t *btn, bool selected)
{
    /* El boton puede haberse destruido si SquareLine recreo la pantalla. */
    if (btn == NULL || !lv_obj_is_valid(btn)) return;

    if (selected) {
        lv_obj_set_style_bg_color(btn, lv_color_hex(0x0ABDCF), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_color(btn, lv_color_hex(0x0ABDCF), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(btn, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    } else {
        lv_obj_set_style_bg_color(btn, lv_color_hex(0x1F2937), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(btn, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

static void update_send_button_state_en(void)
{
    bool ready = (s_selected_pitch_en != PITCH_NONE) && (s_selected_zone_en != -1);

    if (ui_Button_Enviar1_EN == NULL) return;

    if (ready) {
        lv_obj_clear_state(ui_Button_Enviar1_EN, LV_STATE_DISABLED);
        lv_obj_set_style_opa(ui_Button_Enviar1_EN, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    } else {
        lv_obj_add_state(ui_Button_Enviar1_EN, LV_STATE_DISABLED);
        lv_obj_set_style_opa(ui_Button_Enviar1_EN, 120, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

/*---------------------------------------------------------------
 * Callback compartido: botones de tipo de lanzamiento
 * (el tipo específico viaja en user_data)
 *--------------------------------------------------------------*/
static void pitch_btn_event_cb_en(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    pitch_type_t type = (pitch_type_t)(intptr_t)lv_event_get_user_data(e);

    set_selected_style_en(s_selected_pitch_btn_en, false);
    set_selected_style_en(btn, true);

    s_selected_pitch_btn_en = btn;
    s_selected_pitch_en = type;

    update_send_button_state_en();
}

static void attach_pitch_buttons_en(void)
{
    if (ui_Recta_EN == NULL || ui_PanelTipos_EN == NULL) return; /* pantalla EN no está creada */

    lv_obj_add_event_cb(ui_Recta_EN,                  pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_RECTA_4C);
    lv_obj_add_event_cb(ui_Boton_Curva_EN,            pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_CURVA);
    lv_obj_add_event_cb(ui_Recta2_EN,                 pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_RECTA_2C);
    lv_obj_add_event_cb(ui_Boton_sinker_EN,           pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SINKER);
    lv_obj_add_event_cb(ui_Boton_cutter_EN,           pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_CUTTER);
    lv_obj_add_event_cb(ui_Boton_SPLITFINGER_EN,      pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SPLITFINGER);
    lv_obj_add_event_cb(ui_Boton_SLIDER_EN,           pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SLIDER);
    lv_obj_add_event_cb(ui_Boton_SWEEPER_EN,          pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SWEEPER);
    lv_obj_add_event_cb(ui_Boton_CAMBIO_DE_VELOCIDAD_EN, pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_CAMBIO_VELOCIDAD);
    lv_obj_add_event_cb(ui_Boton__CIRCLECHANGE_EN,    pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_CIRCLECHANGE);
    lv_obj_add_event_cb(ui_Boton__SPLITTER_EN,        pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SPLITTER);
    lv_obj_add_event_cb(ui_Boton__TENEDOR_EN,         pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_TENEDOR);
    lv_obj_add_event_cb(ui_Boton__nudillera_EN,       pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_NUDILLERA);
    lv_obj_add_event_cb(ui_Boton__Tirabuzon_EN,       pitch_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_TIRABUZON);
}

/*---------------------------------------------------------------
 * Callback compartido: botones de zona (ui_Panelubicacion_EN -> Zona1..Zona9)
 * Se recorren los hijos por índice, así el índice (0-8) es la zona.
 *--------------------------------------------------------------*/
static void zone_btn_event_cb_en(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    int8_t zone = (int8_t)(intptr_t)lv_event_get_user_data(e);

    set_selected_style_en(s_selected_zone_btn_en, false);
    set_selected_style_en(btn, true);

    s_selected_zone_btn_en = btn;
    s_selected_zone_en = zone;

    update_send_button_state_en();
}

static void attach_zone_buttons_en(void)
{
    if (ui_Panelubicacion_EN == NULL) return;

    uint32_t count = lv_obj_get_child_count(ui_Panelubicacion_EN);
    for (uint32_t i = 0; i < count && i < 9; i++) {
        lv_obj_t *btn = lv_obj_get_child(ui_Panelubicacion_EN, i);
        lv_obj_add_event_cb(btn, zone_btn_event_cb_en, LV_EVENT_CLICKED, (void *)(intptr_t)i);
    }
}

/*---------------------------------------------------------------
 * Enviar / Cancelar
 *--------------------------------------------------------------*/
static void reset_selection_en(void)
{
    set_selected_style_en(s_selected_pitch_btn_en, false);
    set_selected_style_en(s_selected_zone_btn_en, false);
    s_selected_pitch_btn_en = NULL;
    s_selected_zone_btn_en  = NULL;
    s_selected_pitch_en = PITCH_NONE;
    s_selected_zone_en  = -1;
    update_send_button_state_en();
}

static void send_btn_event_cb_en(lv_event_t *e)
{
    (void)e;
    if (s_selected_pitch_en == PITCH_NONE || s_selected_zone_en == -1) {
        return; /* botón deshabilitado visualmente, pero por si acaso */
    }

    esp_now_send_pitch_signal(s_selected_pitch_en, s_selected_zone_en);

    reset_selection_en();
}

static void cancel_btn_event_cb_en(lv_event_t *e)
{
    (void)e;
    /* "Cancelar" en esta pantalla también avisa a los jugadores de que
     * anulen/repitan la última señal recibida, además de limpiar la UI. */
    esp_now_send_cancelar();
    reset_selection_en();
}

/*---------------------------------------------------------------
 * Inicialización pública
 *--------------------------------------------------------------*/
void lanzamientos_dynamic_en_init(void)
{
    attach_pitch_buttons_en();
    attach_zone_buttons_en();

    if (ui_Button_Enviar1_EN != NULL) {
        lv_obj_add_event_cb(ui_Button_Enviar1_EN, send_btn_event_cb_en, LV_EVENT_CLICKED, NULL);
    }
    if (ui_Button_CancelarLan_EN != NULL) {
        lv_obj_add_event_cb(ui_Button_CancelarLan_EN, cancel_btn_event_cb_en, LV_EVENT_CLICKED, NULL);
    }

    update_send_button_state_en(); // arranca deshabilitado
}

/*---------------------------------------------------------------
 * Reset publico (lo usa pitch_filter.c)
 *--------------------------------------------------------------*/
void lanzamientos_dynamic_en_reset_selection(void)
{
    reset_selection_en();
}
