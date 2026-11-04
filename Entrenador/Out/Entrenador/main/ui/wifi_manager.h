#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include "esp_err.h"
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Nombres y firmas tomados tal cual de lo que ya usan ui_wifi_popup.c y
 * ui_events.c (deducidos de los errores de compilacion) — NO renombrar sin
 * actualizar tambien esos archivos. */

#define WIFI_MANAGER_MAX_SSID_LEN     33  /* 32 + terminador nulo */
#define WIFI_MANAGER_MAX_SCAN_RESULTS 20

typedef struct {
    char ssid[WIFI_MANAGER_MAX_SSID_LEN];
    int8_t rssi;
    bool requires_password;
} wifi_manager_ap_t;

typedef enum {
    WIFI_MANAGER_STATE_OFF = 0,
    WIFI_MANAGER_STATE_DISCONNECTED,
    WIFI_MANAGER_STATE_SCANNING,
    WIFI_MANAGER_STATE_CONNECTING,
    WIFI_MANAGER_STATE_CONNECTED,
    WIFI_MANAGER_STATE_ERROR,
} wifi_manager_state_t;

typedef void (*wifi_manager_scan_cb_t)(const wifi_manager_ap_t *redes, int cantidad);
typedef void (*wifi_manager_state_cb_t)(wifi_manager_state_t estado, const char *ssid);

/**
 * @brief Inicializa el gestor de WiFi. No toca hardware de radio directamente:
 *        toda la comunicacion real pasa por el C6 externo via UART.
 */
esp_err_t wifi_manager_init(void);

/**
 * @brief Enciende/apaga el WiFi desde el switch de Ajustes.
 */
esp_err_t wifi_manager_set_enabled(bool encendido);
bool wifi_manager_is_enabled(void);

/**
 * @brief Pide al C6 escanear redes. cb se llama una vez cuando el escaneo
 *        termina, con la lista de redes encontradas (puede ser NULL si solo
 *        quieres consultar el estado por wifi_manager_get_state()).
 */
esp_err_t wifi_manager_start_scan(wifi_manager_scan_cb_t cb);

/**
 * @brief Registra un callback para enterarse de cambios de estado
 *        (conectando/conectado/error/etc). Solo puede haber uno activo a la vez.
 */
void wifi_manager_set_state_callback(wifi_manager_state_cb_t cb);

esp_err_t wifi_manager_connect(const char *ssid, const char *pass);
esp_err_t wifi_manager_disconnect(void);

/**
 * @brief SSID de la red actualmente conectada, o NULL si no hay conexion activa.
 */
const char *wifi_manager_get_connected_ssid(void);

wifi_manager_state_t wifi_manager_get_state(void);

/**
 * @brief Debe ser llamado desde uart_bridge_rx_task cuando llega una trama con
 *        tipo en el rango 0x20-0x2F (ver protocolo_wifi_uart.md).
 */
void wifi_manager_handle_uart_frame(uint8_t tipo, const uint8_t *payload, uint8_t len);

#ifdef __cplusplus
}
#endif

#endif /* WIFI_MANAGER_H */
