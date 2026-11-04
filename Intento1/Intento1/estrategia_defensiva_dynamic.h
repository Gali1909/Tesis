#ifndef ESTRATEGIA_DEFENSIVA_DYNAMIC_H
#define ESTRATEGIA_DEFENSIVA_DYNAMIC_H

#include "lvgl.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Engancha los 6 botones de jugada fija de ui_Estrategia_defensiva_.c /
 * _EN.c (Viraje a primera, Viraje a segunda, No doble, Robo de base,
 * Toque de bola, Doble play) y los de Repetir/Cancelar jugada, para que
 * manden la jugada correspondiente via enviarJugadaTexto() (Intento1.ino).
 * Se llama una vez desde cada screen_init() (ES: is_english=false, EN:
 * is_english=true), cada vez que esa pantalla se (re)construye. */
void estrategia_defensiva_dynamic_init(lv_obj_t *btn_primera, lv_obj_t *btn_segunda,
                                        lv_obj_t *btn_no_doble, lv_obj_t *btn_robo,
                                        lv_obj_t *btn_toque, lv_obj_t *btn_doble_play,
                                        lv_obj_t *btn_repetir, lv_obj_t *btn_cancelar,
                                        bool is_english);

#ifdef __cplusplus
}
#endif

#endif
