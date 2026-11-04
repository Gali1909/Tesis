#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "ui.h"
#include "analisis_dynamic.h"

/* ------------------------------------------------------------------ */
/* Colores (los mismos que ya usa la pantalla)                          */
/* ------------------------------------------------------------------ */
#define COLOR_CONTADOR_OFF  lv_color_hex(0x2E343D)  /* gris, igual que Container_Out2 */
#define COLOR_STRIKE_ON     lv_color_hex(0x00C60A)  /* verde */
#define COLOR_BOLA_ON       lv_color_hex(0x105BDF)  /* azul  */
#define COLOR_OUT_ON        lv_color_hex(0xD83838)  /* rojo  */
#define COLOR_BASE_OFF      lv_color_hex(0x262B33)  /* base vacía (el de SquareLine) */
#define COLOR_BASE_ON       lv_color_hex(0xE36F10)  /* base ocupada (naranja del proyecto) */

#define MAX_STRIKES 2   /* Container_Strike1..2 */
#define MAX_BOLAS   3   /* Container_Bola1..3   */
#define MAX_OUTS    2   /* Container_Out1..2 (el 3er out cierra la entrada) */

/* ------------------------------------------------------------------ */
/* Estado                                                               */
/* ------------------------------------------------------------------ */
static uint8_t s_strikes = 0;
static uint8_t s_bolas   = 0;
static uint8_t s_outs    = 0;
static uint8_t s_bases   = 0;   /* bit0=1ra, bit1=2da, bit2=3ra */

/* Marcador. Por ahora: empieza el juego, entrada 1, batea EQUIPO1 (alta). */
#define NUM_INNINGS 7

/* Innings lanzados (label ui_Label_en_la1): cuenta los outs que consigue el lanzador mientras
 * su equipo esta a la defensiva. Equipo del lanzador: 1 = EQUIPO 1, 2 = EQUIPO 2.
 * Con el estado inicial (EQUIPO 1 batea primero) el EQUIPO 2 es el que lanza primero. */
#define LANZADOR_EQUIPO 2
#define IL_PREFIJO "IL                                 "   /* titulo + espacios, igual que el texto de ui_Label_en_la1 */
static uint16_t s_outs_lanz = 0;   /* outs totales del lanzador: 3 outs = 1.0 inning */
static uint16_t s_k_lanz    = 0;   /* ponches del lanzador (ui_Label_en_la2) */
static uint16_t s_bb_lanz   = 0;   /* boletos del lanzador (ui_Label_en_la2) */
static uint16_t s_pitch_lanz = 0;  /* lanzamientos totales del lanzador */
#define KBB_PREFIJO "K-BB                          "   /* titulo + espacios, igual que el texto de ui_Label_en_la2 */
static uint8_t s_entrada      = 1;      /* 1..NUM_INNINGS */
static bool    s_bateando_eq1 = true;   /* true = EQUIPO1 (alta), false = EQUIPO2 (baja) */
static uint8_t s_carreras_eq1 = 0;
static uint8_t s_carreras_eq2 = 0;
static uint8_t s_hits_eq1     = 0;
static uint8_t s_hits_eq2     = 0;
static uint8_t s_errores_eq1  = 0;
static uint8_t s_errores_eq2  = 0;
static uint8_t s_ining_alta[NUM_INNINGS + 1];   /* índice 1..7 */
static uint8_t s_ining_baja[NUM_INNINGS + 1];
static bool    s_show_alta[NUM_INNINGS + 1];   /* casilla ya con valor visible */
static bool    s_show_baja[NUM_INNINGS + 1];

/* Secuencia de lanzamientos del turno al bate (Panel_Secu_Turno) */
#define MAX_LANZ 20
enum { LANZ_STRIKE = 1, LANZ_BOLA = 2, LANZ_FOUL = 3 };
typedef struct {
    uint8_t res;        /* LANZ_* */
    uint8_t zona;       /* 1..25, 0 = sin zona (foul) */
    char    tipo[4];    /* abreviatura del tipo de lanzamiento elegido ("" si ninguno) */
} lanz_t;
static lanz_t  s_secu[MAX_LANZ];
static uint8_t s_secu_n    = 0;
static uint8_t s_secu_base = 0;       /* lanzamientos descartados por turno muy largo (para numerar bien) */
static bool    s_secu_pend = false;   /* true = el proximo lanzamiento empieza una secuencia nueva */
static int8_t  s_tipo_sel  = -1;      /* chip de tipo de lanzamiento elegido (0..5), -1 = ninguno */

/* ------------------------------------------------------------------ */
/* Helpers                                                              */
/* ------------------------------------------------------------------ */
static void pintar_contador(lv_obj_t * obj, bool encendido, lv_color_t color_on)
{
    if(obj == NULL) return;
    lv_obj_set_style_bg_color(obj,
                              encendido ? color_on : COLOR_CONTADOR_OFF,
                              LV_PART_MAIN | LV_STATE_DEFAULT);
}

static void strikes_refrescar(void)
{
    pintar_contador(ui_Container_Strike1, s_strikes >= 1, COLOR_STRIKE_ON);
    pintar_contador(ui_Container_Strike2, s_strikes >= 2, COLOR_STRIKE_ON);
}

static void bolas_refrescar(void)
{
    pintar_contador(ui_Container_Bola1, s_bolas >= 1, COLOR_BOLA_ON);
    pintar_contador(ui_Container_Bola2, s_bolas >= 2, COLOR_BOLA_ON);
    pintar_contador(ui_Container_Bola3, s_bolas >= 3, COLOR_BOLA_ON);
}

static void outs_refrescar(void)
{
    pintar_contador(ui_Container_Out1, s_outs >= 1, COLOR_OUT_ON);
    pintar_contador(ui_Container_Out2, s_outs >= 2, COLOR_OUT_ON);
}

static void pintar_base(lv_obj_t * obj, bool ocupada)
{
    if(obj == NULL) return;
    lv_color_t c = ocupada ? COLOR_BASE_ON : COLOR_BASE_OFF;
    lv_obj_set_style_bg_color(obj, c, LV_PART_MAIN | LV_STATE_DEFAULT);
    if(ocupada) {
        lv_obj_set_style_border_color(obj, COLOR_BASE_ON, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    else {
        lv_obj_set_style_border_color(obj, lv_color_hex(0x2E343D), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

/* Button_Accion12 (base robada): solo se habilita si hay al menos un corredor en base. */
static void robo_btn_refrescar(void)
{
    if(ui_Button_Accion12 == NULL) return;
    lv_obj_set_style_opa(ui_Button_Accion12, LV_OPA_40, LV_PART_MAIN | LV_STATE_DISABLED);
    if(s_bases & 0x07) lv_obj_remove_state(ui_Button_Accion12, LV_STATE_DISABLED);
    else               lv_obj_add_state(ui_Button_Accion12, LV_STATE_DISABLED);
}

static void bases_refrescar(void)
{
    pintar_base(ui_BASE_1, s_bases & 0x01);
    pintar_base(ui_BASE_2, s_bases & 0x02);
    pintar_base(ui_BASE_3, s_bases & 0x04);
    robo_btn_refrescar();
}

/* ------------------------------------------------------------------ */
/* Marcador                                                             */
/* ------------------------------------------------------------------ */
/* Devuelve el label: el propio objeto si es label, o el primer label que
 * encuentre dentro de sus hijos (a cualquier profundidad). */
static lv_obj_t * como_label(lv_obj_t * obj)
{
    if(obj == NULL) return NULL;
    if(lv_obj_check_type(obj, &lv_label_class)) return obj;
    uint32_t n = lv_obj_get_child_count(obj);
    for(uint32_t i = 0; i < n; i++) {
        lv_obj_t * r = como_label(lv_obj_get_child(obj, (int32_t)i));
        if(r) return r;
    }
    return NULL;
}

static void poner_numero(lv_obj_t * obj, uint8_t n)
{
    if(obj == NULL) return;
    lv_obj_t * l = como_label(obj);
    if(l == NULL) {
        /* El panel no trae label (caso de Ining1_Alta): se crea uno centrado. */
        l = lv_label_create(obj);
        lv_obj_center(l);
        lv_obj_set_style_text_color(l, lv_color_white(), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_remove_flag(l, LV_OBJ_FLAG_CLICKABLE);
    }
    lv_label_set_text_fmt(l, "%u", (unsigned)n);
}

/* Deja vacia una casilla (solo si ya tiene label; no crea uno). */
static void limpiar_numero(lv_obj_t * obj)
{
    lv_obj_t * l = como_label(obj);
    if(l) lv_label_set_text(l, "");
}

static lv_obj_t * ining_obj(bool alta, uint8_t entrada)
{
    switch(entrada) {
        case 1: return alta ? ui_Ining1_Alta : ui_Ining1_Baja;
        case 2: return alta ? ui_Ining2_Alta : ui_Ining2_Baja;
        case 3: return alta ? ui_Ining3_Alta : ui_Ining3_Baja;
        case 4: return alta ? ui_Ining4_Alta : ui_Ining4_Baja;
        case 5: return alta ? ui_Ining5_Alta : ui_Ining5_Baja;
        case 6: return alta ? ui_Ining6_Alta : ui_Ining6_Baja;
        case 7: return alta ? ui_Ining7_Alta : ui_Ining7_Baja;
        default: return NULL;
    }
}

/* ------------------------------------------------------------------ */
/* Secuencia de lanzamientos                                            */
/* ------------------------------------------------------------------ */
/* Distribucion: 10 circulos por fila, hasta 2 filas (20 lanzamientos).
 * Los espacios 1..4 son los de SquareLine; el resto se crean al hacer falta. */
#define SECU_POR_FILA 10
#define SECU_X0       (-135)
#define SECU_DX       30
#define SECU_Y_FILA0  (-18)
#define SECU_DY       32

static lv_obj_t * s_circ[MAX_LANZ];
static lv_obj_t * s_num[MAX_LANZ];
static lv_obj_t * s_tipo[MAX_LANZ];

/* Si la pantalla se volvio a crear, los objetos dinamicos ya no existen. */
static void secu_verificar_pool(void)
{
    lv_obj_t * ref = s_circ[4] ? s_circ[4] : s_tipo[3];
    if(ref == NULL) return;
    if(!lv_obj_is_valid(ref) || lv_obj_get_parent(ref) != ui_Panel_Secu_Turno) {
        for(int i = 4; i < MAX_LANZ; i++) { s_circ[i] = NULL; s_num[i] = NULL; }
        for(int i = 0; i < MAX_LANZ; i++) s_tipo[i] = NULL;
    }
}

/* Crea (si falta) los objetos del espacio i y los deja en su posicion. */
static void secu_asegurar(int i)
{
    int col = i % SECU_POR_FILA;
    int fila = i / SECU_POR_FILA;
    int x = SECU_X0 + SECU_DX * col;
    int y = SECU_Y_FILA0 + SECU_DY * fila;

    if(i < 4) {
        lv_obj_t * circ[4] = { ui_Container_Secu_Lan1, ui_Container_Secu_Lan2,
                               ui_Container_Secu_Lan3, ui_Container_Secu_Lan4 };
        lv_obj_t * num[4]  = { ui_Label_Secu1, ui_Label_Secu2, ui_Label_Secu3, ui_Label_Secu4 };
        s_circ[i] = circ[i];
        s_num[i]  = num[i];
        if(i < 3) {
            lv_obj_t * tipo[3] = { ui_Label_Secu_Lan1, ui_Label_Secu_Lan2, ui_Label_Secu_Lan3 };
            s_tipo[i] = tipo[i];
        }
    }
    else if(s_circ[i] == NULL) {
        lv_obj_t * circ = lv_obj_create(ui_Panel_Secu_Turno);
        lv_obj_remove_style_all(circ);
        lv_obj_set_size(circ, 20, 20);
        lv_obj_set_align(circ, LV_ALIGN_CENTER);
        lv_obj_set_x(circ, x);
        lv_obj_set_y(circ, y);
        lv_obj_remove_flag(circ, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_style_radius(circ, 10, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_opa(circ, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_opa(circ, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(circ, 1, LV_PART_MAIN | LV_STATE_DEFAULT);

        lv_obj_t * num = lv_label_create(circ);
        lv_obj_set_width(num, LV_SIZE_CONTENT);
        lv_obj_set_height(num, LV_SIZE_CONTENT);
        lv_obj_set_align(num, LV_ALIGN_CENTER);

        s_circ[i] = circ;
        s_num[i]  = num;
    }

    if(s_tipo[i] == NULL) {
        lv_obj_t * t = lv_label_create(ui_Panel_Secu_Turno);
        lv_obj_set_width(t, LV_SIZE_CONTENT);
        lv_obj_set_height(t, LV_SIZE_CONTENT);
        lv_obj_set_align(t, LV_ALIGN_CENTER);
        lv_obj_set_x(t, x - 1);
        lv_obj_set_y(t, y + 15);
        lv_obj_set_style_text_color(t, lv_color_hex(0xE7E9EE), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_font(t, &lv_font_montserrat_10, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_label_set_text(t, "");
        s_tipo[i] = t;
    }
}

/* Muestra todos los lanzamientos del turno (minimo 4 espacios visibles).
 * Colores = leyenda del panel: cian = strike, gris = bola, naranja = foul,
 * oscuro = espacio libre. */
static void secuencia_refrescar(void)
{
    if(ui_Panel_Secu_Turno == NULL) return;
    secu_verificar_pool();

    int visibles = (s_secu_n > 4) ? s_secu_n : 4;

    for(int i = 0; i < MAX_LANZ; i++) {
        if(i >= visibles) {                       /* espacio no usado: ocultar si ya existe */
            if(s_circ[i]) lv_obj_add_flag(s_circ[i], LV_OBJ_FLAG_HIDDEN);
            if(s_tipo[i]) lv_obj_add_flag(s_tipo[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }

        secu_asegurar(i);
        lv_obj_remove_flag(s_circ[i], LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(s_tipo[i], LV_OBJ_FLAG_HIDDEN);

        lv_color_t bg, borde, txt;
        char buf[8] = "";

        if(i < s_secu_n) {
            switch(s_secu[i].res) {
                case LANZ_STRIKE: bg = lv_color_hex(0x11CCDE); borde = lv_color_hex(0x47E3F2); txt = lv_color_white(); break;
                case LANZ_FOUL:   bg = lv_color_hex(0xE36F10); borde = lv_color_hex(0xE36F10); txt = lv_color_white(); break;
                default:          bg = lv_color_hex(0x2E343D); borde = lv_color_hex(0x2E343D); txt = lv_color_hex(0x808080); break;
            }
            if(s_secu[i].tipo[0])                 snprintf(buf, sizeof(buf), "%s", s_secu[i].tipo);
            else if(s_secu[i].zona > 0)           snprintf(buf, sizeof(buf), "Z%u", (unsigned)s_secu[i].zona);
            else if(s_secu[i].res == LANZ_FOUL)   snprintf(buf, sizeof(buf), "FOUL");
        }
        else {
            bg = lv_color_hex(0x14171C); borde = lv_color_hex(0x4A4F58); txt = lv_color_hex(0x4A4F58);
        }

        lv_obj_set_style_bg_color(s_circ[i], bg, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_color(s_circ[i], borde, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_width(s_circ[i], 1, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(s_num[i], txt, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_label_set_text_fmt(s_num[i], "%d", s_secu_base + i + 1);
        lv_label_set_text(s_tipo[i], buf);
    }
}

/* Abreviatura (3 letras) del tipo de lanzamiento elegido; "" si no hay. */
static void tipo_actual(char out[4])
{
    out[0] = '\0';
    lv_obj_t * lbl[6] = { ui_Label_Lanzamientosdispo,  ui_Label_Lanzamientosdispo1,
                          ui_Label_Lanzamientosdispo2, ui_Label_Lanzamientosdispo3,
                          ui_Label_Lanzamientosdispo4, ui_Label_Lanzamientosdispo5 };
    if(s_tipo_sel < 0 || s_tipo_sel > 5 || lbl[s_tipo_sel] == NULL) return;
    const char * t = lv_label_get_text(lbl[s_tipo_sel]);
    int n = 0;
    while(*t == ' ') t++;
    for(; *t && n < 3; t++) {
        char ch = *t;
        if(ch >= 'a' && ch <= 'z') ch = (char)(ch - 'a' + 'A');
        out[n++] = ch;
    }
    out[n] = '\0';
}

static void secuencia_agregar(uint8_t res, uint8_t zona)
{
    if(s_secu_pend) {            /* bateador nuevo: la secuencia anterior se borra al primer lanzamiento */
        s_secu_n = 0;
        s_secu_base = 0;
        s_secu_pend = false;
    }
    if(s_secu_n == MAX_LANZ) {   /* turno muy largo: se descarta el mas antiguo */
        memmove(&s_secu[0], &s_secu[1], sizeof(lanz_t) * (MAX_LANZ - 1));
        s_secu_n--;
        s_secu_base++;
    }
    lanz_t * l = &s_secu[s_secu_n++];
    l->res  = res;
    l->zona = zona;
    tipo_actual(l->tipo);
    secuencia_refrescar();
}

/* Chips de tipo de lanzamiento: el elegido se resalta; tocarlo otra vez lo quita. */
static void chips_refrescar(void)
{
    lv_obj_t * chip[6] = { ui_Lanzamientosdispo,  ui_Lanzamientosdispo1, ui_Lanzamientosdispo2,
                           ui_Lanzamientosdispo3, ui_Lanzamientosdispo4, ui_Lanzamientosdispo5 };
    lv_obj_t * lbl[6]  = { ui_Label_Lanzamientosdispo,  ui_Label_Lanzamientosdispo1,
                           ui_Label_Lanzamientosdispo2, ui_Label_Lanzamientosdispo3,
                           ui_Label_Lanzamientosdispo4, ui_Label_Lanzamientosdispo5 };
    for(int i = 0; i < 6; i++) {
        if(chip[i] == NULL) continue;
        bool sel = (i == s_tipo_sel);
        lv_obj_set_style_bg_color(chip[i], sel ? lv_color_hex(0x00D2FE) : lv_color_hex(0x14171C),
                                  LV_PART_MAIN | LV_STATE_DEFAULT);
        if(lbl[i]) lv_obj_set_style_text_color(lbl[i], sel ? lv_color_hex(0x14171C) : lv_color_hex(0x00D2FE),
                                               LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

/* true = el equipo del lanzador esta a la defensiva (el otro equipo batea) */
static bool lanzador_defiende(void)
{
    return s_bateando_eq1 == (LANZADOR_EQUIPO == 2);
}

/* Muestra los innings lanzados en ui_Label_en_la1 como entero.tercio: 0.0, 0.1, 0.2, 1.0, 1.1 ...
 * Ese label trae el titulo y el valor en un solo texto ("IL" + espacios + valor), asi que se
 * conserva el mismo prefijo que tiene en SquareLine. */
static void il_refrescar(void)
{
    if(ui_Label_en_la1 == NULL) return;
    lv_label_set_text_fmt(ui_Label_en_la1, "%s%u.%u", IL_PREFIJO,
                          (unsigned)(s_outs_lanz / 3), (unsigned)(s_outs_lanz % 3));
}

/* K-BB del lanzador en ui_Label_en_la2: "K-BB" + espacios + ponches-boletos (ej. 2-0) */
static void kbb_refrescar(void)
{
    if(ui_Label_en_la2 == NULL) return;
    lv_label_set_text_fmt(ui_Label_en_la2, "%s%u-%u", KBB_PREFIJO,
                          (unsigned)s_k_lanz, (unsigned)s_bb_lanz);
}

/* Contador de lanzamientos del lanzador. SquareLine no trae un label para esto, asi que se
 * crea aqui en Panel_LANANA, a la derecha de "En la noche:".
 * IMPORTANTE: el label se identifica con una marca (user_data) y se BUSCA entre los hijos del
 * panel antes de crear uno. Asi, si analisis_dynamic_init() se llama mas de una vez sobre la
 * misma pantalla, no se apilan labels uno encima de otro (se veria "0" y el numero encimados). */
static const char s_pitch_tag = 0;

static void pitch_refrescar(void)
{
    if(ui_Panel_LANANA == NULL) return;

    lv_obj_t * l = NULL;
    for(int32_t i = (int32_t)lv_obj_get_child_count(ui_Panel_LANANA) - 1; i >= 0; i--) {
        lv_obj_t * c = lv_obj_get_child(ui_Panel_LANANA, i);
        if(c == NULL || lv_obj_get_user_data(c) != (void *)&s_pitch_tag) continue;
        if(l == NULL) l = c;
        else lv_obj_delete(c);   /* duplicado: se elimina */
    }

    if(l == NULL) {
        l = lv_label_create(ui_Panel_LANANA);
        lv_obj_set_user_data(l, (void *)&s_pitch_tag);
        lv_obj_set_width(l, LV_SIZE_CONTENT);
        lv_obj_set_height(l, LV_SIZE_CONTENT);
        lv_obj_set_align(l, LV_ALIGN_CENTER);
        lv_obj_set_x(l, 75);
        lv_obj_set_y(l, 96);   /* misma fila que ui_Label_en_la_noche1 */
        lv_obj_set_style_text_color(l, lv_color_hex(0xE7E9EE), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_font(l, &lv_font_montserrat_14, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    lv_label_set_text_fmt(l, "Lanzamientos: %u", (unsigned)s_pitch_lanz);
}

/* Suma un lanzamiento al lanzador (solo si su equipo esta a la defensiva). Llamar justo
 * DESPUES de undo_guardar() para que deshacer lo reste tambien. */
static void lanz_contar(void)
{
    printf("[analisis] lanzamiento: bateando_eq1=%d, LANZADOR_EQUIPO=%d, cuenta=%s, total=%u\n",
           (int)s_bateando_eq1, LANZADOR_EQUIPO, lanzador_defiende() ? "SI" : "NO (defiende el otro equipo)",
           (unsigned)s_pitch_lanz);
    if(!lanzador_defiende()) return;
    s_pitch_lanz++;
    pitch_refrescar();
}

static void marcador_refrescar(void)
{
    il_refrescar();
    kbb_refrescar();
    pitch_refrescar();
    poner_numero(ui_Carreras_EQ1, s_carreras_eq1);
    poner_numero(ui_Carreras_EQ2, s_carreras_eq2);
    poner_numero(ui_HIT_EQ1, s_hits_eq1);
    poner_numero(ui_HIT_EQ2, s_hits_eq2);
    poner_numero(ui_Errores_EQ1, s_errores_eq1);
    poner_numero(ui_Errores_EQ2, s_errores_eq2);

    /* Linescore: repintar las casillas que ya tienen valor (la pantalla se
     * vuelve a crear cada vez que se entra y sus labels quedan vacios). */
    for(uint8_t i = 1; i <= NUM_INNINGS; i++) {
        if(s_show_alta[i]) poner_numero(ining_obj(true,  i), s_ining_alta[i]);
        else               limpiar_numero(ining_obj(true,  i));
        if(s_show_baja[i]) poner_numero(ining_obj(false, i), s_ining_baja[i]);
        else               limpiar_numero(ining_obj(false, i));
    }

    secuencia_refrescar();
}

/* ------------------------------------------------------------------ */
/* Deshacer (Button_Accion11): pila de estados anteriores                */
/* ------------------------------------------------------------------ */
#define UNDO_MAX 40

typedef struct {
    uint8_t strikes, bolas, outs, bases, entrada;
    bool    bateando_eq1;
    uint8_t carreras_eq1, carreras_eq2;
    uint8_t hits_eq1, hits_eq2;
    uint8_t errores_eq1, errores_eq2;
    uint8_t ining_alta[NUM_INNINGS + 1];
    uint8_t ining_baja[NUM_INNINGS + 1];
    bool    show_alta[NUM_INNINGS + 1];
    bool    show_baja[NUM_INNINGS + 1];
    lanz_t  secu[MAX_LANZ];
    uint8_t secu_n;
    uint8_t secu_base;
    bool    secu_pend;
    uint16_t outs_lanz, k_lanz, bb_lanz, pitch_lanz;
} estado_t;

static estado_t s_undo[UNDO_MAX];
static uint8_t  s_undo_n = 0;

/* Guarda el estado actual. Llamar justo ANTES de cambiar algo en una jugada. */
static void undo_guardar(void)
{
    if(s_undo_n == UNDO_MAX) {   /* pila llena: se descarta la jugada mas antigua */
        memmove(&s_undo[0], &s_undo[1], sizeof(estado_t) * (UNDO_MAX - 1));
        s_undo_n--;
    }
    estado_t * u = &s_undo[s_undo_n++];
    u->strikes = s_strikes; u->bolas = s_bolas; u->outs = s_outs; u->bases = s_bases;
    u->entrada = s_entrada; u->bateando_eq1 = s_bateando_eq1;
    u->carreras_eq1 = s_carreras_eq1; u->carreras_eq2 = s_carreras_eq2;
    u->hits_eq1 = s_hits_eq1; u->hits_eq2 = s_hits_eq2;
    u->errores_eq1 = s_errores_eq1; u->errores_eq2 = s_errores_eq2;
    memcpy(u->ining_alta, s_ining_alta, sizeof(s_ining_alta));
    memcpy(u->ining_baja, s_ining_baja, sizeof(s_ining_baja));
    memcpy(u->show_alta,  s_show_alta,  sizeof(s_show_alta));
    memcpy(u->show_baja,  s_show_baja,  sizeof(s_show_baja));
    memcpy(u->secu, s_secu, sizeof(s_secu));
    u->secu_n = s_secu_n; u->secu_base = s_secu_base; u->secu_pend = s_secu_pend;
    u->outs_lanz = s_outs_lanz; u->k_lanz = s_k_lanz; u->bb_lanz = s_bb_lanz; u->pitch_lanz = s_pitch_lanz;
}

static void undo_restaurar(void)
{
    if(s_undo_n == 0) return;
    const estado_t * u = &s_undo[--s_undo_n];
    s_strikes = u->strikes; s_bolas = u->bolas; s_outs = u->outs; s_bases = u->bases;
    s_entrada = u->entrada; s_bateando_eq1 = u->bateando_eq1;
    s_carreras_eq1 = u->carreras_eq1; s_carreras_eq2 = u->carreras_eq2;
    s_hits_eq1 = u->hits_eq1; s_hits_eq2 = u->hits_eq2;
    s_errores_eq1 = u->errores_eq1; s_errores_eq2 = u->errores_eq2;
    memcpy(s_ining_alta, u->ining_alta, sizeof(s_ining_alta));
    memcpy(s_ining_baja, u->ining_baja, sizeof(s_ining_baja));
    memcpy(s_show_alta,  u->show_alta,  sizeof(s_show_alta));
    memcpy(s_show_baja,  u->show_baja,  sizeof(s_show_baja));
    memcpy(s_secu, u->secu, sizeof(s_secu));
    s_secu_n = u->secu_n; s_secu_base = u->secu_base; s_secu_pend = u->secu_pend;
    s_outs_lanz = u->outs_lanz; s_k_lanz = u->k_lanz; s_bb_lanz = u->bb_lanz; s_pitch_lanz = u->pitch_lanz;

    strikes_refrescar();
    bolas_refrescar();
    outs_refrescar();
    bases_refrescar();
    marcador_refrescar();
}

/* ------------------------------------------------------------------ */
/* Eventos                                                              */
/* user_data = número de zona                                           */
/* ------------------------------------------------------------------ */
/* Registra el lanzamiento en el conteo y en la secuencia. El tipo de lanzamiento
 * ya fue elegido (s_tipo_sel) antes de llegar aqui. */
static void lanzamiento_aplicar(uint8_t res, uint8_t zona)
{
    undo_guardar();
    lanz_contar();   /* lanzamiento del lanzador */
    secuencia_agregar(res, zona);

    if(res == LANZ_STRIKE) {
        if(s_strikes < MAX_STRIKES) {
            s_strikes++;
            strikes_refrescar();
        }
        else {
            /* Tercer strike (ponche): out, y el conteo vuelve a 0-0. */
            if(lanzador_defiende()) { s_k_lanz++; kbb_refrescar(); }   /* K del lanzador */
            analisis_conteo_reiniciar();
            analisis_out_sumar();
        }
    }
    else if(res == LANZ_BOLA) {
        if(s_bolas < MAX_BOLAS) {
            s_bolas++;
            bolas_refrescar();
        }
        else {
            /* Cuarta bola (base por bolas): el bateador toma la 1ra, avanzan solo los
             * corredores forzados, y el conteo vuelve a 0-0. */
            if(lanzador_defiende()) { s_bb_lanz++; kbb_refrescar(); }   /* BB del lanzador */
            analisis_base_por_bolas();
            analisis_conteo_reiniciar();
        }
    }
    else {
        /* Foul: cuenta como strike solo si hay menos de 2. */
        if(s_strikes < MAX_STRIKES) {
            s_strikes++;
            strikes_refrescar();
        }
    }
}

static void tipo_popup_abrir(uint8_t res, uint8_t zona);   /* definido mas abajo */
static void tp_cerrar(void);

static void zona_strike_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    tipo_popup_abrir(LANZ_STRIKE, (uint8_t)(intptr_t)lv_event_get_user_data(e));
}

static void zona_bola_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    tipo_popup_abrir(LANZ_BOLA, (uint8_t)(intptr_t)lv_event_get_user_data(e));
}

static void accion_hit_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_hit();
}

static void accion_out_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_out_bateador();
}

/* ------------------------------------------------------------------ */
/* Popup de doble out (Button_Accion3 con 2+ corredores)                */
/* Indices: 0 = home (bateador), 1 = 1ra, 2 = 2da, 3 = 3ra               */
/* ------------------------------------------------------------------ */
#define DP_COLOR_FONDO    lv_color_hex(0x1B1F26)
#define DP_COLOR_JUGADOR  COLOR_BASE_ON
#define DP_COLOR_OUT      COLOR_OUT_ON

static const int16_t dp_cx[4] = { 170, 250, 170,  90 };
static const int16_t dp_cy[4] = { 240, 180, 120, 180 };
static const char *  dp_txt[4] = { "BAT", "1", "2", "3" };

static struct {
    lv_obj_t * overlay;
    lv_obj_t * title;
    lv_obj_t * info;
    lv_obj_t * btn_ok;
    lv_obj_t * btn_ok_lbl;
    lv_obj_t * dia[4];
    uint8_t    abierto;
    uint8_t    fase;          /* 0 = elegir outs, 1 = elegir bases */
    uint8_t    jugadores;     /* mascara por indice: bateador + corredores */
    uint8_t    outs_sel;      /* mascara por indice */
    uint8_t    ocupadas;      /* mascara por indice (bits 1..3) */
    uint8_t    sobrev;        /* jugadores que NO son out */
} dp;

static uint8_t dp_contar(uint8_t m)
{
    uint8_t n = 0;
    for(int i = 0; i < 4; i++) if(m & (1u << i)) n++;
    return n;
}

static void dp_refrescar(void)
{
    if(!dp.abierto) return;

    for(int i = 0; i < 4; i++) {
        uint8_t bit = (uint8_t)(1u << i);
        lv_color_t col = COLOR_CONTADOR_OFF;
        if(dp.fase == 0) {
            if(dp.outs_sel & bit)       col = DP_COLOR_OUT;
            else if(dp.jugadores & bit) col = DP_COLOR_JUGADOR;
        }
        else {
            if(i == 0)                  col = (dp.outs_sel & bit) ? DP_COLOR_OUT : COLOR_CONTADOR_OFF;
            else if(dp.ocupadas & bit)  col = DP_COLOR_JUGADOR;
        }
        lv_obj_set_style_bg_color(dp.dia[i], col, LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    if(dp.fase == 0) {
        uint8_t n = dp_contar(dp.outs_sel);
        lv_label_set_text(dp.title, "Doble out\nToca los 2 jugadores que fueron out");
        lv_label_set_text_fmt(dp.info, "Out marcados: %u / 2", (unsigned)n);
        lv_label_set_text(dp.btn_ok_lbl, "Siguiente");
        if(n == 2) lv_obj_remove_state(dp.btn_ok, LV_STATE_DISABLED);
        else       lv_obj_add_state(dp.btn_ok, LV_STATE_DISABLED);
    }
    else {
        uint8_t o = dp_contar(dp.ocupadas);
        lv_label_set_text(dp.title, "Bases ocupadas\nToca las bases donde quedan los jugadores");
        lv_label_set_text_fmt(dp.info, "En base: %u de %u   |   Carreras: %u",
                              (unsigned)o, (unsigned)dp.sobrev, (unsigned)(dp.sobrev - o));
        lv_label_set_text(dp.btn_ok_lbl, "Aceptar");
        lv_obj_remove_state(dp.btn_ok, LV_STATE_DISABLED);
    }
}

static void dp_cerrar(void)
{
    if(!dp.abierto) return;
    dp.abierto = 0;
    lv_obj_delete_async(dp.overlay);
    dp.overlay = NULL;
}

static void dp_zona_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED || !dp.abierto) return;
    int idx = (int)(intptr_t)lv_event_get_user_data(e);
    uint8_t bit = (uint8_t)(1u << idx);

    if(dp.fase == 0) {
        if(!(dp.jugadores & bit)) return;                 /* base vacia: no es jugador */
        if(dp.outs_sel & bit)      dp.outs_sel &= (uint8_t)~bit;
        else if(dp_contar(dp.outs_sel) < 2) dp.outs_sel |= bit;
    }
    else {
        if(idx == 0) return;                              /* home no se ocupa */
        if(dp.ocupadas & bit)      dp.ocupadas &= (uint8_t)~bit;
        else if(dp_contar(dp.ocupadas) < dp.sobrev) dp.ocupadas |= bit;
    }
    dp_refrescar();
}

static void dp_cancelar_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    dp_cerrar();
}

static void dp_aceptar_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED || !dp.abierto) return;

    if(dp.fase == 0) {
        if(dp_contar(dp.outs_sel) != 2) return;
        dp.sobrev = (uint8_t)(dp_contar(dp.jugadores) - 2);

        /* Propuesta inicial: los corredores que sobreviven se quedan donde estan
         * y, si el bateador sobrevive, va a la primera base libre. */
        dp.ocupadas = (uint8_t)((dp.jugadores & ~dp.outs_sel) & 0x0E);
        if((dp.jugadores & 0x01) && !(dp.outs_sel & 0x01)) {
            for(int i = 1; i <= 3; i++) {
                if(!(dp.ocupadas & (1u << i))) { dp.ocupadas |= (uint8_t)(1u << i); break; }
            }
        }
        dp.fase = 1;
        dp_refrescar();
        return;
    }

    /* Fase 1: aplicar la jugada */
    undo_guardar();
    lanz_contar();   /* bola en juego */
    uint8_t runs = (uint8_t)(dp.sobrev - dp_contar(dp.ocupadas));
    s_bases = (uint8_t)((dp.ocupadas >> 1) & 0x07);
    bases_refrescar();
    for(uint8_t i = 0; i < runs; i++) analisis_carrera_sumar();
    analisis_conteo_reiniciar();
    analisis_out_sumar();
    analisis_out_sumar();
    dp_cerrar();
}

static void dp_abrir(void)
{
    if(dp.abierto) return;
    memset(&dp, 0, sizeof(dp));
    dp.abierto   = 1;
    dp.jugadores = (uint8_t)(0x01 | ((s_bases & 0x07) << 1));

    /* Fondo oscuro que bloquea toques al resto de la pantalla */
    dp.overlay = lv_obj_create(lv_layer_top());
    lv_obj_set_size(dp.overlay, lv_pct(100), lv_pct(100));
    lv_obj_set_pos(dp.overlay, 0, 0);
    lv_obj_set_style_bg_color(dp.overlay, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(dp.overlay, LV_OPA_60, 0);
    lv_obj_set_style_border_width(dp.overlay, 0, 0);
    lv_obj_set_style_radius(dp.overlay, 0, 0);
    lv_obj_set_style_pad_all(dp.overlay, 0, 0);
    lv_obj_remove_flag(dp.overlay, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(dp.overlay, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t * panel = lv_obj_create(dp.overlay);
    lv_obj_set_size(panel, 340, 380);
    lv_obj_center(panel);
    lv_obj_set_style_bg_color(panel, DP_COLOR_FONDO, 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(panel, COLOR_CONTADOR_OFF, 0);
    lv_obj_set_style_border_width(panel, 2, 0);
    lv_obj_set_style_radius(panel, 14, 0);
    lv_obj_set_style_pad_all(panel, 0, 0);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_SCROLLABLE);

    dp.title = lv_label_create(panel);
    lv_obj_set_width(dp.title, 310);
    lv_obj_set_pos(dp.title, 15, 10);
    lv_label_set_long_mode(dp.title, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(dp.title, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(dp.title, lv_color_white(), 0);

    dp.info = lv_label_create(panel);
    lv_obj_set_width(dp.info, 310);
    lv_obj_set_pos(dp.info, 15, 56);
    lv_label_set_long_mode(dp.info, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(dp.info, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(dp.info, COLOR_BASE_ON, 0);

    /* Rombos (visual), etiquetas y zonas de toque (rectangulos sin rotar) */
    for(int i = 0; i < 4; i++) {
        lv_obj_t * d = lv_obj_create(panel);
        lv_obj_set_size(d, 52, 52);
        lv_obj_set_pos(d, dp_cx[i] - 26, dp_cy[i] - 26);
        lv_obj_set_style_radius(d, 8, 0);
        lv_obj_set_style_border_color(d, COLOR_BASE_OFF, 0);
        lv_obj_set_style_border_width(d, 2, 0);
        lv_obj_set_style_pad_all(d, 0, 0);
        lv_obj_set_style_transform_pivot_x(d, 26, 0);
        lv_obj_set_style_transform_pivot_y(d, 26, 0);
        lv_obj_set_style_transform_rotation(d, 450, 0);
        lv_obj_remove_flag(d, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_remove_flag(d, LV_OBJ_FLAG_CLICKABLE);
        dp.dia[i] = d;

        lv_obj_t * t = lv_label_create(panel);
        lv_obj_set_width(t, 70);
        lv_obj_set_pos(t, dp_cx[i] - 35, dp_cy[i] - 8);
        lv_obj_set_style_text_align(t, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_color(t, lv_color_white(), 0);
        lv_label_set_text(t, dp_txt[i]);
        lv_obj_remove_flag(t, LV_OBJ_FLAG_CLICKABLE);

        lv_obj_t * z = lv_obj_create(panel);
        lv_obj_set_size(z, 70, 70);
        lv_obj_set_pos(z, dp_cx[i] - 35, dp_cy[i] - 35);
        lv_obj_set_style_bg_opa(z, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(z, 0, 0);
        lv_obj_set_style_pad_all(z, 0, 0);
        lv_obj_remove_flag(z, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_event_cb(z, dp_zona_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);
    }

    /* Botones */
    lv_obj_t * bc = lv_button_create(panel);
    lv_obj_set_size(bc, 140, 50);
    lv_obj_set_pos(bc, 20, 310);
    lv_obj_set_style_bg_color(bc, COLOR_CONTADOR_OFF, 0);
    lv_obj_add_event_cb(bc, dp_cancelar_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t * lc = lv_label_create(bc);
    lv_label_set_text(lc, "Cancelar");
    lv_obj_center(lc);

    dp.btn_ok = lv_button_create(panel);
    lv_obj_set_size(dp.btn_ok, 140, 50);
    lv_obj_set_pos(dp.btn_ok, 180, 310);
    lv_obj_set_style_bg_color(dp.btn_ok, COLOR_BASE_ON, 0);
    lv_obj_set_style_bg_opa(dp.btn_ok, LV_OPA_40, LV_STATE_DISABLED);
    lv_obj_add_event_cb(dp.btn_ok, dp_aceptar_cb, LV_EVENT_CLICKED, NULL);
    dp.btn_ok_lbl = lv_label_create(dp.btn_ok);
    lv_obj_center(dp.btn_ok_lbl);

    dp_refrescar();
}

/* ------------------------------------------------------------------ */
/* Dialogo de pregunta con dos respuestas (+ cancelar)                  */
/* ------------------------------------------------------------------ */
static struct {
    lv_obj_t * overlay;
    uint8_t    abierto;
    uint8_t    opciones;      /* mascara por indice: bases que se pueden tocar (0 = home/anota) */
    void     (*cb)(int);      /* recibe el indice de la base tocada */
} pq;

static void pq_cerrar(void)
{
    if(!pq.abierto) return;
    pq.abierto = 0;
    lv_obj_delete_async(pq.overlay);
    pq.overlay = NULL;
}

static void pq_zona_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED || !pq.abierto) return;
    int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if(!(pq.opciones & (1u << idx))) return;          /* base que no es una opcion valida */
    void (*cb)(int) = pq.cb;
    pq_cerrar();
    if(cb) cb(idx);
}

static void pq_cancelar_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    pq_cerrar();
}

static lv_obj_t * pq_boton(lv_obj_t * padre, const char * txt, lv_color_t col,
                           int x, int y, int w, int h, lv_event_cb_t cb, int id)
{
    lv_obj_t * b = lv_button_create(padre);
    lv_obj_set_size(b, w, h);
    lv_obj_set_pos(b, x, y);
    lv_obj_set_style_bg_color(b, col, 0);
    lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, (void *)(intptr_t)id);
    lv_obj_t * l = lv_label_create(b);
    lv_label_set_text(l, txt);
    lv_obj_center(l);
    return b;
}

static void pq_abrir(const char * titulo, uint8_t opciones, void (*cb)(int), int base_pregunta)
{
    static const char * const nombre_base[4] = { "home", "1ra", "2da", "3ra" };

    if(pq.abierto || dp.abierto) return;
    memset(&pq, 0, sizeof(pq));
    pq.abierto  = 1;
    pq.opciones = opciones;
    pq.cb       = cb;

    pq.overlay = lv_obj_create(lv_layer_top());
    lv_obj_set_size(pq.overlay, lv_pct(100), lv_pct(100));
    lv_obj_set_pos(pq.overlay, 0, 0);
    lv_obj_set_style_bg_color(pq.overlay, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(pq.overlay, LV_OPA_60, 0);
    lv_obj_set_style_border_width(pq.overlay, 0, 0);
    lv_obj_set_style_radius(pq.overlay, 0, 0);
    lv_obj_set_style_pad_all(pq.overlay, 0, 0);
    lv_obj_remove_flag(pq.overlay, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(pq.overlay, LV_OBJ_FLAG_CLICKABLE);

    /* Mismo estilo que el popup de doble out */
    lv_obj_t * panel = lv_obj_create(pq.overlay);
    lv_obj_set_size(panel, 340, 380);
    lv_obj_center(panel);
    lv_obj_set_style_bg_color(panel, DP_COLOR_FONDO, 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(panel, COLOR_CONTADOR_OFF, 0);
    lv_obj_set_style_border_width(panel, 2, 0);
    lv_obj_set_style_radius(panel, 14, 0);
    lv_obj_set_style_pad_all(panel, 0, 0);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t * t = lv_label_create(panel);
    lv_obj_set_width(t, 310);
    lv_obj_set_pos(t, 15, 10);
    lv_label_set_long_mode(t, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(t, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(t, lv_color_white(), 0);
    lv_label_set_text(t, titulo);

    lv_obj_t * info = lv_label_create(panel);
    lv_obj_set_width(info, 310);
    lv_obj_set_pos(info, 15, 56);
    lv_label_set_long_mode(info, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(info, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(info, COLOR_BASE_ON, 0);
    if(base_pregunta < 0) lv_label_set_text(info, "Toca la base del corredor");
    else                  lv_label_set_text_fmt(info, "Corredor en %s (azul)", nombre_base[base_pregunta & 3]);

    /* Naranja = jugador en base, azul = el corredor de la pregunta,
     * borde blanco = bases que se pueden tocar. */
    for(int i = 0; i < 4; i++) {
        bool es_opcion = (opciones & (1u << i)) != 0;
        lv_color_t col = COLOR_CONTADOR_OFF;
        if(i == base_pregunta)                             col = COLOR_BOLA_ON;
        else if(i == 0 || (s_bases & (1u << (i - 1))))     col = DP_COLOR_JUGADOR;
        if(es_opcion && i == 0) col = COLOR_CONTADOR_OFF;   /* home como opcion = 'ANOTA' */

        lv_obj_t * d = lv_obj_create(panel);
        lv_obj_set_size(d, 52, 52);
        lv_obj_set_pos(d, dp_cx[i] - 26, dp_cy[i] - 26);
        lv_obj_set_style_bg_color(d, col, 0);
        lv_obj_set_style_radius(d, 8, 0);
        lv_obj_set_style_border_color(d, es_opcion ? lv_color_white() : COLOR_BASE_OFF, 0);
        lv_obj_set_style_border_width(d, es_opcion ? 3 : 2, 0);
        lv_obj_set_style_pad_all(d, 0, 0);
        lv_obj_set_style_transform_pivot_x(d, 26, 0);
        lv_obj_set_style_transform_pivot_y(d, 26, 0);
        lv_obj_set_style_transform_rotation(d, 450, 0);
        lv_obj_remove_flag(d, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_remove_flag(d, LV_OBJ_FLAG_CLICKABLE);

        lv_obj_t * l = lv_label_create(panel);
        lv_obj_set_width(l, 70);
        lv_obj_set_pos(l, dp_cx[i] - 35, dp_cy[i] - 8);
        lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_color(l, lv_color_white(), 0);
        lv_label_set_text(l, (i == 0 && es_opcion) ? "ANOTA" : dp_txt[i]);
        lv_obj_remove_flag(l, LV_OBJ_FLAG_CLICKABLE);

        if(es_opcion) {
            lv_obj_t * z = lv_obj_create(panel);
            lv_obj_set_size(z, 70, 70);
            lv_obj_set_pos(z, dp_cx[i] - 35, dp_cy[i] - 35);
            lv_obj_set_style_bg_opa(z, LV_OPA_TRANSP, 0);
            lv_obj_set_style_border_width(z, 0, 0);
            lv_obj_set_style_pad_all(z, 0, 0);
            lv_obj_remove_flag(z, LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_add_event_cb(z, pq_zona_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);
        }
    }

    pq_boton(panel, "Cancelar", COLOR_CONTADOR_OFF, 20, 310, 300, 50, pq_cancelar_cb, 0);
}

/* ------------------------------------------------------------------ */
/* Popup de error defensivo (Button_Accion9)                            */
/* El bateador y los corredores quedan en las bases que se toquen;      */
/* los que no queden en base cuentan como carrera anotada.              */
/* ------------------------------------------------------------------ */
static struct {
    lv_obj_t * overlay;
    lv_obj_t * title;
    lv_obj_t * info;
    lv_obj_t * dia[4];
    uint8_t    abierto;
    uint8_t    ocupadas;     /* mascara por indice (bits 1..3) */
    uint8_t    jugadores;    /* bateador + corredores */
} er;

static uint8_t er_contar(uint8_t m)
{
    uint8_t n = 0;
    for(int i = 0; i < 4; i++) if(m & (1u << i)) n++;
    return n;
}

static void er_refrescar(void)
{
    if(!er.abierto) return;
    for(int i = 0; i < 4; i++) {
        lv_color_t col = COLOR_CONTADOR_OFF;
        if(i > 0 && (er.ocupadas & (1u << i))) col = DP_COLOR_JUGADOR;
        lv_obj_set_style_bg_color(er.dia[i], col, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    uint8_t o = er_contar(er.ocupadas);
    if(er.jugadores == 1) {
        lv_label_set_text(er.info, "Toca la base donde quedó el bateador");
    }
    else {
        lv_label_set_text_fmt(er.info, "En base: %u de %u   |   Carreras: %u",
                              (unsigned)o, (unsigned)er.jugadores, (unsigned)(er.jugadores - o));
    }
}

static void er_cerrar(void)
{
    if(!er.abierto) return;
    er.abierto = 0;
    lv_obj_delete_async(er.overlay);
    er.overlay = NULL;
}

static void er_zona_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED || !er.abierto) return;
    int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if(idx == 0) return;                                   /* home no se ocupa */
    uint8_t bit = (uint8_t)(1u << idx);

    if(er.jugadores == 1) {
        er.ocupadas = bit;                                 /* solo el bateador: elegir una base */
    }
    else if(er.ocupadas & bit) {
        er.ocupadas &= (uint8_t)~bit;
    }
    else if(er_contar(er.ocupadas) < er.jugadores) {
        er.ocupadas |= bit;
    }
    er_refrescar();
}

static void er_cancelar_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    er_cerrar();
}

static void er_aceptar_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED || !er.abierto) return;

    undo_guardar();
    lanz_contar();   /* bola en juego */
    uint8_t carreras = (uint8_t)(er.jugadores - er_contar(er.ocupadas));

    /* El error se anota al equipo que defiende. */
    if(s_bateando_eq1) {
        s_errores_eq2++;
        poner_numero(ui_Errores_EQ2, s_errores_eq2);
    }
    else {
        s_errores_eq1++;
        poner_numero(ui_Errores_EQ1, s_errores_eq1);
    }

    s_bases = (uint8_t)((er.ocupadas >> 1) & 0x07);
    bases_refrescar();
    for(uint8_t i = 0; i < carreras; i++) analisis_carrera_sumar();
    analisis_conteo_reiniciar();   /* nuevo bateador */
    er_cerrar();
}

static void er_abrir(void)
{
    if(er.abierto || dp.abierto || pq.abierto) return;
    memset(&er, 0, sizeof(er));
    er.abierto = 1;

    uint8_t corredores = (uint8_t)(((s_bases >> 0) & 1) + ((s_bases >> 1) & 1) + ((s_bases >> 2) & 1));
    er.jugadores = (uint8_t)(corredores + 1);

    /* Propuesta inicial: igual que una base por bolas (bateador a 1ra y avanzan los forzados). */
    uint8_t b = s_bases & 0x07;
    if(!(b & 0x01))      b |= 0x01;
    else if(!(b & 0x02)) b |= 0x02;
    else if(!(b & 0x04)) b |= 0x04;
    er.ocupadas = (uint8_t)(b << 1);

    er.overlay = lv_obj_create(lv_layer_top());
    lv_obj_set_size(er.overlay, lv_pct(100), lv_pct(100));
    lv_obj_set_pos(er.overlay, 0, 0);
    lv_obj_set_style_bg_color(er.overlay, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(er.overlay, LV_OPA_60, 0);
    lv_obj_set_style_border_width(er.overlay, 0, 0);
    lv_obj_set_style_radius(er.overlay, 0, 0);
    lv_obj_set_style_pad_all(er.overlay, 0, 0);
    lv_obj_remove_flag(er.overlay, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(er.overlay, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t * panel = lv_obj_create(er.overlay);
    lv_obj_set_size(panel, 340, 380);
    lv_obj_center(panel);
    lv_obj_set_style_bg_color(panel, DP_COLOR_FONDO, 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(panel, COLOR_CONTADOR_OFF, 0);
    lv_obj_set_style_border_width(panel, 2, 0);
    lv_obj_set_style_radius(panel, 14, 0);
    lv_obj_set_style_pad_all(panel, 0, 0);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_SCROLLABLE);

    er.title = lv_label_create(panel);
    lv_obj_set_width(er.title, 310);
    lv_obj_set_pos(er.title, 15, 10);
    lv_label_set_long_mode(er.title, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(er.title, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(er.title, lv_color_white(), 0);
    lv_label_set_text(er.title, (er.jugadores == 1)
        ? "Error defensivo\n¿En qué base quedó el bateador?"
        : "Error defensivo\n¿Qué pasó con el bateador y los corredores?");

    er.info = lv_label_create(panel);
    lv_obj_set_width(er.info, 310);
    lv_obj_set_pos(er.info, 15, 56);
    lv_label_set_long_mode(er.info, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(er.info, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(er.info, COLOR_BASE_ON, 0);

    for(int i = 0; i < 4; i++) {
        lv_obj_t * d = lv_obj_create(panel);
        lv_obj_set_size(d, 52, 52);
        lv_obj_set_pos(d, dp_cx[i] - 26, dp_cy[i] - 26);
        lv_obj_set_style_radius(d, 8, 0);
        lv_obj_set_style_border_color(d, COLOR_BASE_OFF, 0);
        lv_obj_set_style_border_width(d, 2, 0);
        lv_obj_set_style_pad_all(d, 0, 0);
        lv_obj_set_style_transform_pivot_x(d, 26, 0);
        lv_obj_set_style_transform_pivot_y(d, 26, 0);
        lv_obj_set_style_transform_rotation(d, 450, 0);
        lv_obj_remove_flag(d, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_remove_flag(d, LV_OBJ_FLAG_CLICKABLE);
        er.dia[i] = d;

        lv_obj_t * t = lv_label_create(panel);
        lv_obj_set_width(t, 70);
        lv_obj_set_pos(t, dp_cx[i] - 35, dp_cy[i] - 8);
        lv_obj_set_style_text_align(t, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_color(t, lv_color_white(), 0);
        lv_label_set_text(t, dp_txt[i]);
        lv_obj_remove_flag(t, LV_OBJ_FLAG_CLICKABLE);

        lv_obj_t * z = lv_obj_create(panel);
        lv_obj_set_size(z, 70, 70);
        lv_obj_set_pos(z, dp_cx[i] - 35, dp_cy[i] - 35);
        lv_obj_set_style_bg_opa(z, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(z, 0, 0);
        lv_obj_set_style_pad_all(z, 0, 0);
        lv_obj_remove_flag(z, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_event_cb(z, er_zona_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);
    }

    pq_boton(panel, "Cancelar", COLOR_CONTADOR_OFF, 20, 310, 140, 50, er_cancelar_cb, 0);
    pq_boton(panel, "Aceptar", COLOR_BASE_ON, 180, 310, 140, 50, er_aceptar_cb, 0);

    er_refrescar();
}

static void accion_foul_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_foul();
}

static void accion_borrar_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_deshacer();
}

static void accion_base_gratis_cb(lv_event_t * e)   /* PELOTAZO: no es boleto */
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_base_gratis();   /* guarda el estado para deshacer ANTES de cambiar nada */
    lanz_contar();            /* el pelotazo si es un lanzamiento (el boleto intencional no) */
}

static void accion_boleto_cb(lv_event_t * e)   /* BOLETO intencional: cuenta BB del lanzador */
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_base_gratis();   /* guarda el estado para deshacer ANTES de cambiar nada */
    if(lanzador_defiende()) { s_bb_lanz++; kbb_refrescar(); }
}

/* ------------------------------------------------------------------ */
/* Base robada (Button_Accion12)                                        */
/* ------------------------------------------------------------------ */
static void robo_aplicar(int base)   /* base = 1, 2 o 3: base donde estaba el corredor */
{
    if(base < 1 || base > 3 || !(s_bases & (1u << (base - 1)))) return;

    undo_guardar();
    s_bases &= (uint8_t)~(1u << (base - 1));
    if(base == 3) {
        analisis_carrera_sumar();              /* robo de home: anota */
    }
    else {
        s_bases |= (uint8_t)(1u << base);      /* pasa a la base siguiente */
    }
    bases_refrescar();
}

static void robo_resuelto_cb(int base)
{
    robo_aplicar(base);
}

static void accion_robo_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_base_robada();
}

static void accion_error_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_error_defensivo();
}

static void accion_triple_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_triple();
}

static void accion_doble_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_doble();
}

static void accion_homerun_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    analisis_homerun();
}

static void accion_doble_play_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;

    uint8_t corredores = (uint8_t)(((s_bases >> 0) & 1) + ((s_bases >> 1) & 1) + ((s_bases >> 2) & 1));
    if(corredores >= 2 && s_outs == 0) {
        /* Con 0 outs el doble play deja la jugada abierta: el usuario decide
         * quienes son out y como quedan las bases. */
        dp_abrir();
    }
    else {
        /* Con 1 o 2 outs el 3er out cierra la entrada; con 0-1 corredores no hay que elegir. */
        analisis_doble_play();
    }
}

/* ------------------------------------------------------------------ */
/* API pública                                                          */
/* ------------------------------------------------------------------ */
void analisis_dynamic_init(void)
{
    /* Los popups viven en lv_layer_top() y sobreviviran al cambio de pantalla. */
    dp_cerrar();
    pq_cerrar();
    er_cerrar();
    tp_cerrar();

    /* Zonas de strike = el 3x3 central de la cuadrícula 5x5 */
    static const int zonas_strike[] = { 7, 8, 9, 12, 13, 14, 17, 18, 19 };
    /* Zonas de bola = las 16 del contorno */
    static const int zonas_bola[]   = { 1, 2, 3, 4, 5, 6, 10, 11,
                                        15, 16, 20, 21, 22, 23, 24, 25 };

    lv_obj_t * z[26] = { NULL,   /* índice 0 sin usar: z[n] = ZonaN */
        ui_Zona1_Estadis1,  ui_Zona2_Estadis1,  ui_Zona3_Estadis1,
        ui_Zona4_Estadis1,  ui_Zona5_Estadis1,  ui_Zona6_Estadis1,
        ui_Zona7_Estadis1,  ui_Zona8_Estadis1,  ui_Zona9_Estadis1,
        ui_Zona10_Estadis1, ui_Zona11_Estadis1, ui_Zona12_Estadis1,
        ui_Zona13_Estadis1, ui_Zona14_Estadis1, ui_Zona15_Estadis1,
        ui_Zona16_Estadis1, ui_Zona17_Estadis1, ui_Zona18_Estadis1,
        ui_Zona19_Estadis1, ui_Zona20_Estadis1, ui_Zona21_Estadis1,
        ui_Zona22_Estadis1, ui_Zona23_Estadis1, ui_Zona24_Estadis1,
        ui_Zona25_Estadis1,
    };

    for(size_t i = 0; i < sizeof(zonas_strike) / sizeof(zonas_strike[0]); i++) {
        int n = zonas_strike[i];
        if(z[n] == NULL) continue;
        lv_obj_remove_event_cb(z[n], zona_strike_cb);
        lv_obj_remove_event_cb(z[n], zona_bola_cb);
        lv_obj_add_event_cb(z[n], zona_strike_cb, LV_EVENT_CLICKED, (void *)(intptr_t)n);
    }
    for(size_t i = 0; i < sizeof(zonas_bola) / sizeof(zonas_bola[0]); i++) {
        int n = zonas_bola[i];
        if(z[n] == NULL) continue;
        lv_obj_remove_event_cb(z[n], zona_strike_cb);
        lv_obj_remove_event_cb(z[n], zona_bola_cb);
        lv_obj_add_event_cb(z[n], zona_bola_cb, LV_EVENT_CLICKED, (void *)(intptr_t)n);
    }

    /* Button_Accion4 = hit */
    if(ui_Button_Accion4) {
        lv_obj_remove_event_cb(ui_Button_Accion4, accion_hit_cb);
        lv_obj_add_event_cb(ui_Button_Accion4, accion_hit_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion2 = out */
    if(ui_Button_Accion2) {
        lv_obj_remove_event_cb(ui_Button_Accion2, accion_out_cb);
        lv_obj_add_event_cb(ui_Button_Accion2, accion_out_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion3 = doble out (doble play) */
    if(ui_Button_Accion3) {
        lv_obj_remove_event_cb(ui_Button_Accion3, accion_doble_play_cb);
        lv_obj_add_event_cb(ui_Button_Accion3, accion_doble_play_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion1 = foul */
    if(ui_Button_Accion1) {
        lv_obj_remove_event_cb(ui_Button_Accion1, accion_foul_cb);
        lv_obj_add_event_cb(ui_Button_Accion1, accion_foul_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion12 = base robada */
    if(ui_Button_Accion12) {
        lv_obj_remove_event_cb(ui_Button_Accion12, accion_robo_cb);
        lv_obj_add_event_cb(ui_Button_Accion12, accion_robo_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion11 = borrar la ultima jugada */
    if(ui_Button_Accion11) {
        lv_obj_remove_event_cb(ui_Button_Accion11, accion_borrar_cb);
        lv_obj_add_event_cb(ui_Button_Accion11, accion_borrar_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion8 = boleto intencional, Button_Accion10 = pelotazo (bateador golpeado) */
    if(ui_Button_Accion8) {
        lv_obj_remove_event_cb(ui_Button_Accion8, accion_boleto_cb);
        lv_obj_add_event_cb(ui_Button_Accion8, accion_boleto_cb, LV_EVENT_CLICKED, NULL);
    }
    if(ui_Button_Accion10) {
        lv_obj_remove_event_cb(ui_Button_Accion10, accion_base_gratis_cb);
        lv_obj_add_event_cb(ui_Button_Accion10, accion_base_gratis_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion9 = error del equipo que defiende */
    if(ui_Button_Accion9) {
        lv_obj_remove_event_cb(ui_Button_Accion9, accion_error_cb);
        lv_obj_add_event_cb(ui_Button_Accion9, accion_error_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion6 = triple */
    if(ui_Button_Accion6) {
        lv_obj_remove_event_cb(ui_Button_Accion6, accion_triple_cb);
        lv_obj_add_event_cb(ui_Button_Accion6, accion_triple_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion5 = doble */
    if(ui_Button_Accion5) {
        lv_obj_remove_event_cb(ui_Button_Accion5, accion_doble_cb);
        lv_obj_add_event_cb(ui_Button_Accion5, accion_doble_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Button_Accion7 = homerun */
    if(ui_Button_Accion7) {
        lv_obj_remove_event_cb(ui_Button_Accion7, accion_homerun_cb);
        lv_obj_add_event_cb(ui_Button_Accion7, accion_homerun_cb, LV_EVENT_CLICKED, NULL);
    }

    /* Estado visual inicial: contadores en gris (o con el conteo actual) */
    strikes_refrescar();
    bolas_refrescar();
    outs_refrescar();
    bases_refrescar();
    marcador_refrescar();
    chips_refrescar();
}

void analisis_set_strikes(int n)
{
    if(n < 0) n = 0;
    if(n > MAX_STRIKES) n = MAX_STRIKES;
    s_strikes = (uint8_t)n;
    strikes_refrescar();
}

int analisis_get_strikes(void) { return s_strikes; }

void analisis_set_bolas(int n)
{
    if(n < 0) n = 0;
    if(n > MAX_BOLAS) n = MAX_BOLAS;
    s_bolas = (uint8_t)n;
    bolas_refrescar();
}

int analisis_get_bolas(void) { return s_bolas; }

void analisis_conteo_reiniciar(void)
{
    s_secu_pend = true;    /* nuevo bateador: la secuencia se limpia con su primer lanzamiento */
    s_strikes = 0;
    s_bolas   = 0;
    strikes_refrescar();
    bolas_refrescar();
}

void analisis_set_outs(int n)
{
    if(n < 0) n = 0;
    if(n > MAX_OUTS) n = MAX_OUTS;
    s_outs = (uint8_t)n;
    outs_refrescar();
}

int analisis_get_outs(void) { return s_outs; }

void analisis_out_sumar(void)
{
    s_outs++;
    printf("[analisis] out sumado: outs=%u\n", s_outs);
    /* Out del lanzador: solo si su equipo esta a la defensiva (el otro equipo batea).
     * Se cuenta antes de cerrar la media entrada, que cambia s_bateando_eq1. */
    if(s_bateando_eq1 == (LANZADOR_EQUIPO == 2)) {
        s_outs_lanz++;
        il_refrescar();
    }
    if(s_outs > MAX_OUTS) {
        /* Tercer out: se acaba la media entrada. */
        analisis_media_entrada_terminar();
        return;
    }
    outs_refrescar();
}

void analisis_base_set(int base, bool ocupada)
{
    if(base < 1 || base > 3) return;
    if(ocupada) s_bases |= (uint8_t)(1u << (base - 1));
    else        s_bases &= (uint8_t)~(1u << (base - 1));
    bases_refrescar();
}

bool analisis_base_ocupada(int base)
{
    if(base < 1 || base > 3) return false;
    return (s_bases >> (base - 1)) & 0x01;
}

void analisis_bases_limpiar(void)
{
    s_bases = 0;
    bases_refrescar();
}

void analisis_base_por_bolas(void)
{
    /* El bateador va a 1ra. Solo avanzan los corredores forzados:
     *  - 1ra libre                      -> ocupa 1ra
     *  - 1ra ocupada, 2da libre         -> ocupa 2da   (1ra sigue ocupada por el bateador)
     *  - 1ra y 2da ocupadas, 3ra libre  -> ocupa 3ra
     *  - bases llenas                   -> anota una carrera (las bases siguen llenas)
     * Un corredor en 3ra con 2da libre NO avanza (no está forzado). */
    if(!(s_bases & 0x01))      s_bases |= 0x01;
    else if(!(s_bases & 0x02)) s_bases |= 0x02;
    else if(!(s_bases & 0x04)) s_bases |= 0x04;
    else {
        /* Bases llenas: carrera forzada para el equipo que batea. */
        analisis_carrera_sumar();
    }
    bases_refrescar();
}

void analisis_carrera_sumar(void)
{
    if(s_bateando_eq1) {
        s_carreras_eq1++;
        s_ining_alta[s_entrada]++;
        s_show_alta[s_entrada] = true;
        poner_numero(ui_Carreras_EQ1, s_carreras_eq1);
        poner_numero(ining_obj(true, s_entrada), s_ining_alta[s_entrada]);
    }
    else {
        s_carreras_eq2++;
        s_ining_baja[s_entrada]++;
        s_show_baja[s_entrada] = true;
        poner_numero(ui_Carreras_EQ2, s_carreras_eq2);
        poner_numero(ining_obj(false, s_entrada), s_ining_baja[s_entrada]);
    }
}

int analisis_get_carreras_eq1(void) { return s_carreras_eq1; }

void analisis_media_entrada_terminar(void)
{
    printf("[analisis] FIN media entrada: entrada=%u eq1=%d carreras=%u\n", s_entrada, s_bateando_eq1,
           s_bateando_eq1 ? s_ining_alta[s_entrada] : s_ining_baja[s_entrada]);
    /* 1) Dejar en el linescore las carreras de la media entrada que termina
     *    (3 -> "3", ninguna -> "0"). */
    if(s_bateando_eq1) { s_show_alta[s_entrada] = true; poner_numero(ining_obj(true,  s_entrada), s_ining_alta[s_entrada]); }
    else               { s_show_baja[s_entrada] = true; poner_numero(ining_obj(false, s_entrada), s_ining_baja[s_entrada]); }

    /* 2) Cambiar de equipo al bate; si terminó la baja, pasa a la siguiente entrada. */
    if(s_bateando_eq1) {
        s_bateando_eq1 = false;
    }
    else {
        s_bateando_eq1 = true;
        if(s_entrada < NUM_INNINGS) s_entrada++;
        /* TODO: fin del juego / extra innings al terminar la baja de la 7ma. */
    }

    /* 3) Limpiar outs, conteo y bases para la nueva media entrada. */
    s_outs = 0;
    outs_refrescar();
    analisis_conteo_reiniciar();
    analisis_bases_limpiar();
}

int analisis_get_entrada(void)      { return s_entrada; }
bool analisis_bateando_eq1(void)    { return s_bateando_eq1; }

static bool s_hit_anota_2da = false;   /* respuesta guardada mientras se pregunta por el de 1ra */

static void hit_aplicar(bool anota_2da, bool primera_a_3ra)
{
    undo_guardar();
    lanz_contar();   /* bola en juego */
    /* El corredor de 3ra siempre anota con un hit. Se saca de la base antes de
     * mover a los demas, para que no cuente doble si las bases estaban llenas. */
    if(s_bases & 0x04) {
        s_bases &= (uint8_t)~0x04;
        analisis_carrera_sumar();
    }

    /* Corredor de 2da: anota o llega a 3ra, segun lo elegido. */
    if(s_bases & 0x02) {
        s_bases &= (uint8_t)~0x02;
        if(anota_2da) analisis_carrera_sumar();
        else          s_bases |= 0x04;
    }

    /* Corredor de 1ra: llega a 3ra si se eligio asi; si no, a 2da (forzado). */
    if((s_bases & 0x01) && primera_a_3ra) {
        s_bases &= (uint8_t)~0x01;
        s_bases |= 0x04;
    }

    /* Bateador a 1ra y avanzan los corredores forzados. */
    analisis_base_por_bolas();

    if(s_bateando_eq1) {
        s_hits_eq1++;
        poner_numero(ui_HIT_EQ1, s_hits_eq1);
    }
    else {
        s_hits_eq2++;
        poner_numero(ui_HIT_EQ2, s_hits_eq2);
    }

    /* Nuevo bateador. */
    analisis_conteo_reiniciar();
}

/* Pregunta por el corredor de 1ra: true = 2da, false = 3ra. */
static void hit_resp_1ra_cb(int base)
{
    hit_aplicar(s_hit_anota_2da, base == 3);
}

static void hit_preguntar_1ra(void)
{
    pq_abrir("Hit\n¿En qué base quedó el corredor?",
             (uint8_t)((1u << 2) | (1u << 3)), hit_resp_1ra_cb, 1);
}

/* Pregunta por el corredor de 2da: true = anoto, false = llego a 3ra. */
static void hit_resp_2da_cb(int base)
{
    bool anota = (base == 0);
    s_hit_anota_2da = anota;
    if((s_bases & 0x01) && anota) {
        /* La 3ra queda libre: el de 1ra puede elegir 2da o 3ra. */
        hit_preguntar_1ra();
    }
    else {
        /* Si el de 2da se queda en 3ra, el de 1ra solo puede llegar a 2da. */
        hit_aplicar(anota, false);
    }
}

void analisis_hit(void)
{
    s_hit_anota_2da = false;

    if(s_bases & 0x02) {
        pq_abrir("Hit\n¿En qué base quedó el corredor?",
                 (uint8_t)((1u << 0) | (1u << 3)), hit_resp_2da_cb, 2);
    }
    else if(s_bases & 0x01) {
        hit_preguntar_1ra();
    }
    else {
        hit_aplicar(false, false);
    }
}

int analisis_get_hits_eq1(void) { return s_hits_eq1; }
int analisis_get_hits_eq2(void) { return s_hits_eq2; }

void analisis_out_bateador(void)
{
    undo_guardar();
    lanz_contar();   /* bola en juego */
    /* Nuevo bateador: el conteo vuelve a 0-0. Se reinicia antes de sumar el out
     * porque el 3er out ya limpia todo al cerrar la media entrada. */
    analisis_conteo_reiniciar();
    analisis_out_sumar();
}

bool analisis_doble_play(void)
{
    /* Solo es posible con al menos un corredor en base. */
    if(s_bases == 0) return false;
    undo_guardar();
    lanz_contar();   /* bola en juego */

    /* Sale el bateador y un corredor: el de 1ra si hay (es el forzado);
     * si no, el mas adelantado. */
    if(s_bases & 0x01)      s_bases &= (uint8_t)~0x01;
    else if(s_bases & 0x02) s_bases &= (uint8_t)~0x02;
    else                    s_bases &= (uint8_t)~0x04;
    bases_refrescar();

    analisis_conteo_reiniciar();

    /* Dos outs, pero sin pasarse del tercero: si ya habia 1 o 2 outs,
     * el tercero cierra la media entrada y no se cuenta uno extra en la siguiente. */
    int faltan = (MAX_OUTS + 1) - (int)s_outs;
    int n = (faltan < 2) ? faltan : 2;
    for(int i = 0; i < n; i++) analisis_out_sumar();
    return true;
}

void analisis_homerun(void)
{
    undo_guardar();
    lanz_contar();   /* bola en juego */
    /* Anotan todos los corredores en base mas el bateador. */
    uint8_t corredores = (uint8_t)(((s_bases >> 0) & 1) + ((s_bases >> 1) & 1) + ((s_bases >> 2) & 1));
    uint8_t carreras = (uint8_t)(corredores + 1);

    for(uint8_t i = 0; i < carreras; i++) analisis_carrera_sumar();

    /* El jonron tambien cuenta como hit para el equipo que batea. */
    if(s_bateando_eq1) {
        s_hits_eq1++;
        poner_numero(ui_HIT_EQ1, s_hits_eq1);
    }
    else {
        s_hits_eq2++;
        poner_numero(ui_HIT_EQ2, s_hits_eq2);
    }

    analisis_bases_limpiar();
    analisis_conteo_reiniciar();   /* nuevo bateador */
}

void analisis_dynamic_deinit(void)
{
    dp_cerrar();
    pq_cerrar();
    er_cerrar();
    tp_cerrar();
}

static void doble_aplicar(bool anota_1ra)
{
    undo_guardar();
    lanz_contar();   /* bola en juego */
    /* Doble: el bateador queda en 2da. Los corredores de 2da y 3ra anotan.
     * El de 1ra anota o llega a 3ra, segun lo elegido. */
    uint8_t en_1ra = (s_bases & 0x01) ? 1 : 0;
    uint8_t carreras = (uint8_t)(((s_bases >> 1) & 1) + ((s_bases >> 2) & 1));
    if(en_1ra && anota_1ra) carreras++;

    s_bases = (uint8_t)(0x02 | ((en_1ra && !anota_1ra) ? 0x04 : 0x00));
    bases_refrescar();

    for(uint8_t i = 0; i < carreras; i++) analisis_carrera_sumar();

    /* El doble cuenta como hit para el equipo que batea. */
    if(s_bateando_eq1) {
        s_hits_eq1++;
        poner_numero(ui_HIT_EQ1, s_hits_eq1);
    }
    else {
        s_hits_eq2++;
        poner_numero(ui_HIT_EQ2, s_hits_eq2);
    }

    analisis_conteo_reiniciar();   /* nuevo bateador */
}

static void doble_resuelto_cb(int base)
{
    doble_aplicar(base == 0);
}

void analisis_doble(void)
{
    /* Con un corredor en 1ra se pregunta si anoto o llego a 3ra. */
    if(s_bases & 0x01) {
        pq_abrir("Doble\n¿En qué base quedó el corredor?",
                 (uint8_t)((1u << 0) | (1u << 3)), doble_resuelto_cb, 1);
    }
    else {
        doble_aplicar(false);
    }
}

void analisis_triple(void)
{
    undo_guardar();
    lanz_contar();   /* bola en juego */
    /* Triple: todos los corredores en base anotan y el bateador queda en 3ra. */
    uint8_t carreras = (uint8_t)(((s_bases >> 0) & 1) + ((s_bases >> 1) & 1) + ((s_bases >> 2) & 1));

    s_bases = 0x04;
    bases_refrescar();

    for(uint8_t i = 0; i < carreras; i++) analisis_carrera_sumar();

    /* El triple cuenta como hit para el equipo que batea. */
    if(s_bateando_eq1) {
        s_hits_eq1++;
        poner_numero(ui_HIT_EQ1, s_hits_eq1);
    }
    else {
        s_hits_eq2++;
        poner_numero(ui_HIT_EQ2, s_hits_eq2);
    }

    analisis_conteo_reiniciar();   /* nuevo bateador */
}

void analisis_error_defensivo(void)
{
    /* Abre el popup; el error se suma al aceptar (Cancelar no cambia nada). */
    er_abrir();
}

int analisis_get_errores_eq1(void) { return s_errores_eq1; }
int analisis_get_errores_eq2(void) { return s_errores_eq2; }

void analisis_base_gratis(void)
{
    undo_guardar();
    /* Boleto intencional o pelotazo: el bateador va a 1ra, avanzan solo los
     * corredores forzados (con bases llenas anota una carrera) y no cuenta como hit. */
    analisis_base_por_bolas();
    analisis_conteo_reiniciar();   /* nuevo bateador */
}

void analisis_deshacer(void)
{
    undo_restaurar();
}

/* ------------------------------------------------------------------ */
/* Popup obligatorio: tipo de lanzamiento                               */
/* Se abre al tocar una zona (o al presionar FAUL). El lanzamiento no   */
/* se registra hasta que se elige un tipo; Cancelar lo descarta.        */
/* ------------------------------------------------------------------ */
static struct {
    lv_obj_t * overlay;
    uint8_t    abierto;
    uint8_t    res;
    uint8_t    zona;
} tp;

static void tp_cerrar(void)
{
    if(!tp.abierto) return;
    tp.abierto = 0;
    lv_obj_delete_async(tp.overlay);
    tp.overlay = NULL;
}

static void tp_tipo_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED || !tp.abierto) return;
    int idx = (int)(intptr_t)lv_event_get_user_data(e);
    uint8_t res = tp.res, zona = tp.zona;
    tp_cerrar();
    s_tipo_sel = (int8_t)idx;      /* queda resaltado en los chips y se guarda en la secuencia */
    chips_refrescar();
    lanzamiento_aplicar(res, zona);
}

static void tp_cancelar_cb(lv_event_t * e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    tp_cerrar();
}

static void tipo_popup_abrir(uint8_t res, uint8_t zona)
{
    if(tp.abierto || dp.abierto || pq.abierto || er.abierto) return;

    lv_obj_t * lbl[6] = { ui_Label_Lanzamientosdispo,  ui_Label_Lanzamientosdispo1,
                          ui_Label_Lanzamientosdispo2, ui_Label_Lanzamientosdispo3,
                          ui_Label_Lanzamientosdispo4, ui_Label_Lanzamientosdispo5 };

    memset(&tp, 0, sizeof(tp));
    tp.abierto = 1;
    tp.res     = res;
    tp.zona    = zona;

    tp.overlay = lv_obj_create(lv_layer_top());
    lv_obj_set_size(tp.overlay, lv_pct(100), lv_pct(100));
    lv_obj_set_pos(tp.overlay, 0, 0);
    lv_obj_set_style_bg_color(tp.overlay, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(tp.overlay, LV_OPA_60, 0);
    lv_obj_set_style_border_width(tp.overlay, 0, 0);
    lv_obj_set_style_radius(tp.overlay, 0, 0);
    lv_obj_set_style_pad_all(tp.overlay, 0, 0);
    lv_obj_remove_flag(tp.overlay, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(tp.overlay, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t * panel = lv_obj_create(tp.overlay);
    lv_obj_set_size(panel, 340, 310);
    lv_obj_center(panel);
    lv_obj_set_style_bg_color(panel, DP_COLOR_FONDO, 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(panel, COLOR_CONTADOR_OFF, 0);
    lv_obj_set_style_border_width(panel, 2, 0);
    lv_obj_set_style_radius(panel, 14, 0);
    lv_obj_set_style_pad_all(panel, 0, 0);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t * t = lv_label_create(panel);
    lv_obj_set_width(t, 310);
    lv_obj_set_pos(t, 15, 10);
    lv_label_set_long_mode(t, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(t, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(t, lv_color_white(), 0);
    if(res == LANZ_STRIKE)    lv_label_set_text_fmt(t, "Strike - Zona %u\n¿Qué tipo de lanzamiento fue?", (unsigned)zona);
    else if(res == LANZ_BOLA) lv_label_set_text_fmt(t, "Bola - Zona %u\n¿Qué tipo de lanzamiento fue?", (unsigned)zona);
    else                      lv_label_set_text(t, "Foul\n¿Qué tipo de lanzamiento fue?");

    for(int i = 0; i < 6; i++) {
        lv_obj_t * b = lv_button_create(panel);
        lv_obj_set_size(b, 150, 50);
        lv_obj_set_pos(b, 15 + (i % 2) * 160, 62 + (i / 2) * 58);
        bool sel = (i == s_tipo_sel);
        lv_obj_set_style_bg_color(b, sel ? lv_color_hex(0x00D2FE) : lv_color_hex(0x14171C), 0);
        lv_obj_set_style_border_color(b, lv_color_hex(0x00D2FE), 0);
        lv_obj_set_style_border_width(b, 1, 0);
        lv_obj_add_event_cb(b, tp_tipo_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);

        lv_obj_t * l = lv_label_create(b);
        lv_obj_set_width(l, 134);
        lv_label_set_long_mode(l, LV_LABEL_LONG_WRAP);
        lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_color(l, sel ? lv_color_hex(0x14171C) : lv_color_hex(0x00D2FE), 0);
        lv_label_set_text(l, lbl[i] ? lv_label_get_text(lbl[i]) : "-");
        lv_obj_center(l);
    }

    pq_boton(panel, "Cancelar", COLOR_CONTADOR_OFF, 15, 240, 310, 46, tp_cancelar_cb, 0);
}

void analisis_foul(void)
{
    /* Foul: pide el tipo de lanzamiento y luego lo registra (strike si hay menos de 2). */
    tipo_popup_abrir(LANZ_FOUL, 0);
}

void analisis_base_robada(void)
{
    uint8_t corredores = (uint8_t)(((s_bases >> 0) & 1) + ((s_bases >> 1) & 1) + ((s_bases >> 2) & 1));
    if(corredores == 0) return;                /* boton deshabilitado: nada que hacer */

    if(corredores == 1) {
        /* Un solo corredor: es el que se roba la base. */
        int base = (s_bases & 0x01) ? 1 : (s_bases & 0x02) ? 2 : 3;
        robo_aplicar(base);
        return;
    }

    /* Dos o mas: el usuario toca la base del corredor. Solo pueden robar los que
     * tienen libre la base siguiente (el de 3ra siempre, porque roba home). */
    uint8_t opciones = 0;
    for(int b = 1; b <= 3; b++) {
        if(!(s_bases & (1u << (b - 1)))) continue;
        if(b == 3 || !(s_bases & (1u << b))) opciones |= (uint8_t)(1u << b);
    }
    pq_abrir("Base robada\n¿Qué corredor se robó la base?", opciones, robo_resuelto_cb, -1);
}
