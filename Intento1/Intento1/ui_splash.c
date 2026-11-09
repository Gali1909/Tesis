// Pantalla de presentacion (splash) con el logo Diamond Call System.
// No bloquea el loop: usa un lv_timer de una sola ejecucion.

#include "ui.h"
#include "ui_splash.h"

static lv_obj_t * ui_Splash = NULL;

static void splash_timer_cb(lv_timer_t * timer)
{
    LV_UNUSED(timer);
    // Pasa a la pantalla de inicio y libera la pantalla del splash.
    lv_disp_load_scr(ui_INICIO);
    if(ui_Splash) {
        lv_obj_del(ui_Splash);
        ui_Splash = NULL;
    }
}

void ui_splash_show(void)
{
    ui_Splash = lv_obj_create(NULL);
    lv_obj_clear_flag(ui_Splash, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(ui_Splash, lv_color_hex(0x0B2A48), LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(ui_Splash, 255, LV_PART_MAIN | LV_STATE_DEFAULT);

    lv_obj_t * logo = lv_img_create(ui_Splash);
    lv_img_set_src(logo, &ui_img_splash_logo_png);
    lv_obj_set_width(logo, LV_SIZE_CONTENT);
    lv_obj_set_height(logo, LV_SIZE_CONTENT);
    lv_obj_set_align(logo, LV_ALIGN_CENTER);
    lv_obj_clear_flag(logo, LV_OBJ_FLAG_SCROLLABLE);

    lv_disp_load_scr(ui_Splash);

    lv_timer_t * t = lv_timer_create(splash_timer_cb, SPLASH_DURATION_MS, NULL);
    lv_timer_set_repeat_count(t, 1);
}
