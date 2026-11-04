// uart_bridge.h
#ifndef UART_BRIDGE_H
#define UART_BRIDGE_H

#include "esp_err.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* Inicializa el periferico UART usado para hablar con el modulo C6 puente. */
esp_err_t uart_bridge_init(void);

/* Envia una trama completa (start + tipo + len + payload + checksum + end)
 * ya armada por la capa superior (esp_now_comm.c). */
esp_err_t uart_bridge_send_frame(uint8_t tipo, const uint8_t *payload, uint8_t len);

/* Tipos de trama que atiende el C6 puente para WiFi/Bluetooth (deben
 * coincidir exactamente con UART_MSG_WIFI / UART_MSG_BLUETOOTH en el
 * main.c del modulo C6). */
#define UART_MSG_WIFI       0x05
#define UART_MSG_BLUETOOTH  0x06

/* Sincronizacion de idioma ENTRE PANTALLAS (P4 <-> S3). El C6 NO debe
 * reenviar esta trama a los receptores: solo al peer de la otra pantalla.
 * payload: [receptor 0..2 | 0xFF = todos][idioma 0=ES | 1=EN]
 * Debe coincidir con el valor usado en el main.c del C6 y en Intento1. */
#define UART_MSG_IDIOMA_SYNC 0x07

/* Perfil del lanzador, enviado por la app (BLE) y reenviado por el C6.
 * 0x14 = quitar perfil (payload vacio), 0x15 = datos del perfil. Deben
 * coincidir con APP_T_QUITAR_PERFIL / APP_T_PERFIL_DATOS en el main.c del C6. */
#define UART_MSG_QUITAR_PERFIL 0x14
#define UART_MSG_PERFIL_DATOS  0x15
#define UART_MSG_PERFIL_TIPOS  0x17   /* lista completa de lanzamientos */
#define UART_MSG_PERFIL_VISTA  0x16   /* vista de estadisticas del perfil */

/* Callback para tramas completas y validas que llegan del C6.
 * Se invoca desde la tarea de recepcion UART (NO desde la tarea de LVGL). */
typedef void (*uart_bridge_frame_cb_t)(uint8_t tipo, const uint8_t *payload, uint8_t len);
void uart_bridge_set_frame_callback(uart_bridge_frame_cb_t cb);

/* Callback adicional solo para las tramas 0x14 y 0x15 (se invoca ademas del
 * callback general, sin reemplazarlo). */
void uart_bridge_set_perfil_callback(uart_bridge_frame_cb_t cb);

/* Pide al C6 encender (true) o apagar (false) el SoftAP. Llamar desde donde
 * sea que la pantalla dispare la accion (boton, gesto, etc.). */
esp_err_t uart_bridge_send_wifi(bool encender);

/* Pide al C6 encender (true) o apagar (false) el Bluetooth (BLE). */
esp_err_t uart_bridge_send_bluetooth(bool encender);

#endif
