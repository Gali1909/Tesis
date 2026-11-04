// perfil_lanzador_ui.c
#include <stdio.h>
#include <string.h>
#include "ui.h"                 /* ajusta la ruta si tu ui.h esta en otra carpeta */
#include "perfil_lanzador_ui.h"
#include "perfil_vistas.h"

#define N_TIPOS      14
#define VEL_MIN_MPH  60
#define VEL_MAX_MPH  105

/* Indexados por "slot" = posicion en tiposLanzamientoPredeterminados de la app
 * (database_helper.dart). Es el mismo numero que la app manda en el 0x13. */
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

typedef struct {
    lv_obj_t *nombre, *iniciales, *avatar, *datos, *numero;
    lv_obj_t *tab[3];
    lv_obj_t *panel_stats;
    lv_obj_t *stat[10];   /* G, P, PCL, J, A, SV, IL, SO, WHIP, BB */
    lv_obj_t *fila[PERFIL_MAX_LANZ];
    lv_obj_t *fila_nombre[PERFIL_MAX_LANZ];
    lv_obj_t *fila_slider[PERFIL_MAX_LANZ];
    lv_obj_t *fila_vel[PERFIL_MAX_LANZ];
} vista_t;

/* Devuelve false si esa pantalla no esta creada (los punteros quedan en NULL
 * cuando SquareLine hace screen_destroy). */
static bool vista_es(vista_t *v)
{
    if (ui_Panel_Lan == NULL) return false;
    v->nombre = ui_LabelNombreLan;  v->iniciales = ui_LaBELPLanza1;
    v->avatar = ui_PPLanza1;        v->datos = ui_LAbel_datos;
    v->numero = ui_LabelNumero1;
    v->tab[0] = ui_ButtonULTIMAACTUACION;
    v->tab[1] = ui_ButtonTEMPORADAACTUAL;
    v->tab[2] = ui_ButtonDE_POR_VIDA;
    v->panel_stats = ui_PanelULTIMA_Vida;
    v->stat[0] = ui_LabelGANADOSValor_Vida;  v->stat[1] = ui_LabelPERDIDOSValor_Vida;
    v->stat[2] = ui_LabelPCLValor_Vida;      v->stat[3] = ui_LabelJUGADOSValor_Vida;
    v->stat[4] = ui_LabelAValor_Vida;        v->stat[5] = ui_LabelSVValor_Vida;
    v->stat[6] = ui_LabelILValor_Vida;       v->stat[7] = ui_LabelSOValor_Vida;
    v->stat[8] = ui_LabelWHIPValor_Vida;     v->stat[9] = ui_Labelkbb_Valor_Vida;
    v->fila[0] = ui_Button_Lan1_P1_Vida; v->fila_nombre[0] = ui_Label_Lan1_P1_Vida;
    v->fila_slider[0] = ui_Slider_Lan1_P1_Vida; v->fila_vel[0] = ui_Label2_Lan1_P1_Vida;
    v->fila[1] = ui_Button_Lan1_P2_Vida; v->fila_nombre[1] = ui_Label_Lan1_P2_Vida;
    v->fila_slider[1] = ui_Slider_Lan1_P2_Vida; v->fila_vel[1] = ui_Label2_Lan1_P2_Vida;
    v->fila[2] = ui_Button_Lan1_P3_Vida; v->fila_nombre[2] = ui_Label_Lan1_P3_Vida;
    v->fila_slider[2] = ui_Slider_Lan1_P3_Vida; v->fila_vel[2] = ui_Label2_Lan1_P3_Vida;
    v->fila[3] = ui_Button_Lan1_P4_Vida; v->fila_nombre[3] = ui_Label_Lan1_P4_Vida;
    v->fila_slider[3] = ui_Slider_Lan1_P4_Vida; v->fila_vel[3] = ui_Label2_Lan1_P4_Vida;
    v->fila[4] = ui_Button_Lan1_P5_Vida; v->fila_nombre[4] = ui_Label_Lan1_P5_Vida;
    v->fila_slider[4] = ui_Slider_Lan1_P5_Vida; v->fila_vel[4] = ui_Label2_Lan1_P5_Vida;
    return true;
}

static bool vista_en(vista_t *v)
{
    if (ui_Panel_Lan_EN == NULL) return false;
    v->nombre = ui_LabelNombreLan_EN;  v->iniciales = ui_LaBELPLanza1_EN;
    v->avatar = ui_PPLanza1_EN;        v->datos = ui_LAbel_datos_EN;
    v->numero = ui_LabelNumero1_EN;
    v->tab[0] = ui_ButtonULTIMAACTUACION_EN;
    v->tab[1] = ui_ButtonTEMPORADAACTUAL_EN;
    v->tab[2] = ui_ButtonDE_POR_VIDA_EN;
    v->panel_stats = ui_PanelULTIMA_Vida_EN;
    v->stat[0] = ui_LabelGANADOSValor_Vida_EN;  v->stat[1] = ui_LabelPERDIDOSValor_Vida_EN;
    v->stat[2] = ui_LabelPCLValor_Vida_EN;      v->stat[3] = ui_LabelJUGADOSValor_Vida_EN;
    v->stat[4] = ui_LabelAValor_Vida_EN;        v->stat[5] = ui_LabelSVValor_Vida_EN;
    v->stat[6] = ui_LabelILValor_Vida_EN;       v->stat[7] = ui_LabelSOValor_Vida_EN;
    v->stat[8] = ui_LabelWHIPValor_Vida_EN;     v->stat[9] = ui_Labelkbb_Valor_Vida_EN;
    v->fila[0] = ui_Button_Lan1_P1_Vida_EN; v->fila_nombre[0] = ui_Label_Lan1_P1_Vida_EN;
    v->fila_slider[0] = ui_Slider_Lan1_P1_Vida_EN; v->fila_vel[0] = ui_Label2_Lan1_P1_Vida_EN;
    v->fila[1] = ui_Button_Lan1_P2_Vida_EN; v->fila_nombre[1] = ui_Label_Lan1_P2_Vida_EN;
    v->fila_slider[1] = ui_Slider_Lan1_P2_Vida_EN; v->fila_vel[1] = ui_Label2_Lan1_P2_Vida_EN;
    v->fila[2] = ui_Button_Lan1_P3_Vida_EN; v->fila_nombre[2] = ui_Label_Lan1_P3_Vida_EN;
    v->fila_slider[2] = ui_Slider_Lan1_P3_Vida_EN; v->fila_vel[2] = ui_Label2_Lan1_P3_Vida_EN;
    v->fila[3] = ui_Button_Lan1_P4_Vida_EN; v->fila_nombre[3] = ui_Label_Lan1_P4_Vida_EN;
    v->fila_slider[3] = ui_Slider_Lan1_P4_Vida_EN; v->fila_vel[3] = ui_Label2_Lan1_P4_Vida_EN;
    v->fila[4] = ui_Button_Lan1_P5_Vida_EN; v->fila_nombre[4] = ui_Label_Lan1_P5_Vida_EN;
    v->fila_slider[4] = ui_Slider_Lan1_P5_Vida_EN; v->fila_vel[4] = ui_Label2_Lan1_P5_Vida_EN;
    return true;
}

static void mostrar(lv_obj_t *o, bool si)
{
    if (si) lv_obj_remove_flag(o, LV_OBJ_FLAG_HIDDEN);
    else    lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
}

static void reset_vista(const vista_t *v, bool en)
{
    mostrar(v->avatar, false);
    mostrar(v->datos, false);
    mostrar(v->numero, false);
    for (int i = 0; i < 3; i++) mostrar(v->tab[i], false);
    mostrar(v->panel_stats, false);   /* oculta tambien las 5 filas de lanzamientos */
    lv_label_set_text(v->nombre, en ? "Select a pitcher" : "Selecciona un lanzador");
}

/* Copia el primer caracter UTF-8 de s a out (para iniciales con acentos). */
static int primer_char(const char *s, char *out)
{
    unsigned char c = (unsigned char)s[0];
    int n = (c < 0x80) ? 1 : (c >> 5) == 0x6 ? 2 : (c >> 4) == 0xE ? 3 : (c >> 3) == 0x1E ? 4 : 1;
    for (int i = 0; i < n && s[i]; i++) out[i] = s[i];
    return n;
}

static void iniciales(const char *nombre, char *out, size_t cap)
{
    out[0] = '\0';
    if (cap < 9) return;
    while (*nombre == ' ') nombre++;
    if (*nombre == '\0') return;
    int n = primer_char(nombre, out);
    out[n] = '\0';
    const char *sp = strchr(nombre, ' ');
    if (sp) {
        while (*sp == ' ') sp++;
        if (*sp) {
            int m = primer_char(sp, out + n);
            out[n + m] = '\0';
        }
    }
}

static void aplicar(const vista_t *v, bool en, const perfil_lanzador_t *p)
{
    char buf[64];

    mostrar(v->avatar, true);
    mostrar(v->datos, true);
    mostrar(v->numero, true);
    for (int i = 0; i < 3; i++) mostrar(v->tab[i], true);
    mostrar(v->panel_stats, true);

    lv_label_set_text(v->nombre, p->nombre);

    iniciales(p->nombre, buf, sizeof(buf));
    lv_label_set_text(v->iniciales, buf);

    snprintf(buf, sizeof(buf), "#%u", p->numero);
    lv_label_set_text(v->numero, buf);

    const char *mano = en ? (p->mano ? "Left-handed pitcher (LHP)" : "Right-handed pitcher (RHP)")
                          : (p->mano ? "Lanzador zurdo (LHP)"      : "Lanzador derecho (RHP)");
    if (p->edad) snprintf(buf, sizeof(buf), en ? "%s  %u yrs" : "%s  %u a\xC3\xB1os", mano, p->edad);
    else         snprintf(buf, sizeof(buf), "%s", mano);
    lv_label_set_text(v->datos, buf);

    const uint16_t enteros[10] = { p->g, p->p, 0, p->j, p->a, p->sv, 0, p->so, 0, p->bb };
    for (int i = 0; i < 10; i++) {
        if (i == 2)      snprintf(buf, sizeof(buf), "%u.%02u", p->pcl_x100 / 100, p->pcl_x100 % 100);
        else if (i == 6) snprintf(buf, sizeof(buf), "%u.%u",   p->il_x10 / 10,    p->il_x10 % 10);
        else if (i == 8) snprintf(buf, sizeof(buf), "%u.%02u", p->whip_x100 / 100, p->whip_x100 % 100);
        else             snprintf(buf, sizeof(buf), "%u", enteros[i]);
        lv_label_set_text(v->stat[i], buf);
    }

    const char **nombres = en ? NOMBRE_TIPO_EN : NOMBRE_TIPO_ES;
    for (int i = 0; i < PERFIL_MAX_LANZ; i++) {
        bool hay = (i < p->n_lanz) && (p->lanz[i].tipo < N_TIPOS);
        mostrar(v->fila[i], hay);
        if (!hay) continue;
        const perfil_lanz_t *l = &p->lanz[i];
        lv_label_set_text(v->fila_nombre[i], nombres[l->tipo]);
        lv_slider_set_range(v->fila_slider[i], VEL_MIN_MPH, VEL_MAX_MPH);
        lv_slider_set_value(v->fila_slider[i], (l->vmin + l->vmax) / 2, LV_ANIM_OFF);
        if (l->vmax == 0)       snprintf(buf, sizeof(buf), "-");
        else if (l->vmin == l->vmax) snprintf(buf, sizeof(buf), "%u mph", l->vmax);
        else                    snprintf(buf, sizeof(buf), "%u-%u mph", l->vmin, l->vmax);
        lv_label_set_text(v->fila_vel[i], buf);
    }
}

void perfil_lanzador_ui_reset(void)
{
    vista_t v;
    perfil_vistas_ui_ocultar();
    if (vista_es(&v)) reset_vista(&v, false);
    if (vista_en(&v)) reset_vista(&v, true);
}

void perfil_lanzador_ui_mostrar(const perfil_lanzador_t *p)
{
    if (p == NULL) return;
    vista_t v;
    if (vista_es(&v)) aplicar(&v, false, p);
    if (vista_en(&v)) aplicar(&v, true, p);
    perfil_vistas_ui_mostrar();
}

/*---------------------------------------------------------------
 * Lista de lanzadores (columna izquierda)
 *--------------------------------------------------------------*/
typedef struct { lv_obj_t *b1, *nombre1, *ini1, *b2; } lista_t;

static bool lista_es(lista_t *l)
{
    if (ui_Panel_Lan == NULL || ui_BOTON_PLanzador1 == NULL) return false;
    l->b1 = ui_BOTON_PLanzador1; l->nombre1 = ui_LPLanzador1;
    l->ini1 = ui_LaBELPLanzador1; l->b2 = ui_BOTON_PLanzador2;
    return true;
}

static bool lista_en(lista_t *l)
{
    if (ui_Panel_Lan_EN == NULL || ui_BOTON_PLanzador1_EN == NULL) return false;
    l->b1 = ui_BOTON_PLanzador1_EN; l->nombre1 = ui_LPLanzador1_EN;
    l->ini1 = ui_LaBELPLanzador1_EN; l->b2 = ui_BOTON_PLanzador2_EN;
    return true;
}

static void aplicar_lista(const lista_t *l, bool hay, const char *nombre)
{
    mostrar(l->b1, hay);
    if (l->b2) mostrar(l->b2, false);
    if (!hay) return;
    char ini[16];
    lv_label_set_text(l->nombre1, nombre);
    iniciales(nombre, ini, sizeof(ini));
    lv_label_set_text(l->ini1, ini);
}

void perfil_lanzador_ui_lista(bool hay, const char *nombre)
{
    lista_t l;
    if (nombre == NULL) nombre = "";
    if (lista_es(&l)) aplicar_lista(&l, hay, nombre);
    if (lista_en(&l)) aplicar_lista(&l, hay, nombre);
}

void perfil_lanzador_ui_set_click_cb(lv_event_cb_t cb)
{
    lista_t l;
    if (lista_es(&l)) {
        lv_obj_remove_event_cb(l.b1, cb);
        lv_obj_add_event_cb(l.b1, cb, LV_EVENT_CLICKED, NULL);
    }
    if (lista_en(&l)) {
        lv_obj_remove_event_cb(l.b1, cb);
        lv_obj_add_event_cb(l.b1, cb, LV_EVENT_CLICKED, NULL);
    }
}
