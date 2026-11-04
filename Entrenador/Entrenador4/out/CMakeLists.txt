SET(SOURCES ui_Menu_principal.c
    ui_LanzamientosUbi.c
    ui_Grabarjugadas.c
    ui_AUDIOS_GUARDADOS.c
    ui.c
    ui_comp_hook.c
    ui_helpers.c
    ui_img_icono_campo_beisbol_v4_fondo_png.c
    ui_img_icono_pelota_beisbol_fondo_png.c
    ui_img_icono_portapapeles_fondo_png.c
    ui_img_lanzador2_fondo_1f2937_png.c
    ui_img_bateador_fondo_1f2937_v3_png.c
    ui_img_analitica_icono_e6f1fb_png.c
    ui_img_icono_configuracion_v2_png.c)

add_library(ui ${SOURCES})
