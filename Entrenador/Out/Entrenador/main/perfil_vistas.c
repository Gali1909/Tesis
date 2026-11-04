// perfil_vistas.c
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "ui.h"                 /* ajusta la ruta si tu ui.h esta en otra carpeta */
#include "perfil_vistas.h"

static const char *TAG = "PERFIL_VISTAS";

#define N_VISTAS    6
#define MAX_CAMPOS  14

typedef struct { uint8_t id; uint16_t val; } campo_t;
typedef struct {
    bool     hay;
    uint8_t  n_sal;
    uint16_t anio;
    uint8_t  n;
    campo_t  c[MAX_CAMPOS];
} vista_t;

/* esc: 0 entero, 1 = valor/10, 2 = valor/100 */
typedef struct { const char *es, *en; uint8_t esc; } campo_def_t;
static const campo_def_t CAMPOS[] = {
    /* 0 */ { "PCL", "ERA",  2 },
    /* 1 */ { "WHIP", "WHIP", 2 },
    /* 2 */ { "K/9", "K/9",  2 },
    /* 3 */ { "IL",  "IP",   1 },
    /* 4 */ { "H",   "H",    0 },
    /* 5 */ { "CL",  "ER",   0 },
    /* 6 */ { "SO",  "SO",   0 },
    /* 7 */ { "BB",  "BB",   0 },
    /* 8 */ { "PIT", "PIT",  0 },
    /* 9 */ { "G",   "W",    0 },
    /* 10 */{ "P",   "L",    0 },
    /* 11 */{ "AP",  "GS",   0 },
    /* 12 */{ "SV",  "SV",   0 },
    /* 13 */{ "JL",  "G",    0 },
};
#define N_CAMPOS_DEF ((int)(sizeof(CAMPOS) / sizeof(CAMPOS[0])))

/* Textos de los botones (solo ASCII: las fuentes montserrat incluidas no
 * traen acentos ni enie). */
static const char *BTN_ES[N_VISTAS] = { "ULTIMA\nACTUACION", "ULT.\n5", "ULT.\n10", "ULT.\n15", "TEMPORADA\nACTUAL", "DE POR\nVIDA" };
static const char *BTN_EN[N_VISTAS] = { "LAST\nOUTING",      "LAST\n5", "LAST\n10", "LAST\n15", "CURRENT\nSEASON",   "CAREER" };
static const int   BTN_W[N_VISTAS]  = { 150, 80, 80, 80, 150, 120 };

/* Tipos de lanzamiento (mismo catalogo que perfil_lanzador_ui.c). */
#define N_TIPOS      14
#define VEL_MIN_MPH  60
#define VEL_MAX_MPH  105
static const char *NOMBRE_TIPO_ES[N_TIPOS] = {
    "Recta de 4 costuras", "Recta de 2 costuras", "Sinker", "Cutter",
    "Split-finger", "Curva", "Slider", "Sweeper", "Cambio de velocidad",
    "Circle change", "Splitter", "Tenedor", "Nudillera", "Tirabuz\xC3\xB3n"
};
static const char *NOMBRE_TIPO_EN[N_TIPOS] = {
    "Four-seam fastball", "Two-seam fastball", "Sinker", "Cutter",
    "Split-finger", "Curveball", "Slider", "Sweeper", "Changeup",
    "Circle change", "Splitter", "Forkball", "Knuckleball", "Screwball"
};

typedef struct { uint8_t tipo, vmin, vmax; } tipo_t;
typedef struct { bool hay; uint8_t n; tipo_t t[N_TIPOS]; } tipos_t;

/* ---------------- Datos compartidos (UART <-> LVGL) ---------------- */
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
static vista_t s_v[N_VISTAS];
static tipos_t s_tipos;
static bool    s_dirty = false;

static uint16_t u16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }

void perfil_vistas_on_frame(const uint8_t *p, uint8_t len)
{
    if (len < 5 || p[0] >= N_VISTAS) { ESP_LOGW(TAG, "0x16 invalida (len=%d)", len); return; }
    uint8_t n = p[4];
    if (n > MAX_CAMPOS || len < 5 + 3 * n) { ESP_LOGW(TAG, "0x16 con campos invalidos"); return; }

    vista_t t;
    memset(&t, 0, sizeof(t));
    t.hay = true;
    t.n_sal = p[1];
    t.anio = u16(p + 2);
    t.n = n;
    for (int i = 0; i < n; i++) {
        t.c[i].id  = p[5 + 3 * i];
        t.c[i].val = u16(p + 6 + 3 * i);
    }
    taskENTER_CRITICAL(&s_mux);
    s_v[p[0]] = t;
    s_dirty = true;
    taskEXIT_CRITICAL(&s_mux);
    ESP_LOGI(TAG, "Vista %u recibida: %u campos", p[0], n);
}

/* Trama 0x17: [n] + n x { slot, vmin, vmax }  (n <= 14) */
void perfil_tipos_on_frame(const uint8_t *p, uint8_t len)
{
    if (len < 1 || p[0] > N_TIPOS || len < 1 + 3 * p[0]) { ESP_LOGW(TAG, "0x17 invalida (len=%d)", len); return; }
    tipos_t t;
    memset(&t, 0, sizeof(t));
    t.hay = true;
    t.n = p[0];
    for (int i = 0; i < t.n; i++) {
        t.t[i].tipo = p[1 + 3 * i];
        t.t[i].vmin = p[2 + 3 * i];
        t.t[i].vmax = p[3 + 3 * i];
    }
    taskENTER_CRITICAL(&s_mux);
    s_tipos = t;
    s_dirty = true;
    taskEXIT_CRITICAL(&s_mux);
    ESP_LOGI(TAG, "Tipos recibidos: %u", t.n);
}

void perfil_vistas_borrar(void)
{
    taskENTER_CRITICAL(&s_mux);
    memset(s_v, 0, sizeof(s_v));
    memset(&s_tipos, 0, sizeof(s_tipos));
    s_dirty = true;
    taskEXIT_CRITICAL(&s_mux);
}

/* ---------------- Lado LVGL (solo tarea de LVGL) ---------------- */
typedef struct {
    lv_obj_t *dueno;                 /* ui_Panel_Lan con el que se construyo */
    lv_obj_t *tabs;
    lv_obj_t *btn[N_VISTAS], *btn_lbl[N_VISTAS];
    lv_obj_t *wrap, *caption, *strip;
    lv_obj_t *cel[MAX_CAMPOS], *cel_val[MAX_CAMPOS], *cel_nom[MAX_CAMPOS];
    lv_obj_t *lista;                                   /* lista con scroll de lanzamientos */
    lv_obj_t *fila[N_TIPOS], *fila_nom[N_TIPOS], *fila_sl[N_TIPOS], *fila_vel[N_TIPOS];
} lang_t;

static lang_t s_l[2];       /* 0 = ES, 1 = EN */
static int    s_sel = 4;    /* vista elegida (4 = temporada, como en la app) */
static bool   s_visible = false;

typedef struct {
    lv_obj_t *panel_lan, *panel_stats, *panel_datos, *old_tab[3], *orig[5];
} padres_t;

static bool padres_de(bool en, padres_t *p)
{
    if (!en) {
        if (ui_Panel_Lan == NULL || ui_PanelULTIMA_Vida == NULL || ui_PanelDatos_Vida == NULL) return false;
        p->panel_lan = ui_Panel_Lan; p->panel_stats = ui_PanelULTIMA_Vida; p->panel_datos = ui_PanelDatos_Vida;
        p->old_tab[0] = ui_ButtonULTIMAACTUACION; p->old_tab[1] = ui_ButtonTEMPORADAACTUAL; p->old_tab[2] = ui_ButtonDE_POR_VIDA;
        p->orig[0] = ui_Button_Lan1_P1_Vida; p->orig[1] = ui_Button_Lan1_P2_Vida; p->orig[2] = ui_Button_Lan1_P3_Vida;
        p->orig[3] = ui_Button_Lan1_P4_Vida; p->orig[4] = ui_Button_Lan1_P5_Vida;
    } else {
        if (ui_Panel_Lan_EN == NULL || ui_PanelULTIMA_Vida_EN == NULL || ui_PanelDatos_Vida_EN == NULL) return false;
        p->panel_lan = ui_Panel_Lan_EN; p->panel_stats = ui_PanelULTIMA_Vida_EN; p->panel_datos = ui_PanelDatos_Vida_EN;
        p->old_tab[0] = ui_ButtonULTIMAACTUACION_EN; p->old_tab[1] = ui_ButtonTEMPORADAACTUAL_EN; p->old_tab[2] = ui_ButtonDE_POR_VIDA_EN;
        p->orig[0] = ui_Button_Lan1_P1_Vida_EN; p->orig[1] = ui_Button_Lan1_P2_Vida_EN; p->orig[2] = ui_Button_Lan1_P3_Vida_EN;
        p->orig[3] = ui_Button_Lan1_P4_Vida_EN; p->orig[4] = ui_Button_Lan1_P5_Vida_EN;
    }
    return true;
}

static void set_hidden(lv_obj_t *o, bool oculto)
{
    if (o == NULL) return;
    if (oculto) lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
    else        lv_obj_remove_flag(o, LV_OBJ_FLAG_HIDDEN);
}

static void transparente(lv_obj_t *o)
{
    lv_obj_set_style_bg_opa(o, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(o, 0, 0);
    lv_obj_set_style_radius(o, 0, 0);
    lv_obj_set_style_pad_all(o, 0, 0);
}

static void refrescar_todo(void);

static void tab_cb(lv_event_t *e)
{
    s_sel = (int)(intptr_t)lv_event_get_user_data(e);
    refrescar_todo();
}

static void construir(lang_t *l, bool en, const padres_t *p)
{
    memset(l, 0, sizeof(*l));
    l->dueno = p->panel_lan;

    /* Fila de botones de vista: ocupa el lugar de las 3 pestanas originales. */
    l->tabs = lv_obj_create(p->panel_lan);
    lv_obj_set_size(l->tabs, 700, 86);
    lv_obj_set_align(l->tabs, LV_ALIGN_CENTER);
    lv_obj_set_pos(l->tabs, -3, -101);
    transparente(l->tabs);
    lv_obj_set_style_pad_gap(l->tabs, 8, 0);
    lv_obj_set_flex_flow(l->tabs, LV_FLEX_FLOW_ROW);
    lv_obj_set_scroll_dir(l->tabs, LV_DIR_HOR);
    lv_obj_set_scrollbar_mode(l->tabs, LV_SCROLLBAR_MODE_OFF);

    for (int i = 0; i < N_VISTAS; i++) {
        lv_obj_t *b = lv_button_create(l->tabs);
        lv_obj_set_size(b, BTN_W[i], 86);
        lv_obj_remove_flag(b, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_style_radius(b, 0, 0);
        lv_obj_set_style_bg_opa(b, 255, 0);
        lv_obj_set_style_border_color(b, lv_color_hex(0x0FF5ED), 0);
        lv_obj_set_style_border_opa(b, 255, 0);
        lv_obj_set_style_border_width(b, 2, 0);
        lv_obj_add_event_cb(b, tab_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);

        lv_obj_t *t = lv_label_create(b);
        lv_label_set_text(t, en ? BTN_EN[i] : BTN_ES[i]);
        lv_obj_set_style_text_align(t, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_font(t, &lv_font_montserrat_20, 0);
        lv_obj_set_align(t, LV_ALIGN_CENTER);
        l->btn[i] = b;
        l->btn_lbl[i] = t;
    }

    /* Contenedor de estadisticas: reemplaza la cuadricula (PanelDatos_Vida). */
    l->wrap = lv_obj_create(p->panel_stats);
    lv_obj_set_size(l->wrap, 724, 150);
    lv_obj_set_align(l->wrap, LV_ALIGN_CENTER);
    lv_obj_set_pos(l->wrap, 13, -93);
    transparente(l->wrap);
    lv_obj_remove_flag(l->wrap, LV_OBJ_FLAG_SCROLLABLE);

    l->caption = lv_label_create(l->wrap);
    lv_obj_set_align(l->caption, LV_ALIGN_TOP_LEFT);
    lv_obj_set_pos(l->caption, 6, 2);
    lv_obj_set_style_text_color(l->caption, lv_color_hex(0xE7E9EE), 0);
    lv_obj_set_style_text_font(l->caption, &lv_font_montserrat_20, 0);
    lv_label_set_text(l->caption, "");

    l->strip = lv_obj_create(l->wrap);
    lv_obj_set_size(l->strip, 724, 114);
    lv_obj_set_align(l->strip, LV_ALIGN_BOTTOM_MID);
    transparente(l->strip);
    lv_obj_set_style_pad_gap(l->strip, 6, 0);
    lv_obj_set_flex_flow(l->strip, LV_FLEX_FLOW_ROW);
    lv_obj_set_scroll_dir(l->strip, LV_DIR_HOR);
    lv_obj_set_scrollbar_mode(l->strip, LV_SCROLLBAR_MODE_AUTO);

    for (int i = 0; i < MAX_CAMPOS; i++) {
        lv_obj_t *c = lv_obj_create(l->strip);
        lv_obj_set_size(c, 104, 100);
        lv_obj_remove_flag(c, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_remove_flag(c, LV_OBJ_FLAG_CLICKABLE);   /* deja pasar el arrastre a la franja */
        lv_obj_set_style_radius(c, 0, 0);
        lv_obj_set_style_pad_all(c, 0, 0);
        lv_obj_set_style_bg_color(c, lv_color_hex(0x1F242E), 0);
        lv_obj_set_style_bg_opa(c, 255, 0);
        lv_obj_set_style_border_color(c, lv_color_hex(0x000000), 0);
        lv_obj_set_style_border_opa(c, 255, 0);
        lv_obj_set_style_border_width(c, 2, 0);

        lv_obj_t *v = lv_label_create(c);
        lv_obj_set_align(v, LV_ALIGN_CENTER);
        lv_obj_set_pos(v, 0, -14);
        lv_obj_set_style_text_color(v, lv_color_hex(0xE7E9EE), 0);
        lv_obj_set_style_text_font(v, &lv_font_montserrat_34, 0);

        lv_obj_t *n = lv_label_create(c);
        lv_obj_set_align(n, LV_ALIGN_CENTER);
        lv_obj_set_pos(n, 0, 28);
        lv_obj_set_style_text_color(n, lv_color_hex(0x0FF5ED), 0);
        lv_obj_set_style_text_font(n, &lv_font_montserrat_20, 0);

        l->cel[i] = c; l->cel_val[i] = v; l->cel_nom[i] = n;
        lv_obj_add_flag(c, LV_OBJ_FLAG_HIDDEN);
    }

    /* Lista de lanzamientos con scroll vertical (reemplaza las 5 filas fijas). */
    l->lista = lv_obj_create(p->panel_stats);
    lv_obj_set_size(l->lista, 713, 150);
    lv_obj_set_align(l->lista, LV_ALIGN_CENTER);
    lv_obj_set_pos(l->lista, 3, 90);
    transparente(l->lista);
    lv_obj_set_style_pad_gap(l->lista, 4, 0);
    lv_obj_set_flex_flow(l->lista, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_scroll_dir(l->lista, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(l->lista, LV_SCROLLBAR_MODE_AUTO);
    lv_obj_add_flag(l->lista, LV_OBJ_FLAG_HIDDEN);

    for (int i = 0; i < N_TIPOS; i++) {
        lv_obj_t *r = lv_obj_create(l->lista);
        lv_obj_set_size(r, 700, 46);
        lv_obj_remove_flag(r, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_remove_flag(r, LV_OBJ_FLAG_CLICKABLE);   /* deja pasar el arrastre a la lista */
        lv_obj_set_style_radius(r, 10, 0);
        lv_obj_set_style_pad_all(r, 0, 0);
        lv_obj_set_style_border_width(r, 0, 0);
        lv_obj_set_style_bg_color(r, lv_color_hex(0x14171C), 0);
        lv_obj_set_style_bg_opa(r, 255, 0);

        lv_obj_t *nom = lv_label_create(r);
        lv_obj_set_align(nom, LV_ALIGN_LEFT_MID);
        lv_obj_set_pos(nom, 14, 0);
        lv_obj_set_style_text_color(nom, lv_color_hex(0xE7E9EE), 0);
        lv_obj_set_style_text_font(nom, &lv_font_montserrat_24, 0);

        lv_obj_t *sl = lv_slider_create(r);
        lv_obj_remove_flag(sl, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_size(sl, 180, 10);
        lv_obj_set_align(sl, LV_ALIGN_LEFT_MID);
        lv_obj_set_pos(sl, 330, 0);
        lv_slider_set_range(sl, VEL_MIN_MPH, VEL_MAX_MPH);
        lv_obj_set_style_bg_color(sl, lv_color_hex(0x091925), LV_PART_MAIN);
        lv_obj_set_style_bg_opa(sl, 255, LV_PART_MAIN);
        lv_obj_set_style_bg_color(sl, lv_color_hex(0x0FF5ED), LV_PART_INDICATOR);
        lv_obj_set_style_bg_opa(sl, 255, LV_PART_INDICATOR);
        lv_obj_set_style_bg_color(sl, lv_color_hex(0x0FF5ED), LV_PART_KNOB);
        lv_obj_set_style_bg_opa(sl, 255, LV_PART_KNOB);

        lv_obj_t *vel = lv_label_create(r);
        lv_obj_set_align(vel, LV_ALIGN_RIGHT_MID);
        lv_obj_set_pos(vel, -12, 0);
        lv_obj_set_style_text_color(vel, lv_color_hex(0x0FF5ED), 0);
        lv_obj_set_style_text_font(vel, &lv_font_montserrat_24, 0);

        l->fila[i] = r; l->fila_nom[i] = nom; l->fila_sl[i] = sl; l->fila_vel[i] = vel;
        lv_obj_add_flag(r, LV_OBJ_FLAG_HIDDEN);
    }
}

/* Devuelve true si la pantalla existe y deja sus widgets listos. */
static bool asegurar(bool en, lang_t **out, padres_t *p)
{
    lang_t *l = &s_l[en ? 1 : 0];
    if (!padres_de(en, p)) { memset(l, 0, sizeof(*l)); return false; }  /* pantalla destruida */
    if (l->dueno != p->panel_lan) construir(l, en, p);                   /* nueva o recreada */
    *out = l;
    return true;
}

static void fmt_valor(char *buf, size_t cap, const campo_def_t *d, uint16_t v)
{
    if (d->esc == 2)      snprintf(buf, cap, "%u.%02u", v / 100, v % 100);
    else if (d->esc == 1) snprintf(buf, cap, "%u.%u",   v / 10,  v % 10);
    else                  snprintf(buf, cap, "%u", v);
}

static void texto_titulo(char *buf, size_t cap, bool en, int sel, const vista_t *v)
{
    static const uint8_t req[4] = { 1, 5, 10, 15 };
    if (!v->hay) {
        snprintf(buf, cap, "%s", en ? "No data: resend the profile from the app"
                                    : "Sin datos: reenvia el perfil desde la app");
    } else if (sel == 4) {
        if (v->anio) snprintf(buf, cap, en ? "Season %u" : "Temporada %u", v->anio);
        else snprintf(buf, cap, "%s", en ? "Current season" : "Temporada actual");
    } else if (sel == 5) {
        snprintf(buf, cap, "%s", en ? "Career" : "De por vida");
    } else if (v->n_sal == 0) {
        snprintf(buf, cap, "%s", en ? "No outings logged" : "Sin salidas registradas");
    } else if (sel == 0) {
        snprintf(buf, cap, "%s", en ? "Last outing" : "Ultima salida");
    } else if (v->n_sal < req[sel]) {
        if (en) snprintf(buf, cap, "Only %u outing%s logged", v->n_sal, v->n_sal == 1 ? "" : "s");
        else    snprintf(buf, cap, v->n_sal == 1 ? "Solo hay 1 salida registrada" : "Solo hay %u salidas registradas", v->n_sal);
    } else {
        snprintf(buf, cap, en ? "Last %u outings" : "Ultimas %u salidas", req[sel]);
    }
}

static void pintar(lang_t *l, bool en, int sel, const vista_t *v)
{
    char buf[48];

    for (int i = 0; i < N_VISTAS; i++) {
        bool on = (i == sel);
        lv_obj_set_style_bg_color(l->btn[i], on ? lv_color_hex(0x0FF5ED) : lv_color_hex(0x14171C), 0);
        lv_obj_set_style_text_color(l->btn_lbl[i], on ? lv_color_hex(0x14171C) : lv_color_hex(0xE7E9EE), 0);
    }

    texto_titulo(buf, sizeof(buf), en, sel, v);
    lv_label_set_text(l->caption, buf);

    int k = 0;
    for (int i = 0; i < v->n && k < MAX_CAMPOS; i++) {
        uint8_t id = v->c[i].id;
        if (id >= N_CAMPOS_DEF) continue;
        const campo_def_t *d = &CAMPOS[id];
        char val[24];
        const char *nom = en ? d->en : d->es;
        char nomc[12];

        /* G y P seguidos se muestran juntos como "G-P" (W-L). */
        if (id == 9 && i + 1 < v->n && v->c[i + 1].id == 10) {
            snprintf(val, sizeof(val), "%u-%u", v->c[i].val, v->c[i + 1].val);
            snprintf(nomc, sizeof(nomc), "%s", en ? "W-L" : "G-P");
            nom = nomc;
            i++;
        } else {
            fmt_valor(val, sizeof(val), d, v->c[i].val);
        }
        lv_label_set_text(l->cel_val[k], val);
        lv_label_set_text(l->cel_nom[k], nom);
        lv_obj_remove_flag(l->cel[k], LV_OBJ_FLAG_HIDDEN);
        k++;
    }
    for (; k < MAX_CAMPOS; k++) lv_obj_add_flag(l->cel[k], LV_OBJ_FLAG_HIDDEN);
    lv_obj_scroll_to_x(l->strip, 0, LV_ANIM_OFF);
}

static void pintar_tipos(lang_t *l, bool en, const padres_t *p, const tipos_t *t)
{
    set_hidden(l->lista, !t->hay);
    if (!t->hay) return;                       /* sin 0x17: quedan las 5 filas originales */
    for (int i = 0; i < 5; i++) set_hidden(p->orig[i], true);

    const char **nombres = en ? NOMBRE_TIPO_EN : NOMBRE_TIPO_ES;
    for (int i = 0; i < N_TIPOS; i++) {
        bool hay = (i < t->n) && (t->t[i].tipo < N_TIPOS);
        set_hidden(l->fila[i], !hay);
        if (!hay) continue;
        char buf[24];
        const tipo_t *x = &t->t[i];
        lv_label_set_text(l->fila_nom[i], nombres[x->tipo]);
        lv_slider_set_value(l->fila_sl[i], (x->vmin + x->vmax) / 2, LV_ANIM_OFF);
        if (x->vmax == 0)            snprintf(buf, sizeof(buf), "-");
        else if (x->vmin == x->vmax) snprintf(buf, sizeof(buf), "%u mph", x->vmax);
        else                         snprintf(buf, sizeof(buf), "%u-%u mph", x->vmin, x->vmax);
        lv_label_set_text(l->fila_vel[i], buf);
    }
}

static void refrescar_todo(void)
{
    vista_t v;
    tipos_t tp;
    int sel = s_sel;
    taskENTER_CRITICAL(&s_mux);
    v = s_v[sel];
    tp = s_tipos;
    s_dirty = false;
    taskEXIT_CRITICAL(&s_mux);

    for (int e = 0; e < 2; e++) {
        lang_t *l; padres_t p;
        if (!asegurar(e == 1, &l, &p)) continue;
        pintar(l, e == 1, sel, &v);
        pintar_tipos(l, e == 1, &p, &tp);
    }
}

void perfil_vistas_ui_mostrar(void)
{
    s_visible = true;
    for (int e = 0; e < 2; e++) {
        lang_t *l; padres_t p;
        if (!asegurar(e == 1, &l, &p)) continue;
        for (int i = 0; i < 3; i++) set_hidden(p.old_tab[i], true);   /* pestanas originales */
        set_hidden(p.panel_datos, true);                              /* cuadricula original */
        set_hidden(l->tabs, false);
        set_hidden(l->wrap, false);
        lv_obj_scroll_to_y(l->lista, 0, LV_ANIM_OFF);
    }
    refrescar_todo();
}

void perfil_vistas_ui_ocultar(void)
{
    s_visible = false;
    for (int e = 0; e < 2; e++) {
        lang_t *l = &s_l[e];
        padres_t p;
        if (!padres_de(e == 1, &p) || l->dueno != p.panel_lan) continue;
        set_hidden(l->tabs, true);
        set_hidden(l->wrap, true);
    }
}

void perfil_vistas_ui_tick(void)
{
    if (!s_visible) return;
    bool sucio;
    taskENTER_CRITICAL(&s_mux);
    sucio = s_dirty;
    taskEXIT_CRITICAL(&s_mux);
    if (sucio) refrescar_todo();
}