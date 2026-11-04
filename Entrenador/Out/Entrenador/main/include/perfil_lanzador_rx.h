// perfil_lanzador_rx.h
// Recibe el perfil del lanzador (tramas 0x15 / 0x14 que reenvia el C6) y lo
// muestra en la pantalla "Perfil de lanzadores".
#ifndef PERFIL_LANZADOR_RX_H
#define PERFIL_LANZADOR_RX_H

#include <stdint.h>

/* Llamar UNA vez, despues de ui_init(), en el mismo punto donde llamas a
 * lanzamientos_dynamic_init() (contexto de LVGL). Registra el callback de
 * uart_bridge y crea un lv_timer que aplica los cambios en la tarea de LVGL. */
void perfil_lanzador_rx_init(void);

/* Callback de uart_bridge (tarea UART). Solo copia datos; no toca LVGL. */
void perfil_lanzador_rx_on_frame(uint8_t tipo, const uint8_t *payload, uint8_t len);

#endif
