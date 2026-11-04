SET(SOURCES ui_AJUSTES.c
    ui_Ajustes_en_ingles.c
    ui_UBICACION_DEL_LANZAMIENTO_INGLES.c
    ui_UBICACION_DEL_LANZAMIENTO_ZUR.c
    ui_UBICACION_DEL_LANZAMIENTO_ZUR_EN.c
    ui_UBICACION_DEL_LANZAMIENTO.c
    ui_UBICACION_DEL_LANZAMIENTO1.c
    ui.c
    ui_comp_hook.c
    ui_helpers.c
    ui_img_bluetooth_png.c
    ui_img_1837598647.c
    ui_img_home_png.c
    fonts/ui_font_Font14.c
    fonts/ui_font_Font22.c)

add_library(ui ${SOURCES})
