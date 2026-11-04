#include <stdbool.h>
#include <string.h>
#include "banca_bullpen_dynamic.h"
#include "ui.h"

/* Declaraciones explícitas de los objetos definidos en ui_Alineacion_es.c */
extern lv_obj_t * ui_BBANCA;
extern lv_obj_t * ui_BULLPEN;
extern lv_obj_t * ui_PanelBanca;
extern lv_obj_t * ui_PanelBullpen;
extern lv_obj_t * ui_Boton_agregar5;
extern lv_obj_t * ui_Boton_agregar4;

#define TAB_COLOR_ACTIVE   0x1F2937
#define TAB_COLOR_INACTIVE 0x000000

static lv_obj_t *s_bb_overlay      = NULL;
static lv_obj_t *s_bb_textarea     = NULL;
static lv_obj_t *s_bb_title        = NULL;
static lv_obj_t *s_bb_editing_btn  = NULL;
static lv_obj_t *s_bb_panel_target = NULL;
static lv_obj_t *s_bb_plus_target  = NULL;
static bool s_bb_popups_built      = false;

/* Prototipos de funciones externas de ui_events.c */
void on_player_btn_clicked(lv_event_t *e);
void on_player_btn_long_pressed(lv_event_t *e);
lv_obj_t *get_button_main_label(lv_obj_t *btn);

/*---------------------------------------------------------------
 * Helpers de Jerarquía para Identificar Posición
 *--------------------------------------------------------------*/
static lv_obj_t *get_btn_badge(lv_obj_t *btn)
{
    if (btn == NULL) return NULL;
    uint32_t count = lv_obj_get_child_count(btn);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *child = lv_obj_get_child(btn, i);
        if (child != NULL && !lv_obj_check_type(child, &lv_label_class)) {
            return child;
        }
    }
    return NULL;
}

static lv_obj_t *get_badge_lbl(lv_obj_t *badge)
{
    if (badge == NULL) return NULL;
    uint32_t count = lv_obj_get_child_count(badge);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *child = lv_obj_get_child(badge, i);
        if (child != NULL && lv_obj_check_type(child, &lv_label_class)) {
            return child;
        }
    }
    return NULL;
}

static const char *get_pos_code(lv_obj_t *btn)
{
    lv_obj_t *badge = get_btn_badge(btn);
    if (badge == NULL) return NULL;
    lv_obj_t *lbl = get_badge_lbl(badge);
    return lbl ? lv_label_get_text(lbl) : NULL;
}

/* Sincronización global entre todos los paneles del sistema */
static void sync_name_global(lv_obj_t *source_btn, const char *new_name)
{
    if (source_btn == NULL || new_name == NULL) return;
    const char *pos = get_pos_code(source_btn);
    if (pos == NULL || pos[0] == '\0') return;

    lv_obj_t *panels[] = {
        ui_PanelTitulares,
        ui_PanelOrdenBate,
        ui_PanelBanca,
        ui_PanelBullpen
    };

    for (int p = 0; p < 4; p++) {
        lv_obj_t *panel = panels[p];
        if (panel == NULL) continue;

        uint32_t count = lv_obj_get_child_count(panel);
        for (uint32_t i = 0; i < count; i++) {
            lv_obj_t *btn = lv_obj_get_child(panel, i);
            if (btn == NULL || btn == source_btn) continue;

            const char *other_pos = get_pos_code(btn);
            if (other_pos != NULL && strcmp(pos, other_pos) == 0) {
                lv_obj_t *lbl = get_button_main_label(btn);
                if (lbl != NULL) {
                    lv_label_set_text(lbl, new_name);
                    lv_obj_invalidate(btn);
                }
            }
        }
    }
}

/*---------------------------------------------------------------
 * Gestión de Pestañas (Banca vs Bullpen)
 *--------------------------------------------------------------*/
static void set_tab_active(lv_obj_t *active_tab, lv_obj_t *inactive_tab)
{
    if (active_tab == NULL || inactive_tab == NULL) return;
    lv_obj_set_style_bg_color(active_tab, lv_color_hex(TAB_COLOR_ACTIVE), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(active_tab, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(inactive_tab, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
}

static void show_banca(void)
{
    if (ui_PanelBanca == NULL || ui_PanelBullpen == NULL) return;
    lv_obj_clear_flag(ui_PanelBanca, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(ui_PanelBullpen, LV_OBJ_FLAG_HIDDEN);
    set_tab_active(ui_BBANCA, ui_BULLPEN);
}

static void show_bullpen(void)
{
    if (ui_PanelBanca == NULL || ui_PanelBullpen == NULL) return;
    lv_obj_clear_flag(ui_PanelBullpen, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(ui_PanelBanca, LV_OBJ_FLAG_HIDDEN);
    set_tab_active(ui_BULLPEN, ui_BBANCA);
}

static void tab_banca_event_cb(lv_event_t *e)
{
    (void)e;
    show_banca();
}

static void tab_bullpen_event_cb(lv_event_t *e)
{
    (void)e;
    show_bullpen();
}

/*---------------------------------------------------------------
 * Popup de Edición y Creación
 *--------------------------------------------------------------*/
static void close_overlay(void)
{
    if (s_bb_overlay != NULL) {
        lv_obj_add_flag(s_bb_overlay, LV_OBJ_FLAG_HIDDEN);
    }
    if (s_bb_textarea != NULL) {
        lv_textarea_set_text(s_bb_textarea, "");
    }
    s_bb_editing_btn = NULL;
    s_bb_panel_target = NULL;
    s_bb_plus_target = NULL;
}

static void create_player_button(lv_obj_t *parent_panel, lv_obj_t *plus_btn, const char *text)
{
    if (text == NULL || text[0] == '\0' || parent_panel == NULL) return;

    lv_obj_t *btn = lv_button_create(parent_panel);
    lv_obj_set_width(btn, 250);
    lv_obj_set_height(btn, 60);

    lv_obj_set_style_bg_color(btn, lv_color_hex(0x1F2937), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(btn, lv_color_hex(0x2D3542), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(btn, 1, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_t *label = lv_label_create(btn);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_20, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_center(label);

    if (plus_btn != NULL) {
        lv_obj_move_to_index(btn, lv_obj_get_index(plus_btn));
    }

    lv_obj_add_event_cb(btn, on_player_btn_clicked, LV_EVENT_CLICKED, NULL);
    lv_obj_add_event_cb(btn, on_player_btn_long_pressed, LV_EVENT_LONG_PRESSED, NULL);
}

static void apply_text(void)
{
    if (s_bb_textarea == NULL) return;
    const char *text = lv_textarea_get_text(s_bb_textarea);
    if (text == NULL || text[0] == '\0') return;

    if (s_bb_editing_btn != NULL) {
        lv_obj_t *label = get_button_main_label(s_bb_editing_btn);
        if (label != NULL) {
            lv_label_set_text(label, text);
            lv_obj_invalidate(s_bb_editing_btn);
        }
        sync_name_global(s_bb_editing_btn, text);
    } else if (s_bb_panel_target != NULL) {
        create_player_button(s_bb_panel_target, s_bb_plus_target, text);
    }
}

static void ok_btn_event_cb(lv_event_t *e)
{
    (void)e;
    apply_text();
    close_overlay();
}

static void cancel_btn_event_cb(lv_event_t *e)
{
    (void)e;
    close_overlay();
}

static void kb_event_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_READY) {
        apply_text();
        close_overlay();
    } else if (code == LV_EVENT_CANCEL) {
        close_overlay();
    }
}

static void build_bb_popup(void)
{
    s_bb_overlay = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_bb_overlay);
    lv_obj_set_size(s_bb_overlay, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_color(s_bb_overlay, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(s_bb_overlay, 150, 0);
    lv_obj_clear_flag(s_bb_overlay, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_bb_overlay, LV_OBJ_FLAG_HIDDEN);

    lv_obj_t *box = lv_obj_create(s_bb_overlay);
    lv_obj_set_size(box, 400, 140);
    lv_obj_align(box, LV_ALIGN_TOP_MID, 0, 15);
    lv_obj_set_style_bg_color(box, lv_color_hex(0x111827), 0);
    lv_obj_set_style_bg_opa(box, 255, 0);
    lv_obj_set_style_radius(box, 12, 0);
    lv_obj_clear_flag(box, LV_OBJ_FLAG_SCROLLABLE);

    s_bb_title = lv_label_create(box);
    lv_label_set_text(s_bb_title, "Editar Jugador");
    lv_obj_align(s_bb_title, LV_ALIGN_TOP_MID, 0, 5);

    s_bb_textarea = lv_textarea_create(box);
    lv_textarea_set_one_line(s_bb_textarea, true);
    lv_textarea_set_placeholder_text(s_bb_textarea, "Nombre del jugador");
    lv_obj_set_width(s_bb_textarea, 360);
    lv_obj_align(s_bb_textarea, LV_ALIGN_TOP_MID, 0, 0);

    lv_obj_t *ok = lv_button_create(box);
    lv_obj_set_size(ok, 100, 40);
    lv_obj_align(ok, LV_ALIGN_BOTTOM_LEFT, 20, -10);
    lv_obj_add_event_cb(ok, ok_btn_event_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *ok_lbl = lv_label_create(ok);
    lv_label_set_text(ok_lbl, "Guardar");
    lv_obj_center(ok_lbl);

    lv_obj_t *can = lv_button_create(box);
    lv_obj_set_size(can, 100, 40);
    lv_obj_align(can, LV_ALIGN_BOTTOM_RIGHT, -20, -10);
    lv_obj_add_event_cb(can, cancel_btn_event_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *can_lbl = lv_label_create(can);
    lv_label_set_text(can_lbl, "Cancelar");
    lv_obj_center(can_lbl);

    lv_obj_t *kb = lv_keyboard_create(s_bb_overlay);
    lv_keyboard_set_textarea(kb, s_bb_textarea);
    lv_obj_add_event_cb(kb, kb_event_cb, LV_EVENT_READY, NULL);
    lv_obj_add_event_cb(kb, kb_event_cb, LV_EVENT_CANCEL, NULL);
}

/*---------------------------------------------------------------
 * Callbacks Botones "+"
 *--------------------------------------------------------------*/
static void plus_banca_event_cb(lv_event_t *e)
{
    (void)e;
    s_bb_editing_btn = NULL;
    s_bb_panel_target = ui_PanelBanca;
    s_bb_plus_target = ui_Boton_agregar5;

    if (s_bb_title != NULL) lv_label_set_text(s_bb_title, "Agregar Jugador Banca");
    if (s_bb_textarea != NULL) lv_textarea_set_text(s_bb_textarea, "");
    if (s_bb_overlay != NULL) lv_obj_clear_flag(s_bb_overlay, LV_OBJ_FLAG_HIDDEN);
}

static void plus_bullpen_event_cb(lv_event_t *e)
{
    (void)e;
    s_bb_editing_btn = NULL;
    s_bb_panel_target = ui_PanelBullpen;
    s_bb_plus_target = ui_Boton_agregar4;

    if (s_bb_title != NULL) lv_label_set_text(s_bb_title, "Agregar Lanzador Bullpen");
    if (s_bb_textarea != NULL) lv_textarea_set_text(s_bb_textarea, "");
    if (s_bb_overlay != NULL) lv_obj_clear_flag(s_bb_overlay, LV_OBJ_FLAG_HIDDEN);
}

/*---------------------------------------------------------------
 * Inicialización Pública
 *--------------------------------------------------------------*/
void banca_bullpen_dynamic_init(void)
{
    if (!s_bb_popups_built) {
        build_bb_popup();
        s_bb_popups_built = true;
    }

    /* Pestañas */
    if (ui_BBANCA != NULL && ui_BULLPEN != NULL) {
        lv_obj_add_event_cb(ui_BBANCA, tab_banca_event_cb, LV_EVENT_CLICKED, NULL);
        lv_obj_add_event_cb(ui_BULLPEN, tab_bullpen_event_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Botones "+" */
    if (ui_Boton_agregar5 != NULL) {
        lv_obj_add_event_cb(ui_Boton_agregar5, plus_banca_event_cb, LV_EVENT_CLICKED, NULL);
    }
    if (ui_Boton_agregar4 != NULL) {
        lv_obj_add_event_cb(ui_Boton_agregar4, plus_bullpen_event_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Asignar eventos a los botones de Panel Banca */
    if (ui_PanelBanca != NULL) {
        uint32_t count = lv_obj_get_child_count(ui_PanelBanca);
        for (uint32_t i = 0; i < count; i++) {
            lv_obj_t *child = lv_obj_get_child(ui_PanelBanca, i);
            if (child != NULL && child != ui_Boton_agregar5) {
                lv_obj_add_event_cb(child, on_player_btn_clicked, LV_EVENT_CLICKED, NULL);
                lv_obj_add_event_cb(child, on_player_btn_long_pressed, LV_EVENT_LONG_PRESSED, NULL);
            }
        }
    }

    /* Asignar eventos a los botones de Panel Bullpen */
    if (ui_PanelBullpen != NULL) {
        uint32_t count = lv_obj_get_child_count(ui_PanelBullpen);
        for (uint32_t i = 0; i < count; i++) {
            lv_obj_t *child = lv_obj_get_child(ui_PanelBullpen, i);
            if (child != NULL && child != ui_Boton_agregar4) {
                lv_obj_add_event_cb(child, on_player_btn_clicked, LV_EVENT_CLICKED, NULL);
                lv_obj_add_event_cb(child, on_player_btn_long_pressed, LV_EVENT_LONG_PRESSED, NULL);
            }
        }
    }

    show_banca();
}