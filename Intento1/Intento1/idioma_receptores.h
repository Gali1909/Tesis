#ifndef IDIOMA_RECEPTORES_H
#define IDIOMA_RECEPTORES_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NUM_RECEPTORES 4

typedef enum {
    IDIOMA_RECEPTOR_ES = 0,   // valor que se envia al receptor: 0 = espanol
    IDIOMA_RECEPTOR_EN = 1    // valor que se envia al receptor: 1 = ingles
} idioma_receptor_t;

// Llamar al final de ui_DISPOSITIVOS_E_IDIOMA_screen_init():
// engancha los botones y repinta el estado guardado.
void idioma_receptores_init(void);

// Igual, pero para la pantalla en ingles: llamar al final de
// ui_DISPOSITIVOS_EIDIOMA_EN_screen_init().
void idioma_receptores_init_en(void);

// Cambia el idioma de un receptor (0..NUM_RECEPTORES-1), repinta y envia por ESP-NOW.
void idioma_receptor_set(int receptor, idioma_receptor_t idioma);

idioma_receptor_t idioma_receptor_get(int receptor);

// Longitud maxima del nombre (sin contar el '\0').
#define NOMBRE_RECEPTOR_MAX 16

// Devuelve el nombre actual del receptor (siempre un string valido).
const char *idioma_receptor_nombre(int receptor);

// Cambia el nombre, lo guarda en memoria no volatil y repinta la etiqueta.
void idioma_receptor_set_nombre(int receptor, const char *nombre);

// Llamar cada vez que llega un latido del receptor de esa fila (la llama
// Intento1.ino al recibir la trama UART_MSG_RECEPTOR_ESTADO del C6). Pone su
// circulo en verde; si dejan de llegar latidos el circulo pasa a rojo solo.
void idioma_receptor_latido(uint8_t fila);

#ifdef __cplusplus
}
#endif

#endif
