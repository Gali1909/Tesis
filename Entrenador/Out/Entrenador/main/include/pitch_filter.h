// pitch_filter.h
// Restringe los botones de tipo de lanzamiento segun el perfil del lanzador
// enviado desde la app (tramas 0x13 / 0x14 que llegan por el C6).
#ifndef PITCH_FILTER_H
#define PITCH_FILTER_H

#include <stdint.h>
#include <stdbool.h>

#define UART_MSG_PERFIL_LANZADOR  0x13  /* payload: N bytes, cada uno = slot del catalogo de la app (0..13) */
#define UART_MSG_QUITAR_PERFIL    0x14  /* payload: vacio -> habilita los 14 tipos */

/* Crea el timer de LVGL que aplica el filtro. Llamar UNA vez, despues de
 * lanzamientos_dynamic_init() y lanzamientos_dynamic_en_init(). */
void pitch_filter_init(void);

/* Llamar al inicio del callback de uart_bridge_set_frame_callback().
 * Devuelve true si la trama era 0x13/0x14 (ya atendida). Segura desde la
 * tarea UART: solo guarda la mascara; LVGL la aplica en su propio hilo. */
bool pitch_filter_on_frame(uint8_t tipo, const uint8_t *payload, uint8_t len);

#endif
