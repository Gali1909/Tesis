#ifndef AJUSTES_DYNAMIC_H
#define AJUSTES_DYNAMIC_H

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

// Se llama cuando el usuario mueve el slider de brillo (evento
// "Value Changed" sobre ui_SliderBRILLO, registrado desde SquareLine).
void slider_brillo_event_cb(lv_event_t *e);

#ifdef __cplusplus
}
#endif

#endif // AJUSTES_DYNAMIC_H
