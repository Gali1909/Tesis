#include <stdbool.h>
#include <string.h>
#include "jugadas_dynamic.h"
#include "esp_now_comm.h"  /* esp_now_send_jugada_texto / esp_now_send_cancelar_jugada */
#include "ui.h"    /* for ui_PanelJugadas_es, ui_Boton_agregar1 */

/*---------------------------------------------------------------
 * Popups globales en lv_layer_top() (se crean una sola vez)
 *--------------------------------------------------------------*/
static lv_obj_t *s_overlay     = NULL;  
static lv_obj_t *s_textarea    = NULL;
static lv_obj_t *s_popup_title = NULL;

static lv_obj_t *s_editing_btn = NULL;

static lv_obj_t *s_context_overlay = NULL;
static lv_obj_t *s_context_target  = NULL;

/* Panel de jugadas y botón "+" de la pantalla actualmente activa
 * (ES o EN). Se actualizan cada vez que jugadas_dynamic_init() se
 * llama desde el screen_init correspondiente. */
static lv_obj_t *s_active_panel   = NULL;
static lv_obj_t *s_active_add_btn = NULL;
static bool      s_active_is_en   = false;

/* Labels de los popups compartidos (ES/EN) cuyo texto hay que
 * actualizar según el idioma de la pantalla activa. */
static lv_obj_t *s_ok_label     = NULL;
static lv_obj_t *s_cancel_label = NULL;
static lv_obj_t *s_edit_label   = NULL;
static lv_obj_t *s_delete_label = NULL;

/* Texto de la última jugada enviada por ESP-NOW (para "Repetir jugada").
 * Es global a ambas pantallas (ES/EN): la última jugada enviada es la
 * última, sin importar desde qué pantalla se envió. */
static char s_last_play_text[64] = "";
static bool s_has_last_play      = false;

/*---------------------------------------------------------------
 * Declaraciones adelantadas
 *--------------------------------------------------------------*/
static void attach_context_menu(lv_obj_t *btn);
static void attach_send_action(lv_obj_t *btn);

/*---------------------------------------------------------------
 * Aplica el idioma activo (ES/EN) a los textos fijos de los
 * popups compartidos. Se llama cada vez que se cambia de pantalla.
 *--------------------------------------------------------------*/
static void apply_popup_language(void)
{
    if (s_textarea != NULL) {
        lv_textarea_set_placeholder_text(s_textarea, s_active_is_en ? "Play name" : "Nombre de la jugada");
    }
    if (s_ok_label != NULL) {
        lv_label_set_text(s_ok_label, s_active_is_en ? "Add" : "Agregar");
    }
    if (s_cancel_label != NULL) {
        lv_label_set_text(s_cancel_label, s_active_is_en ? "Cancel" : "Cancelar");
    }
    if (s_edit_label != NULL) {
        lv_label_set_text(s_edit_label, s_active_is_en ? "Edit" : "Editar");
    }
    if (s_delete_label != NULL) {
        lv_label_set_text(s_delete_label, s_active_is_en ? "Delete" : "Borrar");
    }
}

/*---------------------------------------------------------------
 * Helpers del diálogo de texto
 *--------------------------------------------------------------*/
static void close_overlay(void)
{
    if (s_overlay != NULL) {
        lv_obj_add_flag(s_overlay, LV_OBJ_FLAG_HIDDEN);
    }
    if (s_textarea != NULL) {
        lv_textarea_set_text(s_textarea, "");
    }
    s_editing_btn = NULL;
}

static void create_play_button(const char *text)
{
    if (text == NULL || text[0] == '\0' || s_active_panel == NULL) {
        return;
    }

    lv_obj_t *btn = lv_button_create(s_active_panel);
    lv_obj_set_width(btn, 350);
    lv_obj_set_height(btn, 60);

    lv_obj_set_style_bg_color(btn, lv_color_hex(0x1F2937), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_set_style_border_color(btn, lv_color_hex(0x2D3542), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(btn, 1, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_t *label = lv_label_create(btn);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_24, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_center(label);

    if (s_active_add_btn != NULL) {
        lv_obj_move_to_index(btn, lv_obj_get_index(s_active_add_btn));
    }

    attach_context_menu(btn);
    attach_send_action(btn);
}

static lv_obj_t *get_button_label(lv_obj_t *btn)
{
    if (btn == NULL) return NULL;
    return lv_obj_get_child(btn, 0);
}

static void apply_popup_text(void)
{
    if (s_textarea == NULL) return;

    const char *text = lv_textarea_get_text(s_textarea);
    if (text == NULL || text[0] == '\0') {
        return;
    }

    if (s_editing_btn != NULL) {
        lv_obj_t *label = get_button_label(s_editing_btn);
        if (label != NULL) {
            lv_label_set_text(label, text);
        }
    } else {
        create_play_button(text);
    }
}

/*---------------------------------------------------------------
 * Callbacks de botones del diálogo
 *--------------------------------------------------------------*/
static void ok_btn_event_cb(lv_event_t *e)
{
    (void)e;
    apply_popup_text();
    close_overlay();
}

static void cancel_btn_event_cb(lv_event_t *e)
{
    (void)e;
    close_overlay();
}

static void keyboard_event_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);

    if (code == LV_EVENT_READY) {
        apply_popup_text();
        close_overlay();
    } else if (code == LV_EVENT_CANCEL) {
        close_overlay();
    }
}

/*---------------------------------------------------------------
 * Construcción de la ventana de texto
 *--------------------------------------------------------------*/
static void build_add_play_popup(void)
{
    s_overlay = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_overlay);
    lv_obj_set_size(s_overlay, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_color(s_overlay, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(s_overlay, 150, 0);
    lv_obj_clear_flag(s_overlay, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_overlay, LV_OBJ_FLAG_HIDDEN);

    lv_obj_t *box = lv_obj_create(s_overlay);
    lv_obj_set_size(box, 400, 140);
    lv_obj_align(box, LV_ALIGN_TOP_MID, 0, 15);
    lv_obj_set_style_bg_color(box, lv_color_hex(0x111827), 0);
    lv_obj_set_style_bg_opa(box, 255, 0);
    lv_obj_set_style_radius(box, 12, 0);
    lv_obj_clear_flag(box, LV_OBJ_FLAG_SCROLLABLE);

    s_popup_title = lv_label_create(box);
    lv_label_set_text(s_popup_title, "Nueva jugada");
    lv_obj_align(s_popup_title, LV_ALIGN_TOP_MID, 0, 5);

    s_textarea = lv_textarea_create(box);
    lv_textarea_set_one_line(s_textarea, true);
    lv_textarea_set_placeholder_text(s_textarea, "Nombre de la jugada");
    lv_obj_set_width(s_textarea, 360);
    lv_obj_align(s_textarea, LV_ALIGN_TOP_MID, 0, 0);

    lv_obj_t *ok_btn = lv_button_create(box);
    lv_obj_set_size(ok_btn, 100, 40);
    lv_obj_align(ok_btn, LV_ALIGN_BOTTOM_LEFT, 20, -2);
    lv_obj_add_event_cb(ok_btn, ok_btn_event_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *ok_label = lv_label_create(ok_btn);
    lv_label_set_text(ok_label, "Agregar");
    lv_obj_center(ok_label);
    s_ok_label = ok_label;

    lv_obj_t *cancel_btn = lv_button_create(box);
    lv_obj_set_size(cancel_btn, 100, 40);
    lv_obj_align(cancel_btn, LV_ALIGN_BOTTOM_RIGHT, -20, -2);
    lv_obj_add_event_cb(cancel_btn, cancel_btn_event_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *cancel_label = lv_label_create(cancel_btn);
    lv_label_set_text(cancel_label, "Cancelar");
    lv_obj_center(cancel_label);
    s_cancel_label = cancel_label;

    lv_obj_t *kb = lv_keyboard_create(s_overlay);
    lv_keyboard_set_textarea(kb, s_textarea);
    lv_obj_add_event_cb(kb, keyboard_event_cb, LV_EVENT_READY, NULL);
    lv_obj_add_event_cb(kb, keyboard_event_cb, LV_EVENT_CANCEL, NULL);
}

static void open_edit_popup(lv_obj_t *btn)
{
    if (btn == NULL || s_textarea == NULL || s_popup_title == NULL || s_overlay == NULL) return;

    s_editing_btn = btn;

    lv_obj_t *label = get_button_label(btn);
    const char *current_text = (label != NULL) ? lv_label_get_text(label) : "";
    lv_textarea_set_text(s_textarea, current_text);

    lv_label_set_text(s_popup_title, s_active_is_en ? "Edit play" : "Editar jugada");
    lv_obj_clear_flag(s_overlay, LV_OBJ_FLAG_HIDDEN);
}

/*---------------------------------------------------------------
 * Menú contextual (Editar / Borrar)
 *--------------------------------------------------------------*/
static void context_edit_event_cb(lv_event_t *e)
{
    (void)e;
    if (s_context_overlay != NULL) {
        lv_obj_add_flag(s_context_overlay, LV_OBJ_FLAG_HIDDEN);
    }
    if (s_context_target != NULL) {
        open_edit_popup(s_context_target);
    }
}

static void context_delete_event_cb(lv_event_t *e)
{
    (void)e;
    if (s_context_overlay != NULL) {
        lv_obj_add_flag(s_context_overlay, LV_OBJ_FLAG_HIDDEN);
    }
    if (s_context_target != NULL) {
        lv_obj_delete(s_context_target);
        s_context_target = NULL;
    }
}

static void context_cancel_event_cb(lv_event_t *e)
{
    (void)e;
    if (s_context_overlay != NULL) {
        lv_obj_add_flag(s_context_overlay, LV_OBJ_FLAG_HIDDEN);
    }
    s_context_target = NULL;
}

static void build_context_menu(void)
{
    s_context_overlay = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_context_overlay);
    lv_obj_set_size(s_context_overlay, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_color(s_context_overlay, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(s_context_overlay, 120, 0);
    lv_obj_clear_flag(s_context_overlay, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_context_overlay, LV_OBJ_FLAG_HIDDEN);

    lv_obj_add_event_cb(s_context_overlay, context_cancel_event_cb, LV_EVENT_CLICKED, NULL);

    lv_obj_t *box = lv_obj_create(s_context_overlay);
    lv_obj_set_size(box, 220, 130);
    lv_obj_align(box, LV_ALIGN_CENTER, 0, 0);
    lv_obj_set_style_bg_color(box, lv_color_hex(0x111827), 0);
    lv_obj_set_style_bg_opa(box, 255, 0);
    lv_obj_set_style_radius(box, 12, 0);
    lv_obj_set_flex_flow(box, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(box, LV_FLEX_ALIGN_SPACE_EVENLY, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_clear_flag(box, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *edit_btn = lv_button_create(box);
    lv_obj_set_size(edit_btn, 180, 40);
    lv_obj_add_event_cb(edit_btn, context_edit_event_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *edit_label = lv_label_create(edit_btn);
    lv_label_set_text(edit_label, "Editar");
    lv_obj_center(edit_label);
    s_edit_label = edit_label;

    lv_obj_t *delete_btn = lv_button_create(box);
    lv_obj_set_size(delete_btn, 180, 40);
    lv_obj_set_style_bg_color(delete_btn, lv_color_hex(0x7F1D1D), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_add_event_cb(delete_btn, context_delete_event_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *delete_label = lv_label_create(delete_btn);
    lv_label_set_text(delete_label, "Borrar");
    lv_obj_center(delete_label);
    s_delete_label = delete_label;
}

static void play_button_long_press_cb(lv_event_t *e)
{
    s_context_target = lv_event_get_target(e);
    if (s_context_overlay != NULL) {
        lv_obj_clear_flag(s_context_overlay, LV_OBJ_FLAG_HIDDEN);
    }
}

static void attach_context_menu(lv_obj_t *btn)
{
    if (btn == NULL) return;
    lv_obj_add_event_cb(btn, play_button_long_press_cb, LV_EVENT_LONG_PRESSED, NULL);
}

/*---------------------------------------------------------------
 * Envío ESP-NOW: un tap corto sobre una jugada la envía a los
 * 3 receptores. Se usa SHORT_CLICKED (no CLICKED) para que un
 * long-press que abre el menú contextual no dispare también el envío.
 *--------------------------------------------------------------*/
static void play_button_send_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    lv_obj_t *label = get_button_label(btn);
    const char *text = (label != NULL) ? lv_label_get_text(label) : NULL;

    esp_now_send_jugada_texto(text);

    if (text != NULL) {
        strncpy(s_last_play_text, text, sizeof(s_last_play_text) - 1);
        s_last_play_text[sizeof(s_last_play_text) - 1] = '\0';
        s_has_last_play = true;
    }
}

static void attach_send_action(lv_obj_t *btn)
{
    if (btn == NULL) return;
    lv_obj_add_event_cb(btn, play_button_send_cb, LV_EVENT_SHORT_CLICKED, NULL);
}

/*---------------------------------------------------------------
 * Cancelar jugada / Repetir jugada
 *--------------------------------------------------------------*/
static void cancel_jugada_btn_event_cb(lv_event_t *e)
{
    (void)e;
    esp_now_send_cancelar_jugada();
}

static void repeat_jugada_btn_event_cb(lv_event_t *e)
{
    (void)e;
    if (!s_has_last_play) {
        return; /* todavía no se ha enviado ninguna jugada */
    }
    esp_now_send_jugada_texto(s_last_play_text);
}

static void plus_button_event_cb(lv_event_t *e)
{
    (void)e;
    s_editing_btn = NULL;
    if (s_popup_title != NULL) {
        lv_label_set_text(s_popup_title, s_active_is_en ? "New play" : "Nueva jugada");
    }
    if (s_textarea != NULL) {
        lv_textarea_set_text(s_textarea, "");
    }
    if (s_overlay != NULL) {
        lv_obj_clear_flag(s_overlay, LV_OBJ_FLAG_HIDDEN);
    }
}

/*---------------------------------------------------------------
 * Inicialización Pública
 *--------------------------------------------------------------*/
static bool s_popups_built = false;

void jugadas_dynamic_init(lv_obj_t *panel, lv_obj_t *add_btn, bool is_english)
{
    if (!s_popups_built) {
        build_add_play_popup();
        build_context_menu();
        s_popups_built = true;
    }

    /* Recordar el idioma de la pantalla activa y refrescar los
     * textos fijos de los popups compartidos (ES/EN). */
    s_active_is_en = is_english;
    apply_popup_language();

    if (panel == NULL || add_btn == NULL) {
        return;
    }

    /* Recordar cuál pantalla (ES o EN) está activa, para que
     * create_play_button() agregue los botones nuevos al panel
     * correcto y no siempre al de la pantalla en español. */
    s_active_panel   = panel;
    s_active_add_btn = add_btn;

    lv_obj_add_event_cb(add_btn, plus_button_event_cb, LV_EVENT_CLICKED, NULL);

    uint32_t child_count = lv_obj_get_child_count(panel);
    for (uint32_t i = 0; i < child_count; i++) {
        lv_obj_t *child = lv_obj_get_child(panel, i);
        if (child != add_btn) {
            attach_context_menu(child);
            attach_send_action(child);
        }
    }

    /* Cancelar jugada / Repetir jugada: los objetos vienen de "ui.h"
     * (creados por la pantalla ES o EN según corresponda). Se conectan
     * cada vez que se (re)inicializa la pantalla activa. */
    lv_obj_t *cancel_btn = is_english ? ui_Cancelar_jugada1_EN : ui_Cancelar_jugada1;
    lv_obj_t *repeat_btn = is_english ? ui_Repetir_jugada2_EN  : ui_Repetir_jugada2;

    if (cancel_btn != NULL) {
        lv_obj_add_event_cb(cancel_btn, cancel_jugada_btn_event_cb, LV_EVENT_CLICKED, NULL);
    }
    if (repeat_btn != NULL) {
        lv_obj_add_event_cb(repeat_btn, repeat_jugada_btn_event_cb, LV_EVENT_CLICKED, NULL);
    }
}
