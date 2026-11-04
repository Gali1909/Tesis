#pragma once

#include "lvgl.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* panel: contenedor de las jugadas de la pantalla activa
 *        (ui_PanelJugadas_es o ui_PanelJugadas_es_EN)
 * add_btn: botón "+" de esa misma pantalla
 *        (ui_Boton_agregar1 o ui_Boton_agregar1_EN)
 * is_english: true si es la pantalla EN, para que los popups
 *        compartidos (agregar/editar jugada, menú Editar/Borrar)
 *        se muestren en inglés.
 */
void jugadas_dynamic_init(lv_obj_t *panel, lv_obj_t *add_btn, bool is_english);

#ifdef __cplusplus
} /*extern "C"*/
#endif