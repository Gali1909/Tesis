// Modulo propio (no generado por SquareLine Studio)
// Guarda el idioma en el que el DISPOSITIVO RECEPTOR reproduce las
// jugadas/lanzamientos (campo "idioma" de pitch_message_t).
// Es independiente del idioma de la pantalla (ui_AJUSTES / ui_Ajustes_en_ingles):
// cambiar el idioma de la pantalla NO cambia este valor.

#ifndef UI_IDIOMA_DISPOSITIVO_H
#define UI_IDIOMA_DISPOSITIVO_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    IDIOMA_DISPOSITIVO_ES = 0,
    IDIOMA_DISPOSITIVO_EN = 1
} idioma_dispositivo_t;

// Cambia el idioma guardado del dispositivo (lo hacen los botones
// ES/ESPAÑOL/SPANISH e INGLES/ENGLISH de la pantalla DISPOSITIVOS E IDIOMA)
void idioma_dispositivo_set(idioma_dispositivo_t idioma);

// Devuelve el idioma actualmente guardado del dispositivo.
// Usar este valor (0 = ES, 1 = EN) como el byte "idioma" al construir
// pitch_message_t / la trama de enviarLanzamiento() / enviarJugadaTexto()
// en Intento1.ino, en vez de un valor fijo o del idioma de pantalla.
idioma_dispositivo_t idioma_dispositivo_get(void);

#ifdef __cplusplus
} /*extern "C"*/
#endif

#endif
