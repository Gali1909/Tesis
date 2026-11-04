#include "estrategia_defensiva_dynamic.h"

/* Funciones expuestas por Intento1.ino (extern "C"): arman la trama UART
 * hacia el modulo C6 de este proyecto (pantalla 3.5"). Equivalentes
 * Arduino de esp_now_send_jugada_texto()/esp_now_send_cancelar_jugada()
 * del proyecto Entrenador (P4). */
extern void enviarJugadaTexto(const char *texto);
extern void cancelarJugada(void);
extern void repetirUltimaJugada(void);

/* Texto EXACTO que YA reconoce el receptor (Jugadores.ino, tablas
 * TEXTOS_JUGADAS_ES / TEXTOS_JUGADAS_EN, indices 2,3,5,6,7,8): son las
 * MISMAS 6 jugadas que ya existen ahi, para reutilizar el audio ya
 * grabado. Si cambias alguno de estos strings, actualiza tambien la
 * entrada correspondiente en Jugadores.ino o esa jugada deja de sonar. */
static const char *TEXTO_VIRAJE_PRIMERA_ES = "Viraje a Primera base ";
static const char *TEXTO_VIRAJE_SEGUNDA_ES = "Viraje a segunda base ";
static const char *TEXTO_NO_DOBLE_ES       = "No Dobles ";
static const char *TEXTO_ROBO_ES           = "Alerta de Robo";
static const char *TEXTO_TOQUE_ES          = "Alerta de toque de bola";
static const char *TEXTO_DOBLE_PLAY_ES     = "Doble Play ";

static const char *TEXTO_VIRAJE_PRIMERA_EN = "Turn toward first base";
static const char *TEXTO_VIRAJE_SEGUNDA_EN = "Turn toward second base";
static const char *TEXTO_NO_DOBLE_EN       = "No Double ";
static const char *TEXTO_ROBO_EN           = "Base Theft Alert";
static const char *TEXTO_TOQUE_EN          = "Ball-Touch Alert";
static const char *TEXTO_DOBLE_PLAY_EN     = "Double Play ";

static void jugada_btn_send_cb(lv_event_t *e)
{
    const char *texto = (const char *)lv_event_get_user_data(e);
    enviarJugadaTexto(texto);
}

static void attach_jugada(lv_obj_t *btn, const char *texto)
{
    if (btn == NULL) return;
    lv_obj_add_event_cb(btn, jugada_btn_send_cb, LV_EVENT_CLICKED, (void *)texto);
}

static void repetir_btn_cb(lv_event_t *e)
{
    (void)e;
    repetirUltimaJugada();
}

static void cancelar_btn_cb(lv_event_t *e)
{
    (void)e;
    cancelarJugada();
}

void estrategia_defensiva_dynamic_init(lv_obj_t *btn_primera, lv_obj_t *btn_segunda,
                                        lv_obj_t *btn_no_doble, lv_obj_t *btn_robo,
                                        lv_obj_t *btn_toque, lv_obj_t *btn_doble_play,
                                        lv_obj_t *btn_repetir, lv_obj_t *btn_cancelar,
                                        bool is_english)
{
    attach_jugada(btn_primera,    is_english ? TEXTO_VIRAJE_PRIMERA_EN : TEXTO_VIRAJE_PRIMERA_ES);
    attach_jugada(btn_segunda,    is_english ? TEXTO_VIRAJE_SEGUNDA_EN : TEXTO_VIRAJE_SEGUNDA_ES);
    attach_jugada(btn_no_doble,   is_english ? TEXTO_NO_DOBLE_EN       : TEXTO_NO_DOBLE_ES);
    attach_jugada(btn_robo,       is_english ? TEXTO_ROBO_EN           : TEXTO_ROBO_ES);
    attach_jugada(btn_toque,      is_english ? TEXTO_TOQUE_EN          : TEXTO_TOQUE_ES);
    attach_jugada(btn_doble_play, is_english ? TEXTO_DOBLE_PLAY_EN     : TEXTO_DOBLE_PLAY_ES);

    if (btn_repetir != NULL) {
        lv_obj_add_event_cb(btn_repetir, repetir_btn_cb, LV_EVENT_CLICKED, NULL);
    }
    if (btn_cancelar != NULL) {
        lv_obj_add_event_cb(btn_cancelar, cancelar_btn_cb, LV_EVENT_CLICKED, NULL);
    }
}
