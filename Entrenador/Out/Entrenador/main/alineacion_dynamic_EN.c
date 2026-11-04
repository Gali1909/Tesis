#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include "alineacion_dynamic_EN.h"
#include "ui.h"
#include "esp_log.h"

/* Referencias a objetos declarados en ui_Alineacion_EN.c */
extern lv_obj_t * ui_BBANCA_EN;
extern lv_obj_t * ui_BULLPEN_EN;
extern lv_obj_t * ui_BANCA_EN;
extern lv_obj_t * ui_LBULLPEN_EN;
extern lv_obj_t * ui_PanelBanca_EN;
extern lv_obj_t * ui_PanelBullpen_EN;
extern lv_obj_t * ui_PanelTitulares_EN;
extern lv_obj_t * ui_PanelOrdenBate_EN;
extern lv_obj_t * ui_Boton_agregar5_EN;
extern lv_obj_t * ui_Boton_agregar4_EN;
extern lv_obj_t * ui_Boton_agregar3_EN;
extern lv_obj_t * ui_Boton_agregar2_EN;
extern lv_obj_t * ui_Titulares_EN;
extern lv_obj_t * ui_TabOrdenBate_EN;

/* Etiquetas sobre el diamante grafico en inglés (ui_Icampo2_EN) */
extern lv_obj_t * ui_NOMBRE1_EN;   /* P  - PITCHER */
extern lv_obj_t * ui_NOMBRE2_EN;   /* C  - CATCHER */
extern lv_obj_t * ui_NOMBRE3_EN;   /* 1B - FIRST BASE */
extern lv_obj_t * ui_NOMBRE4_EN;   /* 2B - SECOND BASE */
extern lv_obj_t * ui_NOMBRE5_EN;   /* 3B - THIRD BASE */
extern lv_obj_t * ui_NOMBRE6_EN;   /* SS - SHORT STOP */
extern lv_obj_t * ui_NOMBRE7_EN;   /* LF - LEFT FIELDER */
extern lv_obj_t * ui_NOMBRE8_EN;   /* CF - CENTER FIELDER */
extern lv_obj_t * ui_NOMBRE9_EN;   /* RF - RIGHT FIELDER */
extern lv_obj_t * ui_NOMBRE10_EN;  /* DH - DESIGNATED HITTER */

#define TAB_COLOR_ACTIVE   0x1F2937
#define TAB_COLOR_INACTIVE 0x000000

/* Componentes del Popup Modal */
static lv_obj_t *s_overlay_EN         = NULL;
static lv_obj_t *s_modal_box_EN       = NULL;
static lv_obj_t *s_textarea_EN        = NULL;
static lv_obj_t *s_dropdown_pos_EN    = NULL;
static lv_obj_t *s_popup_title_EN     = NULL;
static lv_obj_t *s_ok_btn_EN          = NULL;
static lv_obj_t *s_delete_btn_EN      = NULL;
static lv_obj_t *s_cancel_btn_EN      = NULL;
static lv_obj_t *s_kb_EN              = NULL;

static lv_obj_t *s_editing_btn_EN     = NULL;
static lv_obj_t *s_target_panel_EN    = NULL;
static lv_obj_t *s_plus_btn_target_EN = NULL;

/* Prototipos de ui_events.c */
void on_player_btn_clicked(lv_event_t *e);
void on_player_btn_long_pressed(lv_event_t *e);
lv_obj_t *get_button_main_label(lv_obj_t *btn);
void reset_player_selection(void);

/*---------------------------------------------------------------
 * Tablas de Posiciones (English)
 *--------------------------------------------------------------*/
typedef struct {
    const char *code;
    const char *name;
    uint32_t color_hex;
} pos_info_t;

static const pos_info_t POSICIONES_BANCA_EN[] = {
    {"C",  "CATCHER",           0xE36F10},
    {"1B", "FIRST BASE",        0x0266FF},
    {"2B", "SECOND BASE",       0x0266FF},
    {"3B", "THIRD BASE",        0x0266FF},
    {"SS", "SHORT STOP",        0x0266FF},
    {"LF", "LEFT FIELDER",      0x53AB08},
    {"CF", "CENTER FIELDER",    0x53AB08},
    {"RF", "RIGHT FIELDER",     0x53AB08},
    {"DH", "DESIGNATED HITTER", 0x8304F3},
    {"P",  "PITCHER",           0x81046D}
};
#define TOTAL_POSICIONES_BANCA_EN (sizeof(POSICIONES_BANCA_EN) / sizeof(POSICIONES_BANCA_EN[0]))

static const pos_info_t POSICIONES_BULLPEN_EN[] = {
    {"RHP", "RIGHT PITCHER", 0x81046D},
    {"LHP", "LEFT PITCHER",  0x81046D}
};
#define TOTAL_POSICIONES_BULLPEN_EN (sizeof(POSICIONES_BULLPEN_EN) / sizeof(POSICIONES_BULLPEN_EN[0]))

/*---------------------------------------------------------------
 * Datos de "jugador multi-posición"
 *--------------------------------------------------------------*/
typedef struct {
    uint32_t count;
    char codes[TOTAL_POSICIONES_BANCA_EN][4];
    uint32_t colors[TOTAL_POSICIONES_BANCA_EN];
} multi_pos_data_t;

static void multi_pos_data_delete_cb(lv_event_t *e)
{
    lv_obj_t *obj = lv_event_get_target(e);
    multi_pos_data_t *data = (multi_pos_data_t *)lv_obj_get_user_data(obj);
    if (data != NULL) {
        lv_free(data);
        lv_obj_set_user_data(obj, NULL);
    }
}

static multi_pos_data_t *attach_multi_pos_data(lv_obj_t *btn, const pos_info_t **selected_positions, uint32_t pos_count)
{
    multi_pos_data_t *data = lv_malloc(sizeof(multi_pos_data_t));
    if (data == NULL) return NULL;

    data->count = (pos_count > TOTAL_POSICIONES_BANCA_EN) ? TOTAL_POSICIONES_BANCA_EN : pos_count;
    for (uint32_t i = 0; i < data->count; i++) {
        strncpy(data->codes[i], selected_positions[i]->code, sizeof(data->codes[i]) - 1);
        data->codes[i][sizeof(data->codes[i]) - 1] = '\0';
        data->colors[i] = selected_positions[i]->color_hex;
    }

    lv_obj_remove_event_cb(btn, multi_pos_data_delete_cb);
    lv_obj_add_event_cb(btn, multi_pos_data_delete_cb, LV_EVENT_DELETE, NULL);
    lv_obj_set_user_data(btn, data);
    return data;
}

static uint32_t lookup_position_color_EN(const char *code)
{
    if (code == NULL) return 0x81046D;
    for (uint32_t i = 0; i < TOTAL_POSICIONES_BANCA_EN; i++) {
        if (strcmp(POSICIONES_BANCA_EN[i].code, code) == 0) return POSICIONES_BANCA_EN[i].color_hex;
    }
    for (uint32_t i = 0; i < TOTAL_POSICIONES_BULLPEN_EN; i++) {
        if (strcmp(POSICIONES_BULLPEN_EN[i].code, code) == 0) return POSICIONES_BULLPEN_EN[i].color_hex;
    }
    return 0x81046D;
}

static lv_obj_t *s_pos_multi_container_EN = NULL;
static lv_obj_t *s_pos_checkboxes_EN[TOTAL_POSICIONES_BANCA_EN] = {NULL};

lv_obj_t *get_diamond_label_for_pos_EN(const char *pos_code)
{
    if (pos_code == NULL) return NULL;

    if (strcmp(pos_code, "P")   == 0 || strcmp(pos_code, "RHP") == 0 || strcmp(pos_code, "LHP") == 0) return ui_NOMBRE1_EN;
    if (strcmp(pos_code, "C")   == 0) return ui_NOMBRE2_EN;
    if (strcmp(pos_code, "1B")  == 0) return ui_NOMBRE3_EN;
    if (strcmp(pos_code, "2B")  == 0) return ui_NOMBRE4_EN;
    if (strcmp(pos_code, "3B")  == 0) return ui_NOMBRE5_EN;
    if (strcmp(pos_code, "SS")  == 0) return ui_NOMBRE6_EN;
    if (strcmp(pos_code, "LF")  == 0) return ui_NOMBRE7_EN;
    if (strcmp(pos_code, "CF")  == 0) return ui_NOMBRE8_EN;
    if (strcmp(pos_code, "RF")  == 0) return ui_NOMBRE9_EN;
    if (strcmp(pos_code, "DH")  == 0) return ui_NOMBRE10_EN;

    return NULL;
}

/*---------------------------------------------------------------
 * Helpers de Inspección de Botones
 *--------------------------------------------------------------*/
static lv_obj_t *get_button_badge_panel(lv_obj_t *btn)
{
    if (btn == NULL || !lv_obj_is_valid(btn)) return NULL;
    uint32_t count = lv_obj_get_child_count(btn);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *child = lv_obj_get_child(btn, i);
        if (child != NULL && !lv_obj_check_type(child, &lv_label_class)) return child;
    }
    return NULL;
}

static lv_obj_t *get_badge_label(lv_obj_t *badge)
{
    if (badge == NULL || !lv_obj_is_valid(badge)) return NULL;
    uint32_t count = lv_obj_get_child_count(badge);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *child = lv_obj_get_child(badge, i);
        if (child == NULL) continue;
        if (lv_obj_check_type(child, &lv_label_class)) return child;
        lv_obj_t *found = get_badge_label(child);
        if (found != NULL) return found;
    }
    return NULL;
}

static const char *get_button_pos_code(lv_obj_t *btn)
{
    lv_obj_t *badge = get_button_badge_panel(btn);
    if (badge == NULL) return NULL;
    lv_obj_t *lbl = get_badge_label(badge);
    return lbl ? lv_label_get_text(lbl) : NULL;
}

void sync_name_to_orden_bate_EN(const char *pos_code, const char *new_name, const char *old_name)
{
    if (new_name == NULL || ui_PanelOrdenBate_EN == NULL || !lv_obj_is_valid(ui_PanelOrdenBate_EN)) return;

    uint32_t count = lv_obj_get_child_count(ui_PanelOrdenBate_EN);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *btn = lv_obj_get_child(ui_PanelOrdenBate_EN, i);
        if (btn == NULL || !lv_obj_is_valid(btn) || btn == ui_Boton_agregar2_EN) continue;

        const char *btn_pos = get_button_pos_code(btn);
        lv_obj_t *lbl = get_button_main_label(btn);
        if (lbl == NULL) continue;

        if ((pos_code != NULL && btn_pos != NULL && strcmp(pos_code, btn_pos) == 0 && strcmp(pos_code, "-") != 0) ||
            (old_name != NULL && old_name[0] != '\0' && strcmp(lv_label_get_text(lbl), old_name) == 0)) {
            lv_label_set_text(lbl, new_name);
            lv_obj_invalidate(btn);
        }
    }
}

void sync_name_to_titulares_EN(const char *pos_code, const char *new_name, const char *old_name)
{
    if (new_name == NULL || ui_PanelTitulares_EN == NULL || !lv_obj_is_valid(ui_PanelTitulares_EN)) return;

    uint32_t count = lv_obj_get_child_count(ui_PanelTitulares_EN);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *btn = lv_obj_get_child(ui_PanelTitulares_EN, i);
        if (btn == NULL || !lv_obj_is_valid(btn) || btn == ui_Boton_agregar3_EN) continue;

        const char *btn_pos = get_button_pos_code(btn);
        lv_obj_t *lbl = get_button_main_label(btn);
        if (lbl == NULL) continue;

        if ((pos_code != NULL && btn_pos != NULL && strcmp(pos_code, btn_pos) == 0 && strcmp(pos_code, "-") != 0) ||
            (old_name != NULL && old_name[0] != '\0' && strcmp(lv_label_get_text(lbl), old_name) == 0)) {
            lv_label_set_text(lbl, new_name);
            lv_obj_invalidate(btn);
        }
    }
}

void sync_name_global_EN(lv_obj_t *source_btn, const char *new_name)
{
    if (source_btn == NULL || new_name == NULL) return;
    const char *pos = get_button_pos_code(source_btn);
    if (pos == NULL || pos[0] == '\0' || strcmp(pos, "-") == 0) return;

    lv_obj_t *parent = lv_obj_get_parent(source_btn);

    if (parent == ui_PanelTitulares_EN) {
        sync_name_to_orden_bate_EN(pos, new_name, NULL);
    } else if (parent == ui_PanelOrdenBate_EN) {
        sync_name_to_titulares_EN(pos, new_name, NULL);
    }

    lv_obj_t *diamond_lbl = get_diamond_label_for_pos_EN(pos);
    if (diamond_lbl != NULL && lv_obj_is_valid(diamond_lbl)) {
        lv_label_set_text(diamond_lbl, new_name);
        lv_obj_clear_flag(diamond_lbl, LV_OBJ_FLAG_HIDDEN);
        lv_obj_move_foreground(diamond_lbl);
        lv_obj_invalidate(diamond_lbl);
    }
}

void sync_field_label_only_EN(lv_obj_t *source_btn, const char *new_name)
{
    if (source_btn == NULL || new_name == NULL) return;
    const char *pos = get_button_pos_code(source_btn);
    if (pos == NULL || pos[0] == '\0' || strcmp(pos, "-") == 0) return;

    lv_obj_t *diamond_lbl = get_diamond_label_for_pos_EN(pos);
    if (diamond_lbl != NULL && lv_obj_is_valid(diamond_lbl)) {
        lv_label_set_text(diamond_lbl, new_name);
        lv_obj_clear_flag(diamond_lbl, LV_OBJ_FLAG_HIDDEN);
        lv_obj_move_foreground(diamond_lbl);
        lv_obj_invalidate(diamond_lbl);
    }
}

static void sync_titulares_to_field_EN(void)
{
    if (ui_PanelTitulares_EN == NULL || !lv_obj_is_valid(ui_PanelTitulares_EN)) return;

    uint32_t count = lv_obj_get_child_count(ui_PanelTitulares_EN);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *btn = lv_obj_get_child(ui_PanelTitulares_EN, i);
        if (btn == NULL || !lv_obj_is_valid(btn) || btn == ui_Boton_agregar3_EN) continue;

        const char *pos = get_button_pos_code(btn);
        lv_obj_t *lbl = get_button_main_label(btn);

        if (pos != NULL && lbl != NULL) {
            const char *p_name = lv_label_get_text(lbl);
            lv_obj_t *diamond_lbl = get_diamond_label_for_pos_EN(pos);
            if (diamond_lbl != NULL && lv_obj_is_valid(diamond_lbl)) {
                lv_label_set_text(diamond_lbl, p_name);
                lv_obj_clear_flag(diamond_lbl, LV_OBJ_FLAG_HIDDEN);
                lv_obj_move_foreground(diamond_lbl);
                lv_obj_invalidate(diamond_lbl);
            }
            sync_name_to_orden_bate_EN(pos, p_name, NULL);
        }
    }
}

/*---------------------------------------------------------------
 * Gestión de Pestañas
 *--------------------------------------------------------------*/
static void set_tab_active(lv_obj_t *active_tab, lv_obj_t *inactive_tab)
{
    if (active_tab == NULL || inactive_tab == NULL) return;
    if (!lv_obj_is_valid(active_tab) || !lv_obj_is_valid(inactive_tab)) return;

    lv_obj_set_style_bg_color(active_tab, lv_color_hex(TAB_COLOR_ACTIVE), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(active_tab, 255, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_set_style_bg_color(inactive_tab, lv_color_hex(TAB_COLOR_INACTIVE), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(inactive_tab, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
}

static void show_titulares_EN(void)
{
    if (ui_PanelTitulares_EN == NULL || ui_PanelOrdenBate_EN == NULL) return;
    if (!lv_obj_is_valid(ui_PanelTitulares_EN) || !lv_obj_is_valid(ui_PanelOrdenBate_EN)) return;

    lv_obj_clear_flag(ui_PanelTitulares_EN, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(ui_PanelOrdenBate_EN, LV_OBJ_FLAG_HIDDEN);
    set_tab_active(ui_Titulares_EN, ui_TabOrdenBate_EN);
    lv_obj_update_layout(ui_PanelTitulares_EN);
    lv_obj_invalidate(ui_PanelTitulares_EN);
}

static void show_orden_bate_EN(void)
{
    if (ui_PanelTitulares_EN == NULL || ui_PanelOrdenBate_EN == NULL) return;
    if (!lv_obj_is_valid(ui_PanelTitulares_EN) || !lv_obj_is_valid(ui_PanelOrdenBate_EN)) return;

    lv_obj_clear_flag(ui_PanelOrdenBate_EN, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(ui_PanelTitulares_EN, LV_OBJ_FLAG_HIDDEN);
    set_tab_active(ui_TabOrdenBate_EN, ui_Titulares_EN);
    lv_obj_update_layout(ui_PanelOrdenBate_EN);
    lv_obj_invalidate(ui_PanelOrdenBate_EN);
}

static void show_banca_EN(void)
{
    if (ui_PanelBanca_EN == NULL || ui_PanelBullpen_EN == NULL) return;
    if (!lv_obj_is_valid(ui_PanelBanca_EN) || !lv_obj_is_valid(ui_PanelBullpen_EN)) return;

    lv_obj_add_flag(ui_PanelBullpen_EN, LV_OBJ_FLAG_HIDDEN);
    lv_obj_clear_flag(ui_PanelBanca_EN, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(ui_PanelBanca_EN);

    uint32_t count = lv_obj_get_child_count(ui_PanelBanca_EN);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *child = lv_obj_get_child(ui_PanelBanca_EN, i);
        if (child && lv_obj_is_valid(child)) {
            lv_obj_clear_flag(child, LV_OBJ_FLAG_HIDDEN);
        }
    }

    set_tab_active(ui_BBANCA_EN, ui_BULLPEN_EN);
    lv_obj_update_layout(ui_PanelBanca_EN);
    lv_obj_invalidate(ui_PanelBanca_EN);
}

static void show_bullpen_EN(void)
{
    if (ui_PanelBanca_EN == NULL || ui_PanelBullpen_EN == NULL) return;
    if (!lv_obj_is_valid(ui_PanelBanca_EN) || !lv_obj_is_valid(ui_PanelBullpen_EN)) return;

    lv_obj_add_flag(ui_PanelBanca_EN, LV_OBJ_FLAG_HIDDEN);
    lv_obj_set_flex_flow(ui_PanelBullpen_EN, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(ui_PanelBullpen_EN, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START);

    lv_obj_set_x(ui_PanelBullpen_EN, lv_obj_get_x(ui_PanelBanca_EN));
    lv_obj_set_y(ui_PanelBullpen_EN, lv_obj_get_y(ui_PanelBanca_EN));
    lv_obj_set_size(ui_PanelBullpen_EN, lv_obj_get_width(ui_PanelBanca_EN), lv_obj_get_height(ui_PanelBanca_EN));

    lv_obj_clear_flag(ui_PanelBullpen_EN, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(ui_PanelBullpen_EN);

    uint32_t count = lv_obj_get_child_count(ui_PanelBullpen_EN);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *child = lv_obj_get_child(ui_PanelBullpen_EN, i);
        if (child && lv_obj_is_valid(child)) {
            lv_obj_clear_flag(child, LV_OBJ_FLAG_HIDDEN);
        }
    }

    set_tab_active(ui_BULLPEN_EN, ui_BBANCA_EN);
    lv_obj_update_layout(ui_PanelBullpen_EN);
    lv_obj_invalidate(ui_PanelBullpen_EN);
}

static void tab_titulares_EN_cb(lv_event_t *e)  { (void)e; show_titulares_EN(); }
static void tab_orden_bate_EN_cb(lv_event_t *e) { (void)e; show_orden_bate_EN(); }
static void tab_banca_EN_cb(lv_event_t *e)      { (void)e; show_banca_EN(); }
static void tab_bullpen_EN_cb(lv_event_t *e)    { (void)e; show_bullpen_EN(); }

/*---------------------------------------------------------------
 * Popup Modal
 *--------------------------------------------------------------*/
static void close_overlay_EN(void)
{
    if (s_overlay_EN != NULL && lv_obj_is_valid(s_overlay_EN)) {
        lv_obj_add_flag(s_overlay_EN, LV_OBJ_FLAG_HIDDEN);
    }
    if (s_textarea_EN != NULL && lv_obj_is_valid(s_textarea_EN)) {
        lv_textarea_set_text(s_textarea_EN, "");
    }
    s_editing_btn_EN = NULL;
    s_target_panel_EN = NULL;
    s_plus_btn_target_EN = NULL;
}

static void build_single_badge_visual(lv_obj_t *btn, const char *player_name, const char *code, uint32_t color_hex)
{
    lv_obj_t *badge = lv_obj_create(btn);
    lv_obj_set_size(badge, 40, 40);
    lv_obj_set_align(badge, LV_ALIGN_CENTER);
    lv_obj_set_x(badge, -95);
    lv_obj_set_y(badge, 1);
    lv_obj_remove_flag(badge, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_radius(badge, 25, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(badge, lv_color_hex(color_hex), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(badge, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(badge, lv_color_hex(0x000000), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_opa(badge, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(badge, 2, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_t *lbl_pos = lv_label_create(badge);
    lv_obj_set_align(lbl_pos, LV_ALIGN_CENTER);
    lv_obj_set_x(lbl_pos, -1);
    lv_obj_set_y(lbl_pos, 0);
    lv_label_set_text(lbl_pos, code != NULL ? code : "-");
    lv_obj_set_style_text_color(lbl_pos, lv_color_hex(0x000000), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_text_font(lbl_pos, &lv_font_montserrat_20, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_t *lbl_name = lv_label_create(btn);
    lv_obj_set_align(lbl_name, LV_ALIGN_CENTER);
    lv_obj_set_x(lbl_name, 23);
    lv_obj_set_y(lbl_name, -1);
    lv_label_set_text(lbl_name, player_name);
    lv_obj_set_style_text_color(lbl_name, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_text_font(lbl_name, &lv_font_montserrat_20, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_set_height(btn, 60);
}

static void build_multi_badge_visual(lv_obj_t *btn, const char *player_name, multi_pos_data_t *data)
{
    lv_obj_t *lbl_name = lv_label_create(btn);
    lv_obj_set_align(lbl_name, LV_ALIGN_CENTER);
    lv_obj_set_x(lbl_name, -4);
    lv_obj_set_y(lbl_name, -15);
    lv_label_set_text(lbl_name, player_name);
    lv_obj_set_style_text_color(lbl_name, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_text_font(lbl_name, &lv_font_montserrat_18, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_t *badge_box = lv_obj_create(btn);
    lv_obj_set_size(badge_box, 230, 32);
    lv_obj_set_align(badge_box, LV_ALIGN_CENTER);
    lv_obj_set_x(badge_box, 0);
    lv_obj_set_y(badge_box, 14);
    lv_obj_set_flex_flow(badge_box, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(badge_box, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_scrollbar_mode(badge_box, LV_SCROLLBAR_MODE_OFF);
    lv_obj_remove_flag(badge_box, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_bg_opa(badge_box, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_opa(badge_box, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_all(badge_box, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_column(badge_box, 6, LV_PART_MAIN | LV_STATE_DEFAULT);

    for (uint32_t i = 0; i < data->count; i++) {
        lv_obj_t *badge = lv_obj_create(badge_box);
        lv_obj_set_size(badge, 28, 28);
        lv_obj_remove_flag(badge, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_radius(badge, 14, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(badge, lv_color_hex(data->colors[i]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_opa(badge, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_color(badge, lv_color_hex(0x000000), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_opa(badge, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(badge, 1, LV_PART_MAIN | LV_STATE_DEFAULT);

        lv_obj_t *lbl_pos = lv_label_create(badge);
        lv_obj_set_align(lbl_pos, LV_ALIGN_CENTER);
        lv_label_set_text(lbl_pos, data->codes[i]);
        lv_obj_set_style_text_color(lbl_pos, lv_color_hex(0x000000), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_font(lbl_pos, &lv_font_montserrat_14, LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    lv_obj_set_height(btn, 65);
}

static void create_player_button_full_EN(lv_obj_t *parent_panel, lv_obj_t *plus_btn, const char *player_name, const pos_info_t **selected_positions, uint32_t pos_count)
{
    if (player_name == NULL || player_name[0] == '\0' || parent_panel == NULL || !lv_obj_is_valid(parent_panel)) return;

    lv_obj_t *btn = lv_button_create(parent_panel);
    lv_obj_set_width(btn, 250);

    lv_obj_clear_flag(btn, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_set_style_bg_color(btn, lv_color_hex(0x1F2937), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(btn, lv_color_hex(0x2D3542), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(btn, 1, LV_PART_MAIN | LV_STATE_DEFAULT);

    if (pos_count > 1) {
        multi_pos_data_t *data = attach_multi_pos_data(btn, selected_positions, pos_count);
        build_multi_badge_visual(btn, player_name, data);
    } else {
        const pos_info_t *pos = (pos_count == 1) ? selected_positions[0] : NULL;
        build_single_badge_visual(btn, player_name, pos ? pos->code : "-", pos ? pos->color_hex : 0x81046D);
    }

    if (plus_btn != NULL && lv_obj_is_valid(plus_btn)) {
        uint32_t plus_idx = lv_obj_get_index(plus_btn);
        lv_obj_move_to_index(btn, plus_idx);
    }

    lv_obj_add_event_cb(btn, on_player_btn_clicked, LV_EVENT_CLICKED, NULL);
    lv_obj_add_event_cb(btn, on_player_btn_long_pressed, LV_EVENT_LONG_PRESSED, NULL);

    lv_obj_update_layout(parent_panel);
    lv_obj_invalidate(parent_panel);
}

/*---------------------------------------------------------------
 * Intercambio de jugadores (Swap) en versión EN
 *--------------------------------------------------------------*/
typedef struct {
    char name[64];
    multi_pos_data_t *multi;
    char single_code[4];
} button_snapshot_t;

static void capture_button_snapshot(lv_obj_t *btn, button_snapshot_t *out)
{
    memset(out, 0, sizeof(*out));
    if (btn == NULL || !lv_obj_is_valid(btn)) return;

    lv_obj_t *lbl = get_button_main_label(btn);
    const char *t = lbl != NULL ? lv_label_get_text(lbl) : "";
    strncpy(out->name, t != NULL ? t : "", sizeof(out->name) - 1);

    out->multi = (multi_pos_data_t *)lv_obj_get_user_data(btn);

    const char *code = get_button_pos_code(btn);
    strncpy(out->single_code, code != NULL ? code : "-", sizeof(out->single_code) - 1);
}

static void apply_button_snapshot_EN(lv_obj_t *btn, button_snapshot_t *snap, const char *forced_code)
{
    if (btn == NULL || !lv_obj_is_valid(btn)) return;

    lv_obj_t *panel = lv_obj_get_parent(btn);
    lv_obj_clean(btn);

    lv_obj_set_style_border_color(btn, lv_color_hex(0x2D3542), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(btn, 1, LV_PART_MAIN | LV_STATE_DEFAULT);

    bool is_single_mode_panel = (panel == ui_PanelTitulares_EN || panel == ui_PanelOrdenBate_EN);
    bool show_multi = (snap->multi != NULL && snap->multi->count > 1 && !is_single_mode_panel);

    if (show_multi) {
        build_multi_badge_visual(btn, snap->name, snap->multi);
    } else {
        const char *code = forced_code;
        if (code == NULL) {
            code = (snap->multi != NULL && snap->multi->count >= 1) ? snap->multi->codes[0] : snap->single_code;
        }
        build_single_badge_visual(btn, snap->name, code, lookup_position_color_EN(code));
    }

    lv_obj_remove_event_cb(btn, multi_pos_data_delete_cb);
    if (snap->multi != NULL) {
        lv_obj_add_event_cb(btn, multi_pos_data_delete_cb, LV_EVENT_DELETE, NULL);
    }
    lv_obj_set_user_data(btn, snap->multi);
}

static void perform_swap_EN(lv_obj_t *btn_a, lv_obj_t *btn_b, const char *forced_code)
{
    if (btn_a == NULL || btn_b == NULL || btn_a == btn_b) return;
    if (!lv_obj_is_valid(btn_a) || !lv_obj_is_valid(btn_b)) return;

    lv_obj_t *panel_a = lv_obj_get_parent(btn_a);
    lv_obj_t *panel_b = lv_obj_get_parent(btn_b);

    if (panel_a == panel_b && (panel_a == ui_PanelOrdenBate_EN || panel_a == ui_PanelTitulares_EN)) {
        uint32_t idx_a = lv_obj_get_index(btn_a);
        uint32_t idx_b = lv_obj_get_index(btn_b);

        if (idx_a < idx_b) {
            lv_obj_move_to_index(btn_b, idx_a);
            lv_obj_move_to_index(btn_a, idx_b);
        } else {
            lv_obj_move_to_index(btn_a, idx_b);
            lv_obj_move_to_index(btn_b, idx_a);
        }

        lv_obj_set_style_border_color(btn_a, lv_color_hex(0x2D3542), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(btn_a, 1, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_color(btn_b, lv_color_hex(0x2D3542), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(btn_b, 1, LV_PART_MAIN | LV_STATE_DEFAULT);

        reset_player_selection();
        lv_obj_update_layout(panel_a);
        lv_obj_invalidate(panel_a);
        return;
    }

    button_snapshot_t snap_a, snap_b;
    capture_button_snapshot(btn_a, &snap_a);
    capture_button_snapshot(btn_b, &snap_b);

    const char *code_for_a = NULL;
    const char *code_for_b = NULL;
    if (snap_b.multi != NULL && snap_b.multi->count > 1 && (panel_a == ui_PanelTitulares_EN || panel_a == ui_PanelOrdenBate_EN)) {
        code_for_a = forced_code;
    }
    if (snap_a.multi != NULL && snap_a.multi->count > 1 && (panel_b == ui_PanelTitulares_EN || panel_b == ui_PanelOrdenBate_EN)) {
        code_for_b = forced_code;
    }

    apply_button_snapshot_EN(btn_a, &snap_b, code_for_a);
    apply_button_snapshot_EN(btn_b, &snap_a, code_for_b);

    reset_player_selection();

    if (panel_a == ui_PanelTitulares_EN) {
        lv_obj_t *lbl_a = get_button_main_label(btn_a);
        if (lbl_a != NULL) {
            const char *name_a = lv_label_get_text(lbl_a);
            sync_field_label_only_EN(btn_a, name_a);
            sync_name_to_orden_bate_EN(get_button_pos_code(btn_a), name_a, snap_a.name);
        }
    } else if (panel_a == ui_PanelOrdenBate_EN) {
        lv_obj_t *lbl_a = get_button_main_label(btn_a);
        if (lbl_a != NULL) {
            const char *name_a = lv_label_get_text(lbl_a);
            sync_field_label_only_EN(btn_a, name_a);
            sync_name_to_titulares_EN(get_button_pos_code(btn_a), name_a, snap_a.name);
        }
    }

    if (panel_b == ui_PanelTitulares_EN) {
        lv_obj_t *lbl_b = get_button_main_label(btn_b);
        if (lbl_b != NULL) {
            const char *name_b = lv_label_get_text(lbl_b);
            sync_field_label_only_EN(btn_b, name_b);
            sync_name_to_orden_bate_EN(get_button_pos_code(btn_b), name_b, snap_b.name);
        }
    } else if (panel_b == ui_PanelOrdenBate_EN) {
        lv_obj_t *lbl_b = get_button_main_label(btn_b);
        if (lbl_b != NULL) {
            const char *name_b = lv_label_get_text(lbl_b);
            sync_field_label_only_EN(btn_b, name_b);
            sync_name_to_titulares_EN(get_button_pos_code(btn_b), name_b, snap_b.name);
        }
    }

    lv_obj_invalidate(btn_a);
    lv_obj_invalidate(btn_b);
}

/*---------------------------------------------------------------
 * Position Picker Dialog
 *--------------------------------------------------------------*/
static lv_obj_t *s_pending_swap_a_EN = NULL;
static lv_obj_t *s_pending_swap_b_EN = NULL;
static lv_obj_t *s_pos_pick_overlay_EN = NULL;
static lv_obj_t *s_pos_pick_box_EN = NULL;

static void pos_pick_choice_EN_cb(lv_event_t *e)
{
    const char *code = (const char *)lv_event_get_user_data(e);
    lv_obj_t *btn_a = s_pending_swap_a_EN;
    lv_obj_t *btn_b = s_pending_swap_b_EN;
    s_pending_swap_a_EN = NULL;
    s_pending_swap_b_EN = NULL;

    if (s_pos_pick_overlay_EN != NULL && lv_obj_is_valid(s_pos_pick_overlay_EN)) {
        lv_obj_add_flag(s_pos_pick_overlay_EN, LV_OBJ_FLAG_HIDDEN);
    }

    if (btn_a != NULL && btn_b != NULL && lv_obj_is_valid(btn_a) && lv_obj_is_valid(btn_b)) {
        perform_swap_EN(btn_a, btn_b, code);
    }
}

static void pos_pick_cancel_EN_cb(lv_event_t *e)
{
    (void)e;
    s_pending_swap_a_EN = NULL;
    s_pending_swap_b_EN = NULL;
    reset_player_selection();
    if (s_pos_pick_overlay_EN != NULL && lv_obj_is_valid(s_pos_pick_overlay_EN)) {
        lv_obj_add_flag(s_pos_pick_overlay_EN, LV_OBJ_FLAG_HIDDEN);
    }
}

static void show_position_picker_EN(multi_pos_data_t *data)
{
    if (data == NULL) return;

    if (s_pos_pick_overlay_EN == NULL || !lv_obj_is_valid(s_pos_pick_overlay_EN)) {
        s_pos_pick_overlay_EN = lv_obj_create(lv_layer_top());
        lv_obj_remove_style_all(s_pos_pick_overlay_EN);
        lv_obj_set_size(s_pos_pick_overlay_EN, lv_pct(100), lv_pct(100));
        lv_obj_set_style_bg_color(s_pos_pick_overlay_EN, lv_color_black(), 0);
        lv_obj_set_style_bg_opa(s_pos_pick_overlay_EN, 160, 0);
        lv_obj_clear_flag(s_pos_pick_overlay_EN, LV_OBJ_FLAG_SCROLLABLE);

        s_pos_pick_box_EN = lv_obj_create(s_pos_pick_overlay_EN);
        lv_obj_set_width(s_pos_pick_box_EN, 320);
        lv_obj_set_height(s_pos_pick_box_EN, 450);
        lv_obj_align(s_pos_pick_box_EN, LV_ALIGN_TOP_MID, 0, 40);
        lv_obj_set_style_bg_color(s_pos_pick_box_EN, lv_color_hex(0x111827), 0);
        lv_obj_set_style_bg_opa(s_pos_pick_box_EN, 255, 0);
        lv_obj_set_style_border_color(s_pos_pick_box_EN, lv_color_hex(0x374151), 0);
        lv_obj_set_style_border_width(s_pos_pick_box_EN, 2, 0);
        lv_obj_set_style_radius(s_pos_pick_box_EN, 14, 0);
        lv_obj_set_flex_flow(s_pos_pick_box_EN, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_flex_align(s_pos_pick_box_EN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_all(s_pos_pick_box_EN, 14, 0);
        lv_obj_set_style_pad_row(s_pos_pick_box_EN, 8, 0);
        lv_obj_set_scroll_dir(s_pos_pick_box_EN, LV_DIR_VER);
        lv_obj_set_scrollbar_mode(s_pos_pick_box_EN, LV_SCROLLBAR_MODE_AUTO);

        lv_obj_t *title = lv_label_create(s_pos_pick_box_EN);
        lv_label_set_text(title, "Which position will they play?");
        lv_obj_set_style_text_color(title, lv_color_hex(0xFFFFFF), 0);
        lv_obj_set_style_text_font(title, &lv_font_montserrat_18, 0);
        lv_obj_add_flag(title, LV_OBJ_FLAG_IGNORE_LAYOUT);
        lv_obj_set_align(title, LV_ALIGN_TOP_MID);
        lv_obj_set_x(title, 0);
        lv_obj_set_y(title, 10);
    } else {
        uint32_t count = lv_obj_get_child_count(s_pos_pick_box_EN);
        for (uint32_t i = count; i > 1; i--) {
            lv_obj_t *child = lv_obj_get_child(s_pos_pick_box_EN, i - 1);
            if (child != NULL) lv_obj_delete(child);
        }
        lv_obj_clear_flag(s_pos_pick_overlay_EN, LV_OBJ_FLAG_HIDDEN);
    }

    const lv_coord_t POS_BTN_START_Y = 50;
    const lv_coord_t POS_BTN_SPACING = 50;
    const lv_coord_t POS_BTN_X       = 0;

    for (uint32_t i = 0; i < data->count; i++) {
        lv_obj_t *opt = lv_button_create(s_pos_pick_box_EN);
        lv_obj_set_width(opt, 280);
        lv_obj_set_height(opt, 42);
        lv_obj_set_style_bg_color(opt, lv_color_hex(data->colors[i]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_radius(opt, 8, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_add_flag(opt, LV_OBJ_FLAG_IGNORE_LAYOUT);
        lv_obj_set_align(opt, LV_ALIGN_TOP_MID);
        lv_obj_set_x(opt, POS_BTN_X);
        lv_obj_set_y(opt, POS_BTN_START_Y + (lv_coord_t)i * POS_BTN_SPACING);

        lv_obj_t *lbl = lv_label_create(opt);
        lv_label_set_text(lbl, data->codes[i]);
        lv_obj_set_style_text_color(lbl, lv_color_hex(0x000000), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_font(lbl, &lv_font_montserrat_18, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_center(lbl);

        lv_obj_add_event_cb(opt, pos_pick_choice_EN_cb, LV_EVENT_CLICKED, (void *)data->codes[i]);
    }

    const lv_coord_t CANCEL_BTN_X = 0;
    const lv_coord_t CANCEL_BTN_Y = POS_BTN_START_Y + (lv_coord_t)data->count * POS_BTN_SPACING + 10;

    lv_obj_t *cancel = lv_button_create(s_pos_pick_box_EN);
    lv_obj_set_width(cancel, 280);
    lv_obj_set_height(cancel, 38);
    lv_obj_set_style_bg_color(cancel, lv_color_hex(0x374151), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(cancel, 8, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_add_flag(cancel, LV_OBJ_FLAG_IGNORE_LAYOUT);
    lv_obj_set_align(cancel, LV_ALIGN_TOP_MID);
    lv_obj_set_x(cancel, CANCEL_BTN_X);
    lv_obj_set_y(cancel, CANCEL_BTN_Y);
    lv_obj_t *lbl_c = lv_label_create(cancel);
    lv_label_set_text(lbl_c, "Cancel");
    lv_obj_set_style_text_color(lbl_c, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_center(lbl_c);
    lv_obj_add_event_cb(cancel, pos_pick_cancel_EN_cb, LV_EVENT_CLICKED, NULL);

    lv_obj_clear_flag(s_pos_pick_overlay_EN, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(s_pos_pick_overlay_EN);
}

/* Redireccionador invocado desde ui_events.c para manejar swap en pantalla EN */
static bool is_EN_player_btn(lv_obj_t *btn)
{
    if (!btn || !lv_obj_is_valid(btn)) return false;
    lv_obj_t *p = lv_obj_get_parent(btn);
    return (p == ui_PanelTitulares_EN || p == ui_PanelOrdenBate_EN ||
            p == ui_PanelBanca_EN || p == ui_PanelBullpen_EN);
}

void handle_player_swap_EN(lv_obj_t *btn_a, lv_obj_t *btn_b)
{
    if (btn_a == NULL || btn_b == NULL || btn_a == btn_b) return;
    if (!lv_obj_is_valid(btn_a) || !lv_obj_is_valid(btn_b)) return;

    multi_pos_data_t *data_a = (multi_pos_data_t *)lv_obj_get_user_data(btn_a);
    multi_pos_data_t *data_b = (multi_pos_data_t *)lv_obj_get_user_data(btn_b);
    lv_obj_t *panel_a = lv_obj_get_parent(btn_a);
    lv_obj_t *panel_b = lv_obj_get_parent(btn_b);

    if (panel_a == panel_b && (panel_a == ui_PanelOrdenBate_EN || panel_a == ui_PanelTitulares_EN)) {
        perform_swap_EN(btn_a, btn_b, NULL);
        return;
    }

    bool a_needs_choice = (data_a != NULL && data_a->count > 1 && (panel_b == ui_PanelTitulares_EN || panel_b == ui_PanelOrdenBate_EN));
    bool b_needs_choice = (data_b != NULL && data_b->count > 1 && (panel_a == ui_PanelTitulares_EN || panel_a == ui_PanelOrdenBate_EN));

    if (a_needs_choice || b_needs_choice) {
        s_pending_swap_a_EN = btn_a;
        s_pending_swap_b_EN = btn_b;
        show_position_picker_EN(a_needs_choice ? data_a : data_b);
        return;
    }

    perform_swap_EN(btn_a, btn_b, NULL);
}

static void apply_popup_text_EN(void)
{
    if (s_textarea_EN == NULL || !lv_obj_is_valid(s_textarea_EN)) return;
    const char *text = lv_textarea_get_text(s_textarea_EN);
    if (text == NULL || text[0] == '\0') return;

    if (s_editing_btn_EN != NULL && lv_obj_is_valid(s_editing_btn_EN)) {
        lv_obj_t *label = get_button_main_label(s_editing_btn_EN);
        char old_name[64] = "";
        if (label != NULL) {
            strncpy(old_name, lv_label_get_text(label), sizeof(old_name) - 1);
            lv_label_set_text(label, text);
            lv_obj_invalidate(s_editing_btn_EN);
        }
        lv_obj_t *parent = lv_obj_get_parent(s_editing_btn_EN);
        if (parent == ui_PanelTitulares_EN || parent == ui_PanelOrdenBate_EN) {
            sync_name_global_EN(s_editing_btn_EN, text);
        }
    } else if (s_target_panel_EN != NULL && lv_obj_is_valid(s_target_panel_EN)) {
        const pos_info_t *selected_positions[TOTAL_POSICIONES_BANCA_EN];
        uint32_t pos_count = 0;

        if (s_target_panel_EN == ui_PanelBanca_EN) {
            for (uint32_t i = 0; i < TOTAL_POSICIONES_BANCA_EN; i++) {
                lv_obj_t *cb = s_pos_checkboxes_EN[i];
                if (cb != NULL && lv_obj_is_valid(cb) && lv_obj_has_state(cb, LV_STATE_CHECKED)) {
                    selected_positions[pos_count++] = &POSICIONES_BANCA_EN[i];
                }
            }
        } else if (s_target_panel_EN == ui_PanelBullpen_EN) {
            if (s_dropdown_pos_EN != NULL && lv_obj_is_valid(s_dropdown_pos_EN)) {
                uint16_t selected_idx = lv_dropdown_get_selected(s_dropdown_pos_EN);
                if (selected_idx < TOTAL_POSICIONES_BULLPEN_EN) {
                    selected_positions[pos_count++] = &POSICIONES_BULLPEN_EN[selected_idx];
                }
            }
        }

        create_player_button_full_EN(s_target_panel_EN, s_plus_btn_target_EN, text, selected_positions, pos_count);
    }
}

static void ok_btn_EN_cb(lv_event_t *e)     { (void)e; apply_popup_text_EN(); close_overlay_EN(); }
static void cancel_btn_EN_cb(lv_event_t *e) { (void)e; close_overlay_EN(); }

static void delete_btn_EN_cb(lv_event_t *e)
{
    (void)e;
    if (s_editing_btn_EN != NULL && lv_obj_is_valid(s_editing_btn_EN)) {
        lv_obj_delete_async(s_editing_btn_EN);
        s_editing_btn_EN = NULL;
    }
    close_overlay_EN();
}

static void keyboard_EN_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_READY) {
        if (s_kb_EN != NULL && lv_obj_is_valid(s_kb_EN)) {
            lv_obj_add_flag(s_kb_EN, LV_OBJ_FLAG_HIDDEN);
        }
    } else if (code == LV_EVENT_CANCEL) {
        close_overlay_EN();
    }
}

static void textarea_EN_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_CLICKED || code == LV_EVENT_FOCUSED) {
        if (s_kb_EN != NULL && lv_obj_is_valid(s_kb_EN)) {
            lv_keyboard_set_textarea(s_kb_EN, s_textarea_EN);
            lv_obj_clear_flag(s_kb_EN, LV_OBJ_FLAG_HIDDEN);
            lv_obj_move_foreground(s_kb_EN);
        }
    }
}

static void build_add_player_popup_EN_if_needed(void)
{
    if (s_overlay_EN != NULL && lv_obj_is_valid(s_overlay_EN)) return;

    s_overlay_EN = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_overlay_EN);
    lv_obj_set_size(s_overlay_EN, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_color(s_overlay_EN, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(s_overlay_EN, 160, 0);
    lv_obj_clear_flag(s_overlay_EN, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_overlay_EN, LV_OBJ_FLAG_HIDDEN);

    s_modal_box_EN = lv_obj_create(s_overlay_EN);
    lv_obj_set_size(s_modal_box_EN, 420, 270);
    lv_obj_align(s_modal_box_EN, LV_ALIGN_TOP_MID, 0, 10);
    lv_obj_set_scrollbar_mode(s_modal_box_EN, LV_SCROLLBAR_MODE_OFF);
    lv_obj_set_style_bg_color(s_modal_box_EN, lv_color_hex(0x111827), 0);
    lv_obj_set_style_bg_opa(s_modal_box_EN, 255, 0);
    lv_obj_set_style_border_color(s_modal_box_EN, lv_color_hex(0x374151), 0);
    lv_obj_set_style_border_width(s_modal_box_EN, 2, 0);
    lv_obj_set_style_radius(s_modal_box_EN, 14, 0);
    lv_obj_clear_flag(s_modal_box_EN, LV_OBJ_FLAG_SCROLLABLE);

    s_popup_title_EN = lv_label_create(s_modal_box_EN);
    lv_label_set_text(s_popup_title_EN, "Add Player");
    lv_obj_align(s_popup_title_EN, LV_ALIGN_TOP_MID, 0, -5);
    lv_obj_set_style_text_color(s_popup_title_EN, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_text_font(s_popup_title_EN, &lv_font_montserrat_20, LV_PART_MAIN | LV_STATE_DEFAULT);

    s_textarea_EN = lv_textarea_create(s_modal_box_EN);
    lv_textarea_set_one_line(s_textarea_EN, true);
    lv_textarea_set_placeholder_text(s_textarea_EN, "Player name...");
    lv_obj_set_width(s_textarea_EN, 380);
    lv_obj_set_height(s_textarea_EN, 40);
    lv_obj_align(s_textarea_EN, LV_ALIGN_TOP_MID, 0, 31);
    
    lv_obj_set_scroll_dir(s_textarea_EN, LV_DIR_HOR);
    lv_obj_set_scrollbar_mode(s_textarea_EN, LV_SCROLLBAR_MODE_OFF);
    lv_obj_set_style_pad_top(s_textarea_EN, 6, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_bottom(s_textarea_EN, 6, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_left(s_textarea_EN, 10, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_right(s_textarea_EN, 10, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(s_textarea_EN, lv_color_hex(0x1F2937), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_text_color(s_textarea_EN, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(s_textarea_EN, lv_color_hex(0x4B5563), LV_PART_MAIN | LV_STATE_DEFAULT);
    
    lv_obj_add_event_cb(s_textarea_EN, textarea_EN_cb, LV_EVENT_ALL, NULL);

    s_dropdown_pos_EN = lv_dropdown_create(s_modal_box_EN);
    lv_obj_set_width(s_dropdown_pos_EN, 380);
    lv_obj_set_height(s_dropdown_pos_EN, 42);
    lv_obj_align(s_dropdown_pos_EN, LV_ALIGN_TOP_MID, 0, 98);
    lv_obj_set_style_bg_color(s_dropdown_pos_EN, lv_color_hex(0x1F2937), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_text_color(s_dropdown_pos_EN, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(s_dropdown_pos_EN, lv_color_hex(0x4B5563), LV_PART_MAIN | LV_STATE_DEFAULT);

    s_pos_multi_container_EN = lv_obj_create(s_modal_box_EN);
    lv_obj_set_width(s_pos_multi_container_EN, 380);
    lv_obj_set_height(s_pos_multi_container_EN, 190);
    lv_obj_align(s_pos_multi_container_EN, LV_ALIGN_TOP_MID, 0, 80);
    lv_obj_set_flex_flow(s_pos_multi_container_EN, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_scroll_dir(s_pos_multi_container_EN, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(s_pos_multi_container_EN, LV_SCROLLBAR_MODE_OFF);
    lv_obj_set_style_bg_color(s_pos_multi_container_EN, lv_color_hex(0x1F2937), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(s_pos_multi_container_EN, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(s_pos_multi_container_EN, lv_color_hex(0x4B5563), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(s_pos_multi_container_EN, 1, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_all(s_pos_multi_container_EN, 6, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_row(s_pos_multi_container_EN, 4, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_add_flag(s_pos_multi_container_EN, LV_OBJ_FLAG_HIDDEN);

    for (uint32_t i = 0; i < TOTAL_POSICIONES_BANCA_EN; i++) {
        lv_obj_t *cb = lv_checkbox_create(s_pos_multi_container_EN);
        char cb_label[50];
        snprintf(cb_label, sizeof(cb_label), "%s - %s", POSICIONES_BANCA_EN[i].code, POSICIONES_BANCA_EN[i].name);
        lv_checkbox_set_text(cb, cb_label);
        lv_obj_set_style_text_color(cb, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
        s_pos_checkboxes_EN[i] = cb;
    }

    s_ok_btn_EN = lv_button_create(s_modal_box_EN);
    lv_obj_set_size(s_ok_btn_EN, 110, 42);
    lv_obj_align(s_ok_btn_EN, LV_ALIGN_BOTTOM_LEFT, 15, -6);
    lv_obj_set_style_bg_color(s_ok_btn_EN, lv_color_hex(0xE36F10), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(s_ok_btn_EN, 8, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_add_event_cb(s_ok_btn_EN, ok_btn_EN_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *ok_label = lv_label_create(s_ok_btn_EN);
    lv_label_set_text(ok_label, "Save");
    lv_obj_set_style_text_color(ok_label, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_center(ok_label);

    s_delete_btn_EN = lv_button_create(s_modal_box_EN);
    lv_obj_set_size(s_delete_btn_EN, 110, 42);
    lv_obj_align(s_delete_btn_EN, LV_ALIGN_BOTTOM_MID, 0, -6);
    lv_obj_set_style_bg_color(s_delete_btn_EN, lv_color_hex(0xDC2626), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(s_delete_btn_EN, 8, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_add_event_cb(s_delete_btn_EN, delete_btn_EN_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *del_label = lv_label_create(s_delete_btn_EN);
    lv_label_set_text(del_label, "Delete");
    lv_obj_set_style_text_color(del_label, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_center(del_label);

    s_cancel_btn_EN = lv_button_create(s_modal_box_EN);
    lv_obj_set_size(s_cancel_btn_EN, 110, 42);
    lv_obj_align(s_cancel_btn_EN, LV_ALIGN_BOTTOM_RIGHT, -15, -6);
    lv_obj_set_style_bg_color(s_cancel_btn_EN, lv_color_hex(0x374151), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(s_cancel_btn_EN, 8, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_add_event_cb(s_cancel_btn_EN, cancel_btn_EN_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *cancel_label = lv_label_create(s_cancel_btn_EN);
    lv_label_set_text(cancel_label, "Cancel");
    lv_obj_set_style_text_color(cancel_label, lv_color_hex(0xFFFFFF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_center(cancel_label);

    s_kb_EN = lv_keyboard_create(s_overlay_EN);
    lv_keyboard_set_textarea(s_kb_EN, s_textarea_EN);
    lv_obj_add_event_cb(s_kb_EN, keyboard_EN_cb, LV_EVENT_READY, NULL);
    lv_obj_add_event_cb(s_kb_EN, keyboard_EN_cb, LV_EVENT_CANCEL, NULL);
}

void open_edit_player_popup_EN(lv_obj_t *btn)
{
    if (btn == NULL || !lv_obj_is_valid(btn)) return;
    build_add_player_popup_EN_if_needed();

    s_editing_btn_EN = btn;
    s_target_panel_EN = NULL;

    if (s_dropdown_pos_EN != NULL) lv_obj_add_flag(s_dropdown_pos_EN, LV_OBJ_FLAG_HIDDEN);
    if (s_pos_multi_container_EN != NULL) lv_obj_add_flag(s_pos_multi_container_EN, LV_OBJ_FLAG_HIDDEN);
    if (s_delete_btn_EN != NULL) lv_obj_clear_flag(s_delete_btn_EN, LV_OBJ_FLAG_HIDDEN);

    if (s_ok_btn_EN != NULL) {
        lv_obj_set_size(s_ok_btn_EN, 110, 42);
        lv_obj_align(s_ok_btn_EN, LV_ALIGN_BOTTOM_LEFT, 15, -6);
    }
    if (s_cancel_btn_EN != NULL) {
        lv_obj_set_size(s_cancel_btn_EN, 110, 42);
        lv_obj_align(s_cancel_btn_EN, LV_ALIGN_BOTTOM_RIGHT, -15, -6);
    }
    if (s_modal_box_EN != NULL) lv_obj_set_height(s_modal_box_EN, 175);
    if (s_kb_EN != NULL && lv_obj_is_valid(s_kb_EN)) lv_obj_clear_flag(s_kb_EN, LV_OBJ_FLAG_HIDDEN);

    lv_obj_t *label = get_button_main_label(btn);
    lv_textarea_set_text(s_textarea_EN, label ? lv_label_get_text(label) : "");
    lv_obj_scroll_to_y(s_textarea_EN, 0, LV_ANIM_OFF);
    lv_label_set_text(s_popup_title_EN, "Edit / Delete Player");
    lv_obj_clear_flag(s_overlay_EN, LV_OBJ_FLAG_HIDDEN);
}

static void plus_btn_EN_cb(lv_event_t *e)
{
    lv_obj_t *target = lv_event_get_target(e);
    build_add_player_popup_EN_if_needed();

    s_editing_btn_EN = NULL;

    if (s_delete_btn_EN != NULL) lv_obj_add_flag(s_delete_btn_EN, LV_OBJ_FLAG_HIDDEN);
    if (s_ok_btn_EN != NULL) {
        lv_obj_set_size(s_ok_btn_EN, 130, 42);
        lv_obj_align(s_ok_btn_EN, LV_ALIGN_BOTTOM_LEFT, 15, -6);
    }
    if (s_cancel_btn_EN != NULL) {
        lv_obj_set_size(s_cancel_btn_EN, 130, 42);
        lv_obj_align(s_cancel_btn_EN, LV_ALIGN_BOTTOM_RIGHT, -15, -6);
    }
    if (s_kb_EN != NULL && lv_obj_is_valid(s_kb_EN)) lv_obj_clear_flag(s_kb_EN, LV_OBJ_FLAG_HIDDEN);

    if (target == ui_Boton_agregar5_EN) {
        s_target_panel_EN = ui_PanelBanca_EN; 
        s_plus_btn_target_EN = ui_Boton_agregar5_EN;
        lv_label_set_text(s_popup_title_EN, "Add Bench Player");

        if (s_dropdown_pos_EN != NULL) lv_obj_add_flag(s_dropdown_pos_EN, LV_OBJ_FLAG_HIDDEN);
        if (s_pos_multi_container_EN != NULL) {
            for (uint32_t i = 0; i < TOTAL_POSICIONES_BANCA_EN; i++) {
                if (s_pos_checkboxes_EN[i] != NULL) lv_obj_remove_state(s_pos_checkboxes_EN[i], LV_STATE_CHECKED);
            }
            lv_obj_clear_flag(s_pos_multi_container_EN, LV_OBJ_FLAG_HIDDEN);
        }
        if (s_modal_box_EN != NULL) lv_obj_set_height(s_modal_box_EN, 360);

        if (s_ok_btn_EN != NULL) {
            lv_obj_set_size(s_ok_btn_EN, 170, 48);
            lv_obj_align(s_ok_btn_EN, LV_ALIGN_BOTTOM_MID, -100, 8);
        }
        if (s_cancel_btn_EN != NULL) {
            lv_obj_set_size(s_cancel_btn_EN, 170, 48);
            lv_obj_align(s_cancel_btn_EN, LV_ALIGN_BOTTOM_MID, 100, 8);
        }

    } else if (target == ui_Boton_agregar4_EN) {
        s_target_panel_EN = ui_PanelBullpen_EN; 
        s_plus_btn_target_EN = ui_Boton_agregar4_EN;
        lv_label_set_text(s_popup_title_EN, "Add Bullpen Pitcher");

        if (s_pos_multi_container_EN != NULL) lv_obj_add_flag(s_pos_multi_container_EN, LV_OBJ_FLAG_HIDDEN);
        if (s_dropdown_pos_EN != NULL) {
            lv_dropdown_set_options(s_dropdown_pos_EN, 
                "RHP - Right Handed Pitcher\n"
                "LHP - Left Handed Pitcher"
            );
            lv_dropdown_set_selected(s_dropdown_pos_EN, 0);
            lv_obj_clear_flag(s_dropdown_pos_EN, LV_OBJ_FLAG_HIDDEN);
        }
        if (s_modal_box_EN != NULL) lv_obj_set_height(s_modal_box_EN, 255);

    } else {
        if (s_dropdown_pos_EN != NULL) lv_obj_add_flag(s_dropdown_pos_EN, LV_OBJ_FLAG_HIDDEN);
        if (s_pos_multi_container_EN != NULL) lv_obj_add_flag(s_pos_multi_container_EN, LV_OBJ_FLAG_HIDDEN);
        if (s_modal_box_EN != NULL) lv_obj_set_height(s_modal_box_EN, 175);

        if (target == ui_Boton_agregar3_EN) {
            s_target_panel_EN = ui_PanelTitulares_EN; 
            s_plus_btn_target_EN = ui_Boton_agregar3_EN;
            lv_label_set_text(s_popup_title_EN, "Add Starter");
        } else if (target == ui_Boton_agregar2_EN) {
            s_target_panel_EN = ui_PanelOrdenBate_EN; 
            s_plus_btn_target_EN = ui_Boton_agregar2_EN;
            lv_label_set_text(s_popup_title_EN, "Add Batter");
        }
    }

    if (s_textarea_EN != NULL) {
        lv_textarea_set_text(s_textarea_EN, "");
        lv_obj_scroll_to_y(s_textarea_EN, 0, LV_ANIM_OFF);
    }
    if (s_overlay_EN != NULL) lv_obj_clear_flag(s_overlay_EN, LV_OBJ_FLAG_HIDDEN);
}

static void attach_panel_btn_events_EN(lv_obj_t *panel, lv_obj_t *plus_btn)
{
    if (panel == NULL || !lv_obj_is_valid(panel)) return;
    uint32_t count = lv_obj_get_child_count(panel);
    for (uint32_t i = 0; i < count; i++) {
        lv_obj_t *child = lv_obj_get_child(panel, i);
        if (child != NULL && lv_obj_is_valid(child) && child != plus_btn) {
            lv_obj_add_flag(child, LV_OBJ_FLAG_CLICKABLE);

            lv_obj_remove_event_cb(child, on_player_btn_clicked);
            lv_obj_remove_event_cb(child, on_player_btn_long_pressed);

            lv_obj_add_event_cb(child, on_player_btn_clicked, LV_EVENT_CLICKED, NULL);
            lv_obj_add_event_cb(child, on_player_btn_long_pressed, LV_EVENT_LONG_PRESSED, NULL);
        }
    }
}

void alineacion_dynamic_EN_init(void)
{
    ESP_LOGI("NAV", "  a) alineacion_dynamic_EN_init INICIO");

    /* Pestañas izquierda */
    if (ui_Titulares_EN != NULL && ui_TabOrdenBate_EN != NULL &&
        lv_obj_is_valid(ui_Titulares_EN) && lv_obj_is_valid(ui_TabOrdenBate_EN)) {
        lv_obj_remove_event_cb(ui_Titulares_EN, tab_titulares_EN_cb);
        lv_obj_remove_event_cb(ui_TabOrdenBate_EN, tab_orden_bate_EN_cb);
        lv_obj_add_event_cb(ui_Titulares_EN, tab_titulares_EN_cb, LV_EVENT_CLICKED, NULL);
        lv_obj_add_event_cb(ui_Titulares_EN, tab_titulares_EN_cb, LV_EVENT_PRESSED, NULL);
        lv_obj_add_event_cb(ui_TabOrdenBate_EN, tab_orden_bate_EN_cb, LV_EVENT_CLICKED, NULL);
        lv_obj_add_event_cb(ui_TabOrdenBate_EN, tab_orden_bate_EN_cb, LV_EVENT_PRESSED, NULL);
    }

    /* Pestañas derecha */
    if (ui_BBANCA_EN != NULL && lv_obj_is_valid(ui_BBANCA_EN)) {
        lv_obj_remove_event_cb(ui_BBANCA_EN, tab_banca_EN_cb);
        lv_obj_add_event_cb(ui_BBANCA_EN, tab_banca_EN_cb, LV_EVENT_CLICKED, NULL);
        lv_obj_add_event_cb(ui_BBANCA_EN, tab_banca_EN_cb, LV_EVENT_PRESSED, NULL);
    }
    if (ui_BANCA_EN != NULL && lv_obj_is_valid(ui_BANCA_EN)) {
        lv_obj_add_flag(ui_BANCA_EN, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_remove_event_cb(ui_BANCA_EN, tab_banca_EN_cb);
        lv_obj_add_event_cb(ui_BANCA_EN, tab_banca_EN_cb, LV_EVENT_CLICKED, NULL);
        lv_obj_add_event_cb(ui_BANCA_EN, tab_banca_EN_cb, LV_EVENT_PRESSED, NULL);
    }

    if (ui_BULLPEN_EN != NULL && lv_obj_is_valid(ui_BULLPEN_EN)) {
        lv_obj_remove_event_cb(ui_BULLPEN_EN, tab_bullpen_EN_cb);
        lv_obj_add_event_cb(ui_BULLPEN_EN, tab_bullpen_EN_cb, LV_EVENT_CLICKED, NULL);
        lv_obj_add_event_cb(ui_BULLPEN_EN, tab_bullpen_EN_cb, LV_EVENT_PRESSED, NULL);
    }
    if (ui_LBULLPEN_EN != NULL && lv_obj_is_valid(ui_LBULLPEN_EN)) {
        lv_obj_add_flag(ui_LBULLPEN_EN, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_remove_event_cb(ui_LBULLPEN_EN, tab_bullpen_EN_cb);
        lv_obj_add_event_cb(ui_LBULLPEN_EN, tab_bullpen_EN_cb, LV_EVENT_CLICKED, NULL);
        lv_obj_add_event_cb(ui_LBULLPEN_EN, tab_bullpen_EN_cb, LV_EVENT_PRESSED, NULL);
    }

    /* Botones "+" */
    if (ui_Boton_agregar3_EN && lv_obj_is_valid(ui_Boton_agregar3_EN)) {
        lv_obj_remove_event_cb(ui_Boton_agregar3_EN, plus_btn_EN_cb);
        lv_obj_add_event_cb(ui_Boton_agregar3_EN, plus_btn_EN_cb, LV_EVENT_CLICKED, NULL);
    }
    if (ui_Boton_agregar2_EN && lv_obj_is_valid(ui_Boton_agregar2_EN)) {
        lv_obj_remove_event_cb(ui_Boton_agregar2_EN, plus_btn_EN_cb);
        lv_obj_add_event_cb(ui_Boton_agregar2_EN, plus_btn_EN_cb, LV_EVENT_CLICKED, NULL);
    }
    if (ui_Boton_agregar5_EN && lv_obj_is_valid(ui_Boton_agregar5_EN)) {
        lv_obj_remove_event_cb(ui_Boton_agregar5_EN, plus_btn_EN_cb);
        lv_obj_add_event_cb(ui_Boton_agregar5_EN, plus_btn_EN_cb, LV_EVENT_CLICKED, NULL);
    }
    if (ui_Boton_agregar4_EN && lv_obj_is_valid(ui_Boton_agregar4_EN)) {
        lv_obj_remove_event_cb(ui_Boton_agregar4_EN, plus_btn_EN_cb);
        lv_obj_add_event_cb(ui_Boton_agregar4_EN, plus_btn_EN_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Enlazar eventos */
    attach_panel_btn_events_EN(ui_PanelTitulares_EN, ui_Boton_agregar3_EN);
    attach_panel_btn_events_EN(ui_PanelOrdenBate_EN, ui_Boton_agregar2_EN);
    attach_panel_btn_events_EN(ui_PanelBanca_EN, ui_Boton_agregar5_EN);
    attach_panel_btn_events_EN(ui_PanelBullpen_EN, ui_Boton_agregar4_EN);

    show_titulares_EN();
    show_banca_EN();

    sync_titulares_to_field_EN();
}