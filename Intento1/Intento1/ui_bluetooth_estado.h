// Estado del Bluetooth de la pantalla, independiente de las pantallas de UI.
// Vive fuera de LVGL, asi que sobrevive cuando ui_AJUSTES <-> ui_Ajustes_en_ingles
// se destruyen y se reconstruyen al cambiar el idioma de la pantalla.

#ifndef UI_BLUETOOTH_ESTADO_H
#define UI_BLUETOOTH_ESTADO_H

#include <stdbool.h>
#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

// true = Bluetooth encendido.
bool bluetooth_pantalla_get(void);

// Guarda el estado y, si cambio, manda el comando al modulo C6.
void bluetooth_pantalla_set(bool encendido);

// Llamar al final de screen_init() de cada pantalla de Ajustes, pasando el
// switch de Bluetooth: lo deja en la posicion guardada y le engancha el evento.
void bluetooth_pantalla_attach(lv_obj_t * sw);

#ifdef __cplusplus
} /*extern "C"*/
#endif

#endif
