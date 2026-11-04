SET(SOURCES ui_INICIO.c
    ui_SELECCION_DE_LANZMIENTO.c
    ui_UBICACION_DEL_LANZAMIENTO.c
    ui_INICIO_EN_INGLES.c
    ui_Ajustes_en_ingles.c
    ui_SELECCION_DE_LANZMIENTO_INGLES.c
    ui_UBICACION_DEL_LANZAMIENTO_INGLES.c
    ui_Estrategia_defensiva_.c
    ui.c
    ui_comp_hook.c
    ui_helpers.c
    ui_img_estrategia_png.c
    ui_img_pelota_png.c
    ui_img_ajuste_png.c
    ui_img_recta_png.c
    ui_img_dos_costuras_png.c
    ui_img_cutter_png.c
    ui_img_curva_png.c
    ui_img_slider_png.c
    ui_img_splitter_png.c
    ui_img_tenedor_png.c
    ui_img_cambio_png.c
    ui_img_screwball_png.c
    ui_img_circle_change_png.c
    ui_img_home_png.c
    ui_img_bluetooth_png.c
    ui_img_1837598647.c
    fonts/ui_font_Font14.c
    fonts/ui_font_Font22.c)

add_library(ui ${SOURCES})
