/*
 * wifi_bridge_c6.c — modulo NUEVO para el proyecto c6_espnow_bridge (el firmware
 * del modulo Wireless C6 externo).
 *
 * Escucha los comandos WIFI_SCAN_START/WIFI_CONNECT/WIFI_DISCONNECT que llegan
 * por UART desde el P4 (ver protocolo_wifi_uart.md) y responde con
 * WIFI_AP_FOUND / WIFI_SCAN_DONE / WIFI_STATUS usando la MISMA funcion de envio
 * de tramas que ya usan para contestar "ACK_C6" al P4.
 *
 * OJO: esto es un ESQUELETO. Antes de compilar:
 *   1) Renombra c6_uart_enviar_trama(...) por la funcion real que ya tienes en tu
 *      main.c del C6 para mandar bytes de vuelta al P4.
 *   2) Confirma que tu parser de tramas del C6 llame a
 *      wifi_bridge_c6_handle_frame(tipo, payload, len) cuando el tipo caiga en
 *      0x10-0x1F, igual que ya hace para los tipos existentes.
 *   3) Revisa la coexistencia STA+ESPNOW en el mismo radio (nota al final de
 *      protocolo_wifi_uart.md) antes de dar esto por terminado.
 */

#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include <string.h>

static const char *TAG = "WIFI_BRIDGE_C6";

/* Tipos de trama (deben coincidir exactamente con wifi_manager.c del P4) */
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

/* ---- PLACEHOLDER: reemplazar por la funcion real de envio de tramas ---- */
extern esp_err_t c6_uart_enviar_trama(uint8_t tipo, const uint8_t *payload, uint8_t len);
/* ------------------------------------------------------------------------ */

static esp_netif_t *s_netif_sta = NULL;

static void enviar_status(c6_wifi_estado_t estado, const uint8_t ip[4])
{
    uint8_t payload[5];
    payload[0] = (uint8_t)estado;
    uint8_t len = 1;
    if (estado == C6_ESTADO_CONECTADO && ip) {
        memcpy(&payload[1], ip, 4);
        len = 5;
    }
    c6_uart_enviar_trama(TIPO_WIFI_STATUS, payload, len);
}

static void on_wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_SCAN_DONE) {
        uint16_t num_aps = 0;
        esp_wifi_scan_get_ap_num(&num_aps);
        if (num_aps == 0) {
            uint8_t count = 0;
            c6_uart_enviar_trama(TIPO_WIFI_SCAN_DONE, &count, 1);
            return;
        }

        wifi_ap_record_t *registros = calloc(num_aps, sizeof(wifi_ap_record_t));
        if (!registros) {
            ESP_LOGE(TAG, "sin memoria para %u APs", num_aps);
            uint8_t count = 0;
            c6_uart_enviar_trama(TIPO_WIFI_SCAN_DONE, &count, 1);
            return;
        }

        esp_wifi_scan_get_ap_records(&num_aps, registros);

        uint8_t enviados = 0;
        for (int i = 0; i < num_aps; i++) {
            uint8_t ssid_len = (uint8_t)strnlen((char *)registros[i].ssid, 32);
            if (ssid_len == 0) {
                continue; /* red oculta, se omite */
            }
            uint8_t payload[2 + 32];
            payload[0] = (uint8_t)registros[i].rssi;
            payload[1] = (uint8_t)registros[i].authmode;
            payload[2] = ssid_len;
            memcpy(&payload[3], registros[i].ssid, ssid_len);
            c6_uart_enviar_trama(TIPO_WIFI_AP_FOUND, payload, 3 + ssid_len);
            enviados++;
        }
        free(registros);

        c6_uart_enviar_trama(TIPO_WIFI_SCAN_DONE, &enviados, 1);
        ESP_LOGI(TAG, "scan terminado, %u redes enviadas al P4", enviados);

    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *evt = (wifi_event_sta_disconnected_t *)data;
        c6_wifi_estado_t estado = C6_ESTADO_DESCONECTADO;
        if (evt->reason == WIFI_REASON_AUTH_FAIL ||
            evt->reason == WIFI_REASON_AUTH_EXPIRE) {
            estado = C6_ESTADO_ERROR_AUTH;
        } else if (evt->reason == WIFI_REASON_NO_AP_FOUND) {
            estado = C6_ESTADO_ERROR_NO_AP;
        }
        ESP_LOGW(TAG, "STA desconectado, razon=%d", evt->reason);
        enviar_status(estado, NULL);
    }
}

static void on_ip_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *evt = (ip_event_got_ip_t *)data;
        uint8_t ip[4] = {
            esp_ip4_addr_get_byte(&evt->ip_info.ip, 0),
            esp_ip4_addr_get_byte(&evt->ip_info.ip, 1),
            esp_ip4_addr_get_byte(&evt->ip_info.ip, 2),
            esp_ip4_addr_get_byte(&evt->ip_info.ip, 3),
        };
        ESP_LOGI(TAG, "IP obtenida: %d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
        enviar_status(C6_ESTADO_CONECTADO, ip);
    }
}

/**
 * @brief Llamar una sola vez al iniciar el C6 (ademas de la inicializacion de
 *        WiFi/ESP-NOW que ya tienes), para registrar los handlers de arriba.
 *        Asume que esp_netif_init(), esp_event_loop_create_default() y
 *        esp_wifi_init()/esp_wifi_start() ya corrieron (los mismos que usa tu
 *        ESP-NOW actual).
 */
esp_err_t wifi_bridge_c6_init(void)
{
    s_netif_sta = esp_netif_create_default_wifi_sta();
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &on_wifi_event, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &on_ip_event, NULL));
    return ESP_OK;
}

/**
 * @brief Debe ser llamado por el parser de tramas del C6 cuando llega un tipo
 *        en el rango 0x10-0x1F.
 */
void wifi_bridge_c6_handle_frame(uint8_t tipo, const uint8_t *payload, uint8_t len)
{
    switch (tipo) {
        case TIPO_WIFI_SCAN_START: {
            wifi_scan_config_t cfg = {0};
            esp_err_t err = esp_wifi_scan_start(&cfg, false /* no bloqueante */);
            if (err != ESP_OK) {
                ESP_LOGE(TAG, "esp_wifi_scan_start fallo: %s", esp_err_to_name(err));
                uint8_t count = 0;
                c6_uart_enviar_trama(TIPO_WIFI_SCAN_DONE, &count, 1);
            }
            break;
        }
        case TIPO_WIFI_CONNECT: {
            if (len < 2) {
                ESP_LOGW(TAG, "WIFI_CONNECT con payload invalido");
                break;
            }
            uint8_t ssid_len = payload[0];
            if (1 + ssid_len + 1 > len || ssid_len > 32) {
                ESP_LOGW(TAG, "WIFI_CONNECT: ssid_len invalido");
                break;
            }
            uint8_t pass_len = payload[1 + ssid_len];
            if (1 + ssid_len + 1 + pass_len > len || pass_len > 63) {
                ESP_LOGW(TAG, "WIFI_CONNECT: pass_len invalido");
                break;
            }

            wifi_config_t wifi_cfg = {0};
            memcpy(wifi_cfg.sta.ssid, &payload[1], ssid_len);
            if (pass_len) {
                memcpy(wifi_cfg.sta.password, &payload[2 + ssid_len], pass_len);
            }

            esp_wifi_set_config(WIFI_IF_STA, &wifi_cfg);
            esp_err_t err = esp_wifi_connect();
            if (err != ESP_OK) {
                ESP_LOGE(TAG, "esp_wifi_connect fallo: %s", esp_err_to_name(err));
                enviar_status(C6_ESTADO_ERROR_TIMEOUT, NULL);
            } else {
                enviar_status(C6_ESTADO_CONECTANDO, NULL);
            }
            break;
        }
        case TIPO_WIFI_DISCONNECT:
            esp_wifi_disconnect();
            enviar_status(C6_ESTADO_DESCONECTADO, NULL);
            break;
        default:
            break;
    }
}
