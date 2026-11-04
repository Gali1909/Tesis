SET(SOURCES ui_INICIO.c
    ui_AJUSTES.c
    ui_INICIO_EN_INGLES.c
    ui_Ajustes_en_ingles.c
    ui_Estrategia_defensiva_.c
    ui_Estrategia_defensiva_EN.c
    ui_DISPOSITIVOS_E_IDIOMA.c
    ui_DISPOSITIVOS_E_IDIOMA_EN.c
    ui.c
    ui_comp_hook.c
    ui_helpers.c
    ui_img_estrategia_png.c
    ui_img_pelota_png.c
    ui_img_ajuste_png.c
    ui_img_bluetooth_png.c
    ui_img_1837598647.c
    fonts/ui_font_Font14.c
    fonts/ui_font_Font22.c)

add_library(ui ${SOURCES})
