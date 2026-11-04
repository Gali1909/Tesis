#pragma once

#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Inicialización del socket de comunicación */
esp_err_t esp_now_comm_init(void);

/* Envío genérico */
esp_err_t send_packet(const uint8_t *data, size_t len);

/* Funciones de alto nivel requeridas por la interfaz */
esp_err_t esp_now_send_jugada_texto(const char *texto);
esp_err_t esp_now_send_pitch_signal(int pitch_type, int zone);
esp_err_t esp_now_send_cancelar(void);
esp_err_t esp_now_send_cancelar_jugada(void);

/* Idioma de UN receptor: receptor 0..2 (Receptor 1..3), idioma 0=ES, 1=EN.
 * Ademas de cambiarlo en el receptor, avisa a la otra pantalla (S3). */
esp_err_t esp_now_send_idioma_receptor(uint8_t receptor, uint8_t idioma);

/* Solo avisa a la otra pantalla del idioma de un receptor (receptor 0..2 o
 * 0xFF = todos), sin tocar los receptores. */
esp_err_t esp_now_send_idioma_sync(uint8_t receptor, uint8_t idioma);

/* Callback que se llama cuando la OTRA pantalla cambio el idioma de un
 * dispositivo. receptor: 0..2 o 0xFF (todos). idioma: 0=ES, 1=EN.
 * IMPORTANTE: se invoca desde la tarea UART, no desde la de LVGL. Quien lo
 * registre debe tomar lvgl_port_lock(0) antes de tocar la UI, y NO debe
 * llamar a esp_now_send_idioma_receptor() (el cambio ya esta aplicado en el
 * receptor; solo hay que reflejarlo en la pantalla). */
typedef void (*idioma_remoto_cb_t)(uint8_t receptor, uint8_t idioma);
void esp_now_comm_set_idioma_remoto_cb(idioma_remoto_cb_t cb);

#ifdef __cplusplus
}
#endif
