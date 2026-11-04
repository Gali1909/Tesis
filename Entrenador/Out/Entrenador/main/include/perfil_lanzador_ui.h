// perfil_lanzador_ui.h
// Llena / limpia la pantalla "Perfil de lanzadores" (ES y EN) con los datos
// de un lanzador. NO toca UART ni WiFi: solo widgets LVGL.
//
// IMPORTANTE: todas las funciones deben llamarse desde la tarea de LVGL (o con
// el lock de LVGL tomado). Si los datos llegan por el callback de uart_bridge
// (tarea UART), hay que copiarlos y aplicarlos con el mecanismo de lock que ya
// usas para el resto de la UI.
#ifndef PERFIL_LANZADOR_UI_H
#define PERFIL_LANZADOR_UI_H

#include <stdint.h>
#include <stdbool.h>
#include "lvgl.h"

#define PERFIL_MAX_LANZ 5   /* filas de lanzamientos que tiene la pantalla */

typedef struct {
    uint8_t tipo;   /* slot 0..13 del catalogo de la app */
    uint8_t vmin;   /* mph */
    uint8_t vmax;   /* mph */
} perfil_lanz_t;

typedef struct {
    uint8_t  id;
    char     nombre[32];      /* UTF-8, terminado en '\0' */
    uint8_t  numero;
    uint8_t  mano;            /* 0 = derecho (RHP), 1 = zurdo (LHP) */
    uint8_t  edad;            /* 0 = no se muestra */
    uint16_t g, p, j, a, sv, so, bb;
    uint16_t pcl_x100;        /* PCL (ERA) * 100  -> 275 = 2.75 */
    uint16_t whip_x100;       /* WHIP * 100       -> 502 = 5.02 */
    uint16_t il_x10;          /* IL * 10          -> 2001 = 200.1 */
    uint8_t  n_lanz;          /* cuantas filas de lanzamientos vienen (0..5) */
    perfil_lanz_t lanz[PERFIL_MAX_LANZ];
} perfil_lanzador_t;

/* Deja la pantalla sin lanzador seleccionado: oculta foto, datos, numero,
 * pestanas y estadisticas, y muestra "Selecciona un lanzador". */
void perfil_lanzador_ui_reset(void);

/* Muestra el perfil completo del lanzador. */
void perfil_lanzador_ui_mostrar(const perfil_lanzador_t *p);

/* Lista de la izquierda: muestra al lanzador recibido en el primer boton y
 * oculta el resto. hay=false oculta los botones de la lista. */
void perfil_lanzador_ui_lista(bool hay, const char *nombre);

/* Registra el callback de clic del primer boton de la lista (ES y EN).
 * Se puede llamar cada vez que se entra a la pantalla (no duplica). */
void perfil_lanzador_ui_set_click_cb(lv_event_cb_t cb);

#endif
