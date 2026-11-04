#include "idioma_receptores.h"
#include "ui.h"
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

/* Este modulo maneja las DOS pantallas de dispositivos e idioma:
 *   PANT_ES -> ui_DISPOSITIVOS_E_IDIOMA    (textos en espanol)
 *   PANT_EN -> ui_DISPOSITIVOS_EIDIOMA_EN  (textos en ingles)
 * El estado (idioma, nombres, latidos) es global y compartido, asi que las dos
 * pantallas siempre muestran lo mismo. */
enum { PANT_ES = 0, PANT_EN = 1, NUM_PANTALLAS = 2 };

/* Estado por receptor. Es global (no depende de la pantalla), asi que
 * sobrevive a los cambios de pantalla de SquareLine. */
static idioma_receptor_t s_idioma[NUM_RECEPTORES];   // todos arrancan en ES (0)

/* OJO con los nombres generados por SquareLine:
 *   ui_Boton_EN5_Rece*  -> boton que dice "ESPAÑOL" / "SPANISH"
 *   ui_Boton_ES5_Rece*  -> boton que dice "INGLES" / "ENGLISH"
 * Se guardan las direcciones de los punteros porque valen NULL hasta que se
 * ejecuta screen_init y cambian cada vez que la pantalla se recrea. */
typedef struct {
    lv_obj_t **btn_es;   // boton "ESPAÑOL" / "SPANISH"
    lv_obj_t **lbl_es;
    lv_obj_t **btn_en;   // boton "INGLES" / "ENGLISH"
    lv_obj_t **lbl_en;
} receptor_widgets_t;

static const receptor_widgets_t s_w[NUM_PANTALLAS][NUM_RECEPTORES] = {
    { /* pantalla en espanol */
        { &ui_Boton_EN5_Rece,  &ui_Label_EN5_Rece,  &ui_Boton_ES5_Rece,  &ui_Label_ES5_Rece  },
        { &ui_Boton_EN5_Rece1, &ui_Label_EN5_Rece1, &ui_Boton_ES5_Rece1, &ui_Label_ES5_Rece1 },
        { &ui_Boton_EN5_Rece2, &ui_Label_EN5_Rece2, &ui_Boton_ES5_Rece2, &ui_Label_ES5_Rece2 },
        { &ui_Boton_EN5_Rece3, &ui_Label_EN5_Rece3, &ui_Boton_ES5_Rece3, &ui_Label_ES5_Rece3 },
    },
    { /* pantalla en ingles */
        { &ui_Boton_EN5_Rece_EN,   &ui_Label_EN5_Rece_EN,   &ui_Boton_ES5_Rece_EN,   &ui_Label_ES5_Rece4      },
        { &ui_Boton_EN5_Rece5,     &ui_Label_EN5_Rece5,     &ui_Boton_ES5_Rece5,     &ui_Label_ES5_Rece5      },
        { &ui_Boton_EN5_Rece6,     &ui_Label_EN5_Rece6_EN,  &ui_Boton_ES5_Rece6_EN,  &ui_Label_ES5_Rece6_EN   },
        { &ui_Boton_EN5_Rece7_EN,  &ui_Label_EN5_Rece7_EN,  &ui_Boton_ES5_Rece7_EN,  &ui_Label_ES5_Rece7_EN   },
    },
};

/* Seleccionado: fondo cian y texto oscuro. No seleccionado: fondo oscuro y texto cian. */
static void estilo_idioma(lv_obj_t *btn, lv_obj_t *lbl, bool activo)
{
    lv_obj_set_style_bg_color(btn, lv_color_hex(activo ? 0x00D9FF : 0x0F1524), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_text_color(lbl, lv_color_hex(activo ? 0x0F1524 : 0x00D9FF), LV_PART_MAIN | LV_STATE_DEFAULT);
}

static void refrescar(int i)
{
    bool es = (s_idioma[i] == IDIOMA_RECEPTOR_ES);
    for(int p = 0; p < NUM_PANTALLAS; p++) {
        const receptor_widgets_t *w = &s_w[p][i];
        if(!*w->btn_es || !*w->btn_en) continue;   // esa pantalla no existe ahora mismo
        estilo_idioma(*w->btn_es, *w->lbl_es, es);
        estilo_idioma(*w->btn_en, *w->lbl_en, !es);
    }
}

/* ---- Indicador de conexion: circulo verde (conectado) / rojo (sin senal) ----
 * El receptor manda un latido cada 2 s. Si pasan mas de TIMEOUT_LATIDO_MS sin
 * latido (3 perdidos) o nunca ha llegado uno, el circulo se pone en rojo. */
#define TIMEOUT_LATIDO_MS   7000
#define COLOR_CONECTADO     0x0DF148
#define COLOR_DESCONECTADO  0xF11D1D

static lv_obj_t **const s_conect[NUM_PANTALLAS][NUM_RECEPTORES] = {
    { &ui_Container_conect,  &ui_Container_conect1, &ui_Container_conect2,    &ui_Container_conect3    },
    { &ui_Container_conect4, &ui_Container_conect5, &ui_Container_conect6_EN, &ui_Container_conect7_EN },
};
static uint32_t s_ultimo_latido[NUM_RECEPTORES];   // lv_tick_get() del ultimo latido
static bool s_visto[NUM_RECEPTORES];               // true si ya llego algun latido
static lv_timer_t *s_timer_conexion = NULL;

static bool esta_conectado(int i)
{
    return s_visto[i] && lv_tick_elaps(s_ultimo_latido[i]) < TIMEOUT_LATIDO_MS;
}

static void pintar_conexion(int i)
{
    uint32_t color = esta_conectado(i) ? COLOR_CONECTADO : COLOR_DESCONECTADO;
    for(int p = 0; p < NUM_PANTALLAS; p++) {
        lv_obj_t *c = *s_conect[p][i];
        if(!c) continue;   // esa pantalla no existe ahora mismo
        lv_obj_set_style_bg_color(c, lv_color_hex(color), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_opa(c, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

static void timer_conexion_cb(lv_timer_t *t)
{
    (void)t;
    for(int i = 0; i < NUM_RECEPTORES; i++) pintar_conexion(i);
}

void idioma_receptor_latido(uint8_t fila)
{
    if(fila >= NUM_RECEPTORES) return;
    s_ultimo_latido[fila] = lv_tick_get();
    s_visto[fila] = true;
    pintar_conexion(fila);
}

/* ---- MAC de cada receptor, mostrada debajo de su nombre ----
 * Deben ser las mismas que receiver_macs[] en main.c del puente C6 (misma
 * fila = mismo receptor). Si cambias una alla, cambiala tambien aqui. */
static const uint8_t s_mac_receptor[NUM_RECEPTORES][6] = {
    {0x58, 0xE6, 0xC5, 0x13, 0x6C, 0xF4},   /* fila 0 - Receptor Audio 1 */
    {0x58, 0xE6, 0xC5, 0x1A, 0x62, 0x78},   /* fila 1 - Receptor Audio 2 */
    {0x58, 0xE6, 0xC5, 0x13, 0xC2, 0xF8},   /* fila 2 - Receptor Audio 3 */
    {0x58, 0xE6, 0xC5, 0x1A, 0xF9, 0x30},   /* fila 3 - Receptor Audio 4 */
};

/* Etiquetas de nombre generadas por SquareLine (hijas de cada boton de fila) */
static lv_obj_t **const s_nombre[NUM_PANTALLAS][NUM_RECEPTORES] = {
    { &ui_Label_Rece,  &ui_Label_Rece1, &ui_Label_Rece2,    &ui_Label_Rece3    },
    { &ui_Label_Rece4, &ui_Label_Rece5, &ui_Label_Rece6_EN, &ui_Label_Rece7_EN },
};

/* Botones de fila (tocarlos abre el editor de nombre) */
static lv_obj_t **const s_fila_btn[NUM_PANTALLAS][NUM_RECEPTORES] = {
    { &ui_Button_Rece,    &ui_Button_Rece1, &ui_Button_Rece2, &ui_Button_Rece3    },
    { &ui_Button_Rece_EN, &ui_Button_Rece5, &ui_Button_Rece6, &ui_Button_Rece7_EN },
};

/* El nombre esta centrado en el boton de fila (45 px de alto) con x = -109 y
 * y = 0. Se sube un poco para que quepan nombre y MAC en la misma fila. */
#define NOMBRE_X        (-109)
#define NOMBRE_Y_ARRIBA (-9)
#define MAC_Y_ABAJO     (9)
#define NOMBRE_ANCHO    130   /* ancho fijo: los nombres largos se cortan con "..." */

/* ---- Nombres editables ----
 * Se guardan en NVS mediante receptor_nombres_nvs.cpp (Preferences). */
extern bool nombres_receptores_cargar(uint8_t fila, char *dst, size_t len);
extern void nombres_receptores_guardar(uint8_t fila, const char *txt);

static char s_nombre_txt[NUM_RECEPTORES][NOMBRE_RECEPTOR_MAX + 1];
static bool s_nombres_cargados = false;

static void cargar_nombres(void)
{
    if(s_nombres_cargados) return;
    for(int i = 0; i < NUM_RECEPTORES; i++) {
        s_nombre_txt[i][0] = '\0';
        nombres_receptores_cargar((uint8_t)i, s_nombre_txt[i], sizeof(s_nombre_txt[i]));
        if(s_nombre_txt[i][0] == '\0')
            snprintf(s_nombre_txt[i], sizeof(s_nombre_txt[i]), "Receptor Audio %d", i + 1);
    }
    s_nombres_cargados = true;
}

const char *idioma_receptor_nombre(int receptor)
{
    cargar_nombres();
    if(receptor < 0 || receptor >= NUM_RECEPTORES) return "";
    return s_nombre_txt[receptor];
}

static void pintar_nombre(int i)
{
    for(int p = 0; p < NUM_PANTALLAS; p++) {
        lv_obj_t *l = *s_nombre[p][i];
        if(!l) continue;   // esa pantalla no existe ahora mismo
        lv_label_set_text(l, s_nombre_txt[i]);
    }
}

void idioma_receptor_set_nombre(int receptor, const char *nombre)
{
    if(receptor < 0 || receptor >= NUM_RECEPTORES || !nombre) return;
    cargar_nombres();

    /* Quita espacios al inicio y al final */
    while(*nombre == ' ') nombre++;
    char tmp[NOMBRE_RECEPTOR_MAX + 1];
    strncpy(tmp, nombre, NOMBRE_RECEPTOR_MAX);
    tmp[NOMBRE_RECEPTOR_MAX] = '\0';
    size_t n = strlen(tmp);
    while(n > 0 && tmp[n - 1] == ' ') tmp[--n] = '\0';

    /* Nombre vacio -> vuelve al nombre por defecto */
    if(n == 0) snprintf(tmp, sizeof(tmp), "Receptor Audio %d", receptor + 1);

    strcpy(s_nombre_txt[receptor], tmp);
    nombres_receptores_guardar((uint8_t)receptor, tmp);
    pintar_nombre(receptor);
}

/* ---- Editor: ventana modal con campo de texto + teclado en pantalla ----
 * Se abre al tocar la fila (fuera de los botones de idioma). */
static lv_obj_t *s_editor = NULL;
static lv_obj_t *s_editor_ta = NULL;
static int s_editor_fila = -1;

static void editor_cerrar_cb(void *arg)
{
    (void)arg;
    if(s_editor) lv_obj_del(s_editor);
    s_editor = NULL;
    s_editor_ta = NULL;
    s_editor_fila = -1;
}

static void editor_kb_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    if(code == LV_EVENT_READY) {   /* tecla OK */
        if(s_editor_ta && s_editor_fila >= 0)
            idioma_receptor_set_nombre(s_editor_fila, lv_textarea_get_text(s_editor_ta));
        lv_async_call(editor_cerrar_cb, NULL);
    } else if(code == LV_EVENT_CANCEL) {   /* tecla de cerrar */
        lv_async_call(editor_cerrar_cb, NULL);
    }
}

static void editor_abrir(int fila, int pantalla)
{
    if(s_editor) return;   /* ya hay uno abierto */
    cargar_nombres();
    s_editor_fila = fila;

    /* Fondo a pantalla completa: tapa la pantalla y bloquea los toques */
    s_editor = lv_obj_create(lv_scr_act());
    lv_obj_remove_style_all(s_editor);
    lv_obj_set_size(s_editor, lv_pct(100), lv_pct(100));
    lv_obj_add_flag(s_editor, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_clear_flag(s_editor, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(s_editor, lv_color_hex(0x0F1524), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(s_editor, 255, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_t *titulo = lv_label_create(s_editor);
    if(pantalla == PANT_EN) lv_label_set_text_fmt(titulo, "Receiver %d name", fila + 1);
    else                    lv_label_set_text_fmt(titulo, "Nombre del receptor %d", fila + 1);
    lv_obj_set_style_text_color(titulo, lv_color_hex(0x00D9FF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_align(titulo, LV_ALIGN_TOP_MID, 0, 8);

    s_editor_ta = lv_textarea_create(s_editor);
    lv_textarea_set_one_line(s_editor_ta, true);
    lv_textarea_set_max_length(s_editor_ta, NOMBRE_RECEPTOR_MAX);
    lv_textarea_set_text(s_editor_ta, s_nombre_txt[fila]);
    lv_obj_set_width(s_editor_ta, 320);
    lv_obj_align(s_editor_ta, LV_ALIGN_TOP_MID, 0, 40);
    lv_obj_set_style_bg_color(s_editor_ta, lv_color_hex(0x0F1524), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_text_color(s_editor_ta, lv_color_hex(0x00D9FF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(s_editor_ta, lv_color_hex(0x00D9FF), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(s_editor_ta, 2, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_t *kb = lv_keyboard_create(s_editor);
    lv_obj_set_size(kb, lv_pct(100), lv_pct(58));
    lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, 0);
    lv_keyboard_set_textarea(kb, s_editor_ta);
    lv_obj_set_style_bg_color(kb, lv_color_hex(0x0F1524), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(kb, lv_color_hex(0x1B2740), LV_PART_ITEMS | LV_STATE_DEFAULT);
    lv_obj_set_style_text_color(kb, lv_color_hex(0x00D9FF), LV_PART_ITEMS | LV_STATE_DEFAULT);
    lv_obj_add_event_cb(kb, editor_kb_cb, LV_EVENT_ALL, NULL);
}

/* user_data = pantalla * NUM_RECEPTORES + fila */
static void fila_click_cb(lv_event_t *e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    int v = (int)(intptr_t)lv_event_get_user_data(e);
    editor_abrir(v % NUM_RECEPTORES, v / NUM_RECEPTORES);
}

static void crear_etiquetas_mac(int p)
{
    for(int i = 0; i < NUM_RECEPTORES; i++) {
        lv_obj_t *nombre = *s_nombre[p][i];
        if(!nombre) continue;

        lv_obj_set_y(nombre, NOMBRE_Y_ARRIBA);
        lv_obj_set_width(nombre, NOMBRE_ANCHO);
        lv_label_set_long_mode(nombre, LV_LABEL_LONG_DOT);
        lv_obj_set_style_text_align(nombre, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_label_set_text(nombre, idioma_receptor_nombre(i));

        lv_obj_t *mac = lv_label_create(lv_obj_get_parent(nombre));
        lv_obj_set_width(mac, LV_SIZE_CONTENT);
        lv_obj_set_height(mac, LV_SIZE_CONTENT);
        lv_obj_set_x(mac, NOMBRE_X);
        lv_obj_set_y(mac, MAC_Y_ABAJO);
        lv_obj_set_align(mac, LV_ALIGN_CENTER);
        lv_label_set_text_fmt(mac, "%02X:%02X:%02X:%02X:%02X:%02X",
                              s_mac_receptor[i][0], s_mac_receptor[i][1], s_mac_receptor[i][2],
                              s_mac_receptor[i][3], s_mac_receptor[i][4], s_mac_receptor[i][5]);
        lv_obj_set_style_text_color(mac, lv_color_hex(0x7FB7C4), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_opa(mac, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
#if LV_FONT_MONTSERRAT_12
        lv_obj_set_style_text_font(mac, &lv_font_montserrat_12, LV_PART_MAIN | LV_STATE_DEFAULT);
#endif
    }
}

/* ESP-NOW: definida en Intento1.ino. Envia el idioma (0 = ES, 1 = EN)
 * solo al receptor de esa fila, usando su MAC registrada. */
extern void enviarIdiomaReceptorA(uint8_t fila, uint8_t idioma);

void idioma_receptor_set(int receptor, idioma_receptor_t idioma)
{
    if(receptor < 0 || receptor >= NUM_RECEPTORES) return;
    s_idioma[receptor] = idioma;
    refrescar(receptor);
    enviarIdiomaReceptorA((uint8_t)receptor, (uint8_t)idioma);   // 0 = ES, 1 = EN
}

idioma_receptor_t idioma_receptor_get(int receptor)
{
    if(receptor < 0 || receptor >= NUM_RECEPTORES) return IDIOMA_RECEPTOR_ES;
    return s_idioma[receptor];
}

/* user_data = receptor * 2 + idioma */
static void idioma_btn_cb(lv_event_t *e)
{
    if(lv_event_get_code(e) != LV_EVENT_CLICKED) return;
    int v = (int)(intptr_t)lv_event_get_user_data(e);
    idioma_receptor_set(v / 2, (idioma_receptor_t)(v % 2));
}

static void init_pantalla(int p)
{
    s_editor = NULL;         /* la pantalla se acaba de recrear: no hay editor abierto */
    s_editor_ta = NULL;
    s_editor_fila = -1;

    crear_etiquetas_mac(p);  /* una vez por cada creacion de la pantalla */

    for(int i = 0; i < NUM_RECEPTORES; i++) {
        /* Tocar la fila (fuera de los botones de idioma) abre el editor de nombre */
        if(*s_fila_btn[p][i])
            lv_obj_add_event_cb(*s_fila_btn[p][i], fila_click_cb, LV_EVENT_CLICKED,
                                (void *)(intptr_t)(p * NUM_RECEPTORES + i));

        const receptor_widgets_t *w = &s_w[p][i];
        if(!*w->btn_es || !*w->btn_en) continue;
        lv_obj_add_event_cb(*w->btn_es, idioma_btn_cb, LV_EVENT_CLICKED,
                            (void *)(intptr_t)(i * 2 + IDIOMA_RECEPTOR_ES));
        lv_obj_add_event_cb(*w->btn_en, idioma_btn_cb, LV_EVENT_CLICKED,
                            (void *)(intptr_t)(i * 2 + IDIOMA_RECEPTOR_EN));
        refrescar(i);   // pinta el estado guardado al recrear la pantalla
    }

    /* Estado de conexion: pinta ahora y revisa timeouts cada segundo */
    for(int i = 0; i < NUM_RECEPTORES; i++) pintar_conexion(i);
    if(!s_timer_conexion) s_timer_conexion = lv_timer_create(timer_conexion_cb, 1000, NULL);
}

void idioma_receptores_init(void)    { init_pantalla(PANT_ES); }
void idioma_receptores_init_en(void) { init_pantalla(PANT_EN); }
