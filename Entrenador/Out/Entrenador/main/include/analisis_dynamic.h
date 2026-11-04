#ifndef ANALISIS_DYNAMIC_H
#define ANALISIS_DYNAMIC_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Llamar DESPUÉS de CADA ui_Analisis_del_juego_screen_init(): la pantalla se destruye
 * al salir y se vuelve a crear al entrar, y los eventos hay que engancharlos otra vez.
 * El estado del juego (outs, bases, marcador) se conserva entre entradas.
 * Engancha los eventos de las zonas de strike y de bola y deja los
 * contadores de strikes y bolas en gris (o con el conteo actual).
 */
void analisis_dynamic_init(void);

/** Opcional: llamar al salir de la pantalla (cierra el popup si estaba abierto). */
void analisis_dynamic_deinit(void);

/** Pone el contador de strikes en n (0..2) y lo refleja en pantalla. */
void analisis_set_strikes(int n);
int  analisis_get_strikes(void);

/** Pone el contador de bolas en n (0..3) y lo refleja en pantalla. */
void analisis_set_bolas(int n);
int  analisis_get_bolas(void);

/** Outs: 0..2 en pantalla; el 3er out reinicia a 0 (fin de media entrada). */
void analisis_set_outs(int n);
int  analisis_get_outs(void);
void analisis_out_sumar(void);

/** Bases: base = 1, 2 o 3. Ocupada = naranja, vacía = color original. */
void analisis_base_set(int base, bool ocupada);
bool analisis_base_ocupada(int base);
void analisis_bases_limpiar(void);
/** Base por bolas: bateador a 1ra y avanzan solo los corredores forzados. */
void analisis_base_por_bolas(void);

/** Suma 1 carrera al equipo que batea (panel Carreras_EQ1 y linescore de la entrada). */
void analisis_carrera_sumar(void);
int  analisis_get_carreras_eq1(void);

/** Cierra la media entrada (se llama sola al 3er out): fija las carreras en el
 *  linescore, cambia de equipo al bate / entrada y limpia outs, conteo y bases. */
void analisis_media_entrada_terminar(void);
int  analisis_get_entrada(void);
bool analisis_bateando_eq1(void);

/** Hit (sencillo): bateador a 1ra, avanzan forzados, suma hit al equipo que batea. */
void analisis_hit(void);
int  analisis_get_hits_eq1(void);
int  analisis_get_hits_eq2(void);

/** Out del bateador (Button_Accion2): suma un out y reinicia el conteo. */
void analisis_out_bateador(void);

/** Doble out (Button_Accion3). Solo si hay corredor en base; devuelve false si no hizo nada. */
bool analisis_doble_play(void);

/** Doble (Button_Accion5): bateador a 2da, anotan los de 2da y 3ra, el de 1ra pasa a 3ra. */
void analisis_doble(void);

/** Triple (Button_Accion6): bateador a 3ra y anotan todos los corredores en base. */
void analisis_triple(void);

/** Error (Button_Accion9): abre un popup para ubicar al bateador y los corredores; al
 *  aceptar se suma el error al equipo que defiende (Errores_EQ1 / Errores_EQ2). */
void analisis_error_defensivo(void);
int  analisis_get_errores_eq1(void);
int  analisis_get_errores_eq2(void);

/** Boleto intencional (Button_Accion8) y pelotazo (Button_Accion10): bateador a 1ra,
 *  avanzan solo los forzados; no suma hit. */
void analisis_base_gratis(void);

/** Foul (Button_Accion1): strike si hay menos de 2, y se agrega a la secuencia. */
void analisis_foul(void);

/** Base robada (Button_Accion12): el corredor avanza una base (de 3ra anota). Con 2 o mas
 *  corredores pregunta cual. El boton solo esta habilitado si hay corredores en base. */
void analisis_base_robada(void);

/** Borrar la ultima jugada (Button_Accion11): restaura el estado anterior completo
 *  (conteo, outs, bases, marcador, hits, errores, entrada). Guarda hasta 40 jugadas. */
void analisis_deshacer(void);

/** Jonron (Button_Accion7): anotan los corredores en base y el bateador; bases limpias. */
void analisis_homerun(void);

/** Reinicia el conteo (0 bolas, 0 strikes): nuevo bateador. */
void analisis_conteo_reiniciar(void);

#ifdef __cplusplus
}
#endif

#endif /* ANALISIS_DYNAMIC_H */
