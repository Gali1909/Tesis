#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_now.h"
#include "esp_netif.h"
#include "driver/uart.h"
#include "driver/gpio.h"

static const char *TAG = "BRIDGE_C6_PANTALLA35";

// Pines UART asignados en el ESP32-C6
// Segun el datasheet oficial del modulo Wireless Module for Crowpanel
// Advanced Series - ESP32-C6 (Elecrow), el conector del socket expone
// U0TXD/U0RXD (UART0 por defecto del chip), que en el ESP32-C6 son fijos:
// U0TXD = GPIO16, U0RXD = GPIO17.
#define UART_PORT_NUM      UART_NUM_0
#define UART_TX_PIN        GPIO_NUM_16
#define UART_RX_PIN        GPIO_NUM_17
#define UART_BAUD_RATE     115200
#define UART_BUF_SIZE      512

// Como UART0 es tambien la consola por defecto de ESP-IDF, el log de este
// firmware debe salir por el USB nativo del modulo (USB Serial/JTAG,
// GPIO12/13) en vez de por UART0. Configurar esto en menuconfig:
// Component config -> ESP System Settings -> Channel for console output
// -> USB Serial/JTAG Controller

#define WIFI_CHANNEL       1

// MAC propia del modulo (se llena en init_wifi_espnow, se reimprime cada
// pocos segundos para que sea facil de ver/copiar en el monitor serie)
static uint8_t s_propia_mac[6];

// Protocolo de trama (mismo framing validado en Entrenador):
// [FRAME_START][tipo][len][payload...][checksum][FRAME_END]
// checksum = tipo ^ len ^ payload[0] ^ payload[1] ^ ... ^ payload[len-1]
#define FRAME_START   0xAA
#define FRAME_END     0x55
#define MAX_PAYLOAD   64

// Estructura de 3 bytes (mismo formato usado en Entrenador)
typedef struct __attribute__((packed)) {
    uint8_t idioma;
    uint8_t tipoLanzamiento;
    uint8_t ubicacion;
} pitch_message_t;

// MACs de los 3 receptores ESP32-C6
static const uint8_t receiver_macs[4][ESP_NOW_ETH_ALEN] = {
    {0x58, 0xE6, 0xC5, 0x13, 0x6C, 0xF4}, // Receptor 1
    {0x58, 0xE6, 0xC5, 0x1A, 0x62, 0x78}, // Receptor 2
    {0x58, 0xE6, 0xC5, 0x13, 0xC2, 0xF8},  // Receptor 3
    {0x58, 0xE6, 0xC5, 0x1A, 0xF9, 0x30}
};


static void init_nvs(void) {
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
}

static void init_wifi_espnow(void) {
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());

    ESP_ERROR_CHECK(esp_wifi_get_mac(WIFI_IF_STA, s_propia_mac));
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "MAC de este modulo C6 (STA): %02X:%02X:%02X:%02X:%02X:%02X",
             s_propia_mac[0], s_propia_mac[1], s_propia_mac[2], s_propia_mac[3], s_propia_mac[4], s_propia_mac[5]);
    ESP_LOGI(TAG, "========================================");

    // Fijar canal a 1 (los receptores nunca llaman esp_wifi_set_channel,
    // asi que arrancan en el canal por defecto)
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous(true));
    ESP_ERROR_CHECK(esp_wifi_set_channel(WIFI_CHANNEL, WIFI_SECOND_CHAN_NONE));
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous(false));

    ESP_ERROR_CHECK(esp_now_init());

    // Registrar los peers (sin cifrado)
    esp_now_peer_info_t peer_info = {
        .channel = WIFI_CHANNEL,
        .ifidx = WIFI_IF_STA,
        .encrypt = false
    };

    for (int i = 0; i < 4; i++) {
        memcpy(peer_info.peer_addr, receiver_macs[i], ESP_NOW_ETH_ALEN);
        if (esp_now_add_peer(&peer_info) != ESP_OK) {
            ESP_LOGE(TAG, "Fallo al registrar peer %d", i + 1);
        } else {
            ESP_LOGI(TAG, "Peer %d registrado correctamente", i + 1);
        }
    }
}

static void init_uart(void) {
    uart_config_t uart_config = {
        .baud_rate = UART_BAUD_RATE,
        .data_bits = UART_DATA_8_BITS,
        .parity    = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    ESP_ERROR_CHECK(uart_param_config(UART_PORT_NUM, &uart_config));
    ESP_ERROR_CHECK(uart_set_pin(UART_PORT_NUM, UART_TX_PIN, UART_RX_PIN,
                                 UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
    ESP_ERROR_CHECK(uart_driver_install(UART_PORT_NUM, UART_BUF_SIZE * 2, UART_BUF_SIZE * 2, 0, NULL, 0));
}

static uint8_t calcular_checksum(uint8_t tipo, uint8_t len, const uint8_t *payload) {
    uint8_t chk = tipo ^ len;
    for (uint8_t i = 0; i < len; i++) {
        chk ^= payload[i];
    }
    return chk;
}

// Lee un byte con timeout; devuelve true si lo obtuvo
static bool read_one_byte(uint8_t *out, TickType_t timeout) {
    return uart_read_bytes(UART_PORT_NUM, out, 1, timeout) == 1;
}

// ---------------- Callback ESP-NOW: dato recibido de un receptor ----------------
static void on_espnow_recv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
    if (len <= 0 || len > MAX_PAYLOAD) return;

    // Reenvia el payload hacia la pantalla por UART con el mismo framing
    // tipo = 0x01 generico para "dato entrante de un receptor"
    uint8_t tipo = 0x01;
    uint8_t chk = calcular_checksum(tipo, (uint8_t)len, data);

    uint8_t start = FRAME_START;
    uint8_t plen = (uint8_t)len;
    uint8_t end = FRAME_END;

    uart_write_bytes(UART_PORT_NUM, (const char *)&start, 1);
    uart_write_bytes(UART_PORT_NUM, (const char *)&tipo, 1);
    uart_write_bytes(UART_PORT_NUM, (const char *)&plen, 1);
    uart_write_bytes(UART_PORT_NUM, (const char *)data, len);
    uart_write_bytes(UART_PORT_NUM, (const char *)&chk, 1);
    uart_write_bytes(UART_PORT_NUM, (const char *)&end, 1);
}

static void uart_espnow_bridge_task(void *pvParameters) {
    uint8_t payload[MAX_PAYLOAD];

    while (1) {
        uint8_t b;

        // 1) Esperar el byte de inicio de trama
        if (!read_one_byte(&b, 100 / portTICK_PERIOD_MS)) continue;
        if (b != FRAME_START) continue;

        // 2) tipo
        if (!read_one_byte(&b, 50 / portTICK_PERIOD_MS)) continue;
        uint8_t tipo = b;

        // 3) len
        if (!read_one_byte(&b, 50 / portTICK_PERIOD_MS)) continue;
        uint8_t plen = b;
        if (plen > MAX_PAYLOAD) {
            ESP_LOGW(TAG, "Payload demasiado grande (%d), trama descartada", plen);
            continue;
        }

        // 4) payload
        if (plen > 0) {
            int got = uart_read_bytes(UART_PORT_NUM, payload, plen, 50 / portTICK_PERIOD_MS);
            if (got != plen) {
                ESP_LOGW(TAG, "Payload incompleto (%d/%d), trama descartada", got, plen);
                continue;
            }
        }

        // 5) checksum
        if (!read_one_byte(&b, 50 / portTICK_PERIOD_MS)) continue;
        uint8_t recv_checksum = b;

        // 6) fin de trama
        if (!read_one_byte(&b, 50 / portTICK_PERIOD_MS)) continue;
        if (b != FRAME_END) {
            ESP_LOGW(TAG, "FRAME_END invalido (0x%02X), trama descartada", b);
            continue;
        }

        // 7) verificar checksum
        uint8_t expected = calcular_checksum(tipo, plen, payload);
        if (recv_checksum != expected) {
            ESP_LOGW(TAG, "Checksum invalido: recibido 0x%02X, esperado 0x%02X (tipo=0x%02X)",
                     recv_checksum, expected, tipo);
            continue;
        }

        ESP_LOGI(TAG, "Trama valida recibida de la pantalla (tipo=0x%02X, %d bytes de payload)", tipo, plen);

        // Confirmar recepcion de vuelta a la pantalla
        const char ack_msg[] = "ACK_C6\n";
        uart_write_bytes(UART_PORT_NUM, ack_msg, strlen(ack_msg));

        // Si el payload coincide con pitch_message_t, reenviar por ESP-NOW
        if (plen == sizeof(pitch_message_t)) {
            pitch_message_t *msg = (pitch_message_t *)payload;
            ESP_LOGI(TAG, "  -> Idioma: %d, Tipo: %d, Ubicacion: %d",
                     msg->idioma, msg->tipoLanzamiento, msg->ubicacion);

            for (int i = 0; i < 4; i++) {
                esp_err_t result = esp_now_send(receiver_macs[i], payload, plen);
                if (result != ESP_OK) {
                    ESP_LOGW(TAG, "Error envio ESP-NOW a receptor %d: %s", i + 1, esp_err_to_name(result));
                }
            }
        } else {
            ESP_LOGI(TAG, "Payload de %d bytes no coincide con pitch_message_t (3 bytes); no se reenvia por ESP-NOW", plen);
        }
    }
}

// Reimprime la MAC propia cada 5s para que sea facil de capturar en el
// monitor serie sin tener que estar conectado justo al arrancar
static void mac_announce_task(void *pvParameters) {
    while (1) {
        ESP_LOGI(TAG, "MAC de este modulo C6: %02X:%02X:%02X:%02X:%02X:%02X",
                 s_propia_mac[0], s_propia_mac[1], s_propia_mac[2],
                 s_propia_mac[3], s_propia_mac[4], s_propia_mac[5]);
        vTaskDelay(5000 / portTICK_PERIOD_MS);
    }
}

void app_main(void) {
    ESP_LOGI(TAG, "Iniciando C6 UART-ESPNOW Bridge (proyecto pantalla 3.5\")...");
    init_nvs();
    init_wifi_espnow();
    init_uart();

    esp_now_register_recv_cb(on_espnow_recv);

    xTaskCreate(uart_espnow_bridge_task, "bridge_task", 4096, NULL, 5, NULL);
    xTaskCreate(mac_announce_task, "mac_announce_task", 2048, NULL, 1, NULL);
}
