#include "wifi_manager.h"
#include "uart_bridge.h"   /* debe exponer uart_bridge_send_frame(tipo, payload, len) */
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include <string.h>

static const char *TAG = "WIFI_MGR";

/* Tipos de trama del protocolo WiFi-sobre-UART (ver protocolo_wifi_uart.md) */
#define TIPO_WIFI_SCAN_START 0x10
#define TIPO_WIFI_CONNECT    0x11
#define TIPO_WIFI_DISCONNECT 0x12

#define TIPO_WIFI_AP_FOUND   0x20
#define TIPO_WIFI_SCAN_DONE  0x21
#define TIPO_WIFI_STATUS     0x22

typedef enum {
    C6_ESTADO_DESCONECTADO = 0,
    C6_ESTADO_CONECTANDO,
    C6_ESTADO_CONECTADO,
    C6_ESTADO_ERROR_AUTH,
    C6_ESTADO_ERROR_NO_AP,
    C6_ESTADO_ERROR_TIMEOUT,
} c6_wifi_estado_t;

static bool s_inicializado = false;
static bool s_encendido = false;
static wifi_manager_state_t s_estado = WIFI_MANAGER_STATE_OFF;

static wifi_manager_ap_t s_aps[WIFI_MANAGER_MAX_SCAN_RESULTS];
static size_t s_num_aps = 0;

static char s_ssid_conectado[WIFI_MANAGER_MAX_SSID_LEN] = {0};
static char s_ssid_intentando[WIFI_MANAGER_MAX_SSID_LEN] = {0};

static wifi_manager_scan_cb_t s_scan_cb = NULL;
static wifi_manager_state_cb_t s_state_cb = NULL;

static SemaphoreHandle_t s_lock = NULL;

static void notificar_estado(void)
{
    if (s_state_cb) {
        const char *ssid = NULL;
        if (s_estado == WIFI_MANAGER_STATE_CONNECTED) {
            ssid = s_ssid_conectado;
        } else if (s_estado == WIFI_MANAGER_STATE_CONNECTING) {
            ssid = s_ssid_intentando;
        }
        s_state_cb(s_estado, ssid);
    }
}

esp_err_t wifi_manager_init(void)
{
    if (s_inicializado) {
        return ESP_OK;
    }
    s_lock = xSemaphoreCreateMutex();
    if (!s_lock) {
        return ESP_ERR_NO_MEM;
    }
    s_estado = WIFI_MANAGER_STATE_OFF;
    s_encendido = false;
    s_num_aps = 0;
    s_ssid_conectado[0] = '\0';
    s_ssid_intentando[0] = '\0';
    s_inicializado = true;
    ESP_LOGI(TAG, "wifi_manager listo (modo UART hacia C6 externo)");
    return ESP_OK;
}

bool wifi_manager_is_enabled(void)
{
    return s_encendido;
}

wifi_manager_state_t wifi_manager_get_state(void)
{
    return s_estado;
}

const char *wifi_manager_get_connected_ssid(void)
{
    return (s_estado == WIFI_MANAGER_STATE_CONNECTED) ? s_ssid_conectado : NULL;
}

void wifi_manager_set_state_callback(wifi_manager_state_cb_t cb)
{
    s_state_cb = cb;
}

esp_err_t wifi_manager_start_scan(wifi_manager_scan_cb_t cb)
{
    if (!s_inicializado) {
        ESP_LOGW(TAG, "wifi_manager_start_scan llamado antes de inicializar");
        return ESP_ERR_INVALID_STATE;
    }
    if (!s_encendido) {
        ESP_LOGW(TAG, "wifi_manager_start_scan llamado con el WiFi apagado");
        return ESP_ERR_INVALID_STATE;
    }

    s_scan_cb = cb;

    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_num_aps = 0;
    s_estado = WIFI_MANAGER_STATE_SCANNING;
    xSemaphoreGive(s_lock);
    notificar_estado();

    esp_err_t err = uart_bridge_send_frame(TIPO_WIFI_SCAN_START, NULL, 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "no se pudo enviar WIFI_SCAN_START: %s", esp_err_to_name(err));
        s_estado = WIFI_MANAGER_STATE_ERROR;
        notificar_estado();
        return err;
    }
    ESP_LOGI(TAG, "scan solicitado al C6");
    return ESP_OK;
}

esp_err_t wifi_manager_set_enabled(bool encendido)
{
    if (!s_inicializado) {
        return ESP_ERR_INVALID_STATE;
    }
    if (encendido == s_encendido) {
        return ESP_OK;
    }

    s_encendido = encendido;

    if (!encendido) {
        if (s_estado == WIFI_MANAGER_STATE_CONNECTED || s_estado == WIFI_MANAGER_STATE_CONNECTING) {
            uart_bridge_send_frame(TIPO_WIFI_DISCONNECT, NULL, 0);
        }
        s_estado = WIFI_MANAGER_STATE_OFF;
        s_num_aps = 0;
        s_ssid_conectado[0] = '\0';
        notificar_estado();
        return ESP_OK;
    }

    /* Encender dispara un scan automatico; el switch de la UI ya pasa su
     * propio callback la primera vez que llama a wifi_manager_start_scan,
     * asi que aqui no forzamos ningun cb. */
    s_estado = WIFI_MANAGER_STATE_SCANNING;
    s_num_aps = 0;
    notificar_estado();
    esp_err_t err = uart_bridge_send_frame(TIPO_WIFI_SCAN_START, NULL, 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "no se pudo enviar WIFI_SCAN_START: %s", esp_err_to_name(err));
        s_estado = WIFI_MANAGER_STATE_ERROR;
        notificar_estado();
    }
    return err;
}

esp_err_t wifi_manager_connect(const char *ssid, const char *pass)
{
    if (!s_inicializado || !s_encendido) {
        return ESP_ERR_INVALID_STATE;
    }

    size_t ssid_len = strnlen(ssid, WIFI_MANAGER_MAX_SSID_LEN - 1);
    size_t pass_len = pass ? strnlen(pass, 63) : 0;

    uint8_t payload[1 + (WIFI_MANAGER_MAX_SSID_LEN - 1) + 1 + 63];
    size_t idx = 0;
    payload[idx++] = (uint8_t)ssid_len;
    memcpy(&payload[idx], ssid, ssid_len);
    idx += ssid_len;
    payload[idx++] = (uint8_t)pass_len;
    if (pass_len) {
        memcpy(&payload[idx], pass, pass_len);
        idx += pass_len;
    }

    esp_err_t err = uart_bridge_send_frame(TIPO_WIFI_CONNECT, payload, (uint8_t)idx);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "no se pudo enviar WIFI_CONNECT: %s", esp_err_to_name(err));
        return err;
    }

    memcpy(s_ssid_intentando, ssid, ssid_len);
    s_ssid_intentando[ssid_len] = '\0';
    s_estado = WIFI_MANAGER_STATE_CONNECTING;
    notificar_estado();
    return ESP_OK;
}

esp_err_t wifi_manager_disconnect(void)
{
    if (!s_inicializado) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = uart_bridge_send_frame(TIPO_WIFI_DISCONNECT, NULL, 0);
    if (err == ESP_OK) {
        s_estado = WIFI_MANAGER_STATE_DISCONNECTED;
        s_ssid_conectado[0] = '\0';
        notificar_estado();
    }
    return err;
}

/*---------------------------------------------------------------
 * Manejo de tramas entrantes desde el C6 (llamado por uart_bridge_rx_task)
 *--------------------------------------------------------------*/

static void manejar_ap_found(const uint8_t *payload, uint8_t len)
{
    if (len < 3) {
        ESP_LOGW(TAG, "WIFI_AP_FOUND con payload invalido (%u bytes)", len);
        return;
    }
    int8_t rssi = (int8_t)payload[0];
    uint8_t auth = payload[1];
    uint8_t ssid_len = payload[2];
    if ((3 + ssid_len > len) || (ssid_len > WIFI_MANAGER_MAX_SSID_LEN - 1)) {
        ESP_LOGW(TAG, "WIFI_AP_FOUND con ssid_len invalido (%u)", ssid_len);
        return;
    }

    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (s_num_aps < WIFI_MANAGER_MAX_SCAN_RESULTS) {
        wifi_manager_ap_t *ap = &s_aps[s_num_aps++];
        memcpy(ap->ssid, &payload[3], ssid_len);
        ap->ssid[ssid_len] = '\0';
        ap->rssi = rssi;
        ap->requires_password = (auth != 0); /* 0 = red abierta */
    }
    xSemaphoreGive(s_lock);
}

static void manejar_scan_done(const uint8_t *payload, uint8_t len)
{
    s_estado = WIFI_MANAGER_STATE_DISCONNECTED;
    ESP_LOGI(TAG, "scan terminado, %u redes reportadas por el C6",
             (len >= 1) ? payload[0] : 0);
    notificar_estado();
    if (s_scan_cb) {
        s_scan_cb(s_aps, (int)s_num_aps);
    }
}

static void manejar_status(const uint8_t *payload, uint8_t len)
{
    if (len < 1) {
        return;
    }
    c6_wifi_estado_t estado_c6 = (c6_wifi_estado_t)payload[0];

    switch (estado_c6) {
        case C6_ESTADO_CONECTADO:
            s_estado = WIFI_MANAGER_STATE_CONNECTED;
            strncpy(s_ssid_conectado, s_ssid_intentando, WIFI_MANAGER_MAX_SSID_LEN - 1);
            s_ssid_conectado[WIFI_MANAGER_MAX_SSID_LEN - 1] = '\0';
            if (len >= 5) {
                ESP_LOGI(TAG, "conectado, IP: %u.%u.%u.%u",
                         payload[1], payload[2], payload[3], payload[4]);
            }
            break;
        case C6_ESTADO_CONECTANDO:
            s_estado = WIFI_MANAGER_STATE_CONNECTING;
            break;
        case C6_ESTADO_DESCONECTADO:
            s_estado = WIFI_MANAGER_STATE_DISCONNECTED;
            s_ssid_conectado[0] = '\0';
            break;
        case C6_ESTADO_ERROR_AUTH:
        case C6_ESTADO_ERROR_NO_AP:
        case C6_ESTADO_ERROR_TIMEOUT:
        default:
            ESP_LOGW(TAG, "error de WiFi reportado por el C6 (codigo %d)", estado_c6);
            s_estado = WIFI_MANAGER_STATE_ERROR;
            break;
    }

    notificar_estado();
}

void wifi_manager_handle_uart_frame(uint8_t tipo, const uint8_t *payload, uint8_t len)
{
    if (!s_inicializado) {
        return;
    }
    switch (tipo) {
        case TIPO_WIFI_AP_FOUND:
            manejar_ap_found(payload, len);
            break;
        case TIPO_WIFI_SCAN_DONE:
            manejar_scan_done(payload, len);
            break;
        case TIPO_WIFI_STATUS:
            manejar_status(payload, len);
            break;
        default:
            /* No es una trama de WiFi; el llamador deberia haber filtrado esto */
            break;
    }
}
