#ifndef UI_SPLASH_H
#define UI_SPLASH_H

#ifdef __cplusplus
extern "C" {
#endif

#include "lvgl.h"

// Tiempo que se muestra el logo antes del menu principal (5 minutos).
#define SPLASH_DURATION_MS (5UL * 60UL * 1000UL)

LV_IMAGE_DECLARE(ui_img_splash_logo_png);    // Diamond Call System logo (764x600)

// Muestra el logo y, pasado SPLASH_DURATION_MS, carga ui_Menu_principal.
// Llamar con el lock de LVGL tomado, justo despues de ui_init().
void ui_splash_show(void);

#ifdef __cplusplus
} /*extern "C"*/
#endif

#endif
