// lanzamientos_dynamic.c
#include <stdbool.h>
#include <stdint.h>
#include "lanzamientos_dynamic.h"
#include "esp_now_comm.h"  /* esp_now_send_pitch_signal / esp_now_send_cancelar */
#include "pitch_filter.h"
#include "ui.h"    /* para ui_Boton_..., ui_Zona1..9, ui_Panelubicacion, ui_Button_Enviar, ui_Button_CancelarLan */

/*---------------------------------------------------------------
 * Estado de selección
 *--------------------------------------------------------------*/
static lv_obj_t   *s_selected_pitch_btn = NULL;
static lv_obj_t   *s_selected_zone_btn  = NULL;
static pitch_type_t s_selected_pitch    = PITCH_NONE;
static int8_t       s_selected_zone     = -1;

/*---------------------------------------------------------------
 * Estilo de botón seleccionado / no seleccionado
 *--------------------------------------------------------------*/
static void set_selected_style(lv_obj_t *btn, bool selected)
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

static void update_send_button_state(void)
{
    bool ready = (s_selected_pitch != PITCH_NONE) && (s_selected_zone != -1);

    if (ui_Button_Enviar == NULL) return;

    if (ready) {
        lv_obj_clear_state(ui_Button_Enviar, LV_STATE_DISABLED);
        lv_obj_set_style_opa(ui_Button_Enviar, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    } else {
        lv_obj_add_state(ui_Button_Enviar, LV_STATE_DISABLED);
        lv_obj_set_style_opa(ui_Button_Enviar, 120, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

/*---------------------------------------------------------------
 * Callback compartido: botones de tipo de lanzamiento
 * (el tipo específico viaja en user_data)
 *--------------------------------------------------------------*/
static void pitch_btn_event_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    pitch_type_t type = (pitch_type_t)(intptr_t)lv_event_get_user_data(e);

    set_selected_style(s_selected_pitch_btn, false);
    set_selected_style(btn, true);

    s_selected_pitch_btn = btn;
    s_selected_pitch = type;

    update_send_button_state();
}

static void attach_pitch_buttons(void)
{
    lv_obj_add_event_cb(ui_Recta,                  pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_RECTA_4C);
    lv_obj_add_event_cb(ui_Boton_Curva,            pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_CURVA);
    lv_obj_add_event_cb(ui_Recta2,                 pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_RECTA_2C);
    lv_obj_add_event_cb(ui_Boton_sinker,           pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SINKER);
    lv_obj_add_event_cb(ui_Boton_cutter,           pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_CUTTER);
    lv_obj_add_event_cb(ui_Boton_SPLITFINGER,      pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SPLITFINGER);
    lv_obj_add_event_cb(ui_Boton_SLIDER,           pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SLIDER);
    lv_obj_add_event_cb(ui_Boton_SWEEPER,          pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SWEEPER);
    lv_obj_add_event_cb(ui_Boton_CAMBIO_DE_VELOCIDAD, pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_CAMBIO_VELOCIDAD);
    lv_obj_add_event_cb(ui_Boton__CIRCLECHANGE,    pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_CIRCLECHANGE);
    lv_obj_add_event_cb(ui_Boton__SPLITTER,        pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_SPLITTER);
    lv_obj_add_event_cb(ui_Boton__TENEDOR,         pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_TENEDOR);
    lv_obj_add_event_cb(ui_Boton__nudillera,       pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_NUDILLERA);
    lv_obj_add_event_cb(ui_Boton__Tirabuzon,       pitch_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)PITCH_TIRABUZON);
}

/*---------------------------------------------------------------
 * Callback compartido: botones de zona (ui_Panelubicacion -> Zona1..Zona9)
 * Se recorren los hijos por índice, así el índice (0-8) es la zona.
 *--------------------------------------------------------------*/
static void zone_btn_event_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    int8_t zone = (int8_t)(intptr_t)lv_event_get_user_data(e);

    set_selected_style(s_selected_zone_btn, false);
    set_selected_style(btn, true);

    s_selected_zone_btn = btn;
    s_selected_zone = zone;

    update_send_button_state();
}

static void attach_zone_buttons(void)
{
    if (ui_Panelubicacion == NULL) return;

    uint32_t count = lv_obj_get_child_count(ui_Panelubicacion);
    for (uint32_t i = 0; i < count && i < 9; i++) {
        lv_obj_t *btn = lv_obj_get_child(ui_Panelubicacion, i);
        lv_obj_add_event_cb(btn, zone_btn_event_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);
    }
}

/*---------------------------------------------------------------
 * Enviar / Cancelar
 *--------------------------------------------------------------*/
static void reset_selection(void)
{
    set_selected_style(s_selected_pitch_btn, false);
    set_selected_style(s_selected_zone_btn, false);
    s_selected_pitch_btn = NULL;
    s_selected_zone_btn  = NULL;
    s_selected_pitch = PITCH_NONE;
    s_selected_zone  = -1;
    update_send_button_state();
}

static void send_btn_event_cb(lv_event_t *e)
{
    (void)e;
    if (s_selected_pitch == PITCH_NONE || s_selected_zone == -1) {
        return; /* botón deshabilitado visualmente, pero por si acaso */
    }

    esp_now_send_pitch_signal(s_selected_pitch, s_selected_zone);

    reset_selection();
}

static void cancel_btn_event_cb(lv_event_t *e)
{
    (void)e;
    /* "Cancelar" en esta pantalla también avisa a los jugadores de que
     * anulen/repitan la última señal recibida, además de limpiar la UI. */
    esp_now_send_cancelar();
    reset_selection();
}

/*---------------------------------------------------------------
 * Inicialización pública
 *--------------------------------------------------------------*/
void lanzamientos_dynamic_init(void)
{
    attach_pitch_buttons();
    attach_zone_buttons();

    if (ui_Button_Enviar != NULL) {
        lv_obj_add_event_cb(ui_Button_Enviar, send_btn_event_cb, LV_EVENT_CLICKED, NULL);
    }
    if (ui_Button_CancelarLan != NULL) {
        lv_obj_add_event_cb(ui_Button_CancelarLan, cancel_btn_event_cb, LV_EVENT_CLICKED, NULL);
    }

    update_send_button_state(); // arranca deshabilitado

    pitch_filter_init();        // filtro por perfil de lanzador (idempotente)
}

/*---------------------------------------------------------------
 * Reset publico (lo usa pitch_filter.c)
 *--------------------------------------------------------------*/
void lanzamientos_dynamic_reset_selection(void)
{
    reset_selection();
}
