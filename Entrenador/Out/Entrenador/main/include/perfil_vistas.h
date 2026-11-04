// perfil_vistas.h
// Vistas de estadisticas del perfil del lanzador (Ultima actuacion, Ultimas
// 5/10/15, Temporada y De por vida). Trama 0x16, una por vista.
//
// Payload de la trama 0x16 (enteros de 16 bits little-endian):
//   [0]    vista: 0 ultima, 1 ultimas 5, 2 ultimas 10, 3 ultimas 15,
//                 4 temporada, 5 de por vida
//   [1]    salidas contadas (0 si la vista no es por salidas)
//   [2..3] anio de la temporada (0 si no aplica)
//   [4]    n = cantidad de campos (0..14)
//   [5..]  n x { id del campo (1 byte), valor (uint16) }
// Ids: 0 PCL/ERA(x100) 1 WHIP(x100) 2 K/9(x100) 3 IL/IP(x10) 4 H 5 CL 6 SO
//      7 BB 8 PIT 9 G/W 10 P/L 11 AP 12 SV 13 JL
#ifndef PERFIL_VISTAS_H
#define PERFIL_VISTAS_H

#include <stdint.h>

/* Tarea UART: solo copia datos (no toca LVGL). */
void perfil_vistas_on_frame(const uint8_t *payload, uint8_t len);

/* Tarea UART: trama 0x17 = lista completa de lanzamientos del pitcher.
 * Payload: [n] + n x { slot, vmin, vmax }   (n <= 14) */
void perfil_tipos_on_frame(const uint8_t *payload, uint8_t len);

/* Tarea UART: olvida todas las vistas (al quitar el perfil). */
void perfil_vistas_borrar(void);

/* Tarea LVGL: muestra la franja de estadisticas y la fila de botones de
 * vista (ocultando la cuadricula y las 3 pestanas originales). */
void perfil_vistas_ui_mostrar(void);

/* Tarea LVGL: oculta lo anterior (pantalla sin lanzador seleccionado). */
void perfil_vistas_ui_ocultar(void);

/* Tarea LVGL: llamar periodicamente; refresca si llegaron datos nuevos. */
void perfil_vistas_ui_tick(void);

#endif