#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_now.h"
#include "esp_netif.h"
#include "driver/uart.h"
#include "driver/gpio.h"

// Bluetooth LE (NimBLE)
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"

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

// Tipo de trama que manda la pantalla para encender/apagar el Wi-Fi
// (mismo valor que UART_MSG_WIFI en Intento1.ino). Payload: 1 byte,
// 1 = encender, 0 = apagar.
#define UART_MSG_WIFI      0x04

// Tipo de trama para encender/apagar el Bluetooth (mismo valor que
// UART_MSG_BLUETOOTH en Intento1.ino). Payload: 1 byte, 1 = encender, 0 = apagar.
#define UART_MSG_BLUETOOTH 0x05

// Trama de la pantalla para UN solo receptor (mismo valor que
// UART_MSG_A_RECEPTOR en Intento1.ino). Payload: 1 byte con la fila/indice
// del receptor (0..3, posicion en receiver_macs) + los bytes a reenviar por
// ESP-NOW tal cual (hoy: un pitch_message_t de 3 bytes).
#define UART_MSG_A_RECEPTOR 0x06

// Aviso del C6 hacia la pantalla: "el receptor de la fila N esta vivo".
// Payload: 1 byte con la fila (indice en receiver_macs). Mismo valor que
// UART_MSG_RECEPTOR_ESTADO en Intento1.ino.
#define UART_MSG_RECEPTOR_ESTADO 0x07

// Primer (y unico) byte del latido que mandan los receptores por ESP-NOW.
// Mismo valor que MSG_LATIDO en Jugadores.ino.
#define MSG_LATIDO_RECEPTOR 0xB1

// Nombre BLE con el que aparece el modulo en el telefono.
#define BLE_DEVICE_NAME    "Pantalla35-BLE"

// Punto de acceso (SoftAP) que se levanta cuando la pantalla enciende el
// Wi-Fi. Cambia SSID y clave a tu gusto (la clave debe tener 8+ caracteres).
// Va fijo en el mismo canal que ESP-NOW para no romper los lanzamientos.
#define WIFI_AP_SSID       "Pantalla35-C6"
#define WIFI_AP_PASS       "12345678"
#define WIFI_AP_MAX_CONN   4

// true mientras el SoftAP esta encendido (modo APSTA); false = solo STA.
static bool s_wifi_ap_activo = false;

// Estado del Bluetooth. La pila NimBLE se inicializa una sola vez, la primera
// vez que se enciende; "apagar" detiene el advertising y desconecta al cliente
// (mas robusto que des-inicializar la pila cada vez).
static bool s_ble_iniciado = false;      // nimble_port_init() ya se llamo
static bool s_ble_sincronizado = false;  // la pila ya esta lista (sync_cb)
static bool s_ble_activo = false;        // el usuario lo tiene encendido
static uint8_t s_ble_own_addr_type;
static uint16_t s_ble_conn_handle = BLE_HS_CONN_HANDLE_NONE;

// Manda un mensaje de diagnostico a la pantalla por UART (aparece en su
// Monitor Serie como "Recibido del C6: ..."). Sirve para ver que pasa dentro
// del C6 sin conectarle el USB mientras esta en el socket de la pantalla.
static void reportar_a_pantalla(const char *fmt, ...) {
    char buf[96];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n <= 0) return;
    if (n >= (int)sizeof(buf)) n = sizeof(buf) - 1;
    uart_write_bytes(UART_PORT_NUM, buf, n);
}

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
    {0x58, 0xE6, 0xC5, 0x1A, 0xF6, 0xE4}, // Receptor 1
    {0x58, 0xE6, 0xC5, 0x1A, 0x62, 0x78}, // Receptor 2
    {0x58, 0xE6, 0xC5, 0x13, 0xC2, 0xF8},  // Receptor 3
    {0x58, 0xE6, 0xC5, 0x1A, 0xF9, 0x30}
    //{0x58, 0xE6, 0xC5, 0x13, 0x6C, 0xF4}
    
};
#define NUM_RECEPTORES (sizeof(receiver_macs) / sizeof(receiver_macs[0]))


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
    // Interfaz de red del SoftAP (DHCP, etc.). Solo se crea; el AP no emite
    // nada hasta que la pantalla active el Wi-Fi y el modo pase a APSTA.
    esp_netif_create_default_wifi_ap();

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

// Enciende/apaga el Wi-Fi visible (SoftAP). Importante: NO se llama a
// esp_wifi_stop(), porque ESP-NOW necesita el driver Wi-Fi activo; se cambia
// entre APSTA (Wi-Fi encendido) y STA (Wi-Fi apagado) y ESP-NOW sigue igual.
// Devuelve true si el estado final es el pedido.
static bool wifi_ap_set(bool encender) {
    if (encender == s_wifi_ap_activo) {
        ESP_LOGI(TAG, "Wi-Fi ya estaba %s", encender ? "ENCENDIDO" : "APAGADO");
        return true;
    }

    esp_err_t err;
    if (encender) {
        wifi_config_t ap_cfg = {0};
        strncpy((char *)ap_cfg.ap.ssid, WIFI_AP_SSID, sizeof(ap_cfg.ap.ssid) - 1);
        strncpy((char *)ap_cfg.ap.password, WIFI_AP_PASS, sizeof(ap_cfg.ap.password) - 1);
        ap_cfg.ap.ssid_len = strlen(WIFI_AP_SSID);
        ap_cfg.ap.channel = WIFI_CHANNEL;
        ap_cfg.ap.max_connection = WIFI_AP_MAX_CONN;
        ap_cfg.ap.authmode = WIFI_AUTH_WPA2_PSK;

        // El modo debe incluir AP ANTES de configurar la interfaz AP;
        // si no, esp_wifi_set_config() devuelve error y la red no aparece.
        err = esp_wifi_set_mode(WIFI_MODE_APSTA);
        if (err == ESP_OK) {
            err = esp_wifi_set_config(WIFI_IF_AP, &ap_cfg);
            if (err != ESP_OK) esp_wifi_set_mode(WIFI_MODE_STA); // deshacer
        }
    } else {
        err = esp_wifi_set_mode(WIFI_MODE_STA);
        if (err == ESP_OK) {
            // Reafirmar el canal de ESP-NOW despues de quitar el AP
            esp_wifi_set_promiscuous(true);
            esp_wifi_set_channel(WIFI_CHANNEL, WIFI_SECOND_CHAN_NONE);
            esp_wifi_set_promiscuous(false);
        }
    }

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "No se pudo %s el Wi-Fi: %s",
                 encender ? "encender" : "apagar", esp_err_to_name(err));
        return false;
    }

    s_wifi_ap_activo = encender;
    ESP_LOGI(TAG, "Wi-Fi %s%s", encender ? "ENCENDIDO (SoftAP " WIFI_AP_SSID ", canal 1)" : "APAGADO",
             encender ? "" : " (ESP-NOW sigue activo)");
    return true;
}

// ---------------- Bluetooth LE (NimBLE) ----------------
static int ble_gap_event_cb(struct ble_gap_event *event, void *arg);

static void ble_iniciar_advertising(void) {
    struct ble_hs_adv_fields fields = {0};
    const char *name = ble_svc_gap_device_name();

    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (uint8_t *)name;
    fields.name_len = strlen(name);
    fields.name_is_complete = 1;

    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "BLE: error configurando advertising (rc=%d)", rc);
        reportar_a_pantalla("BLE_ADV_ERR_FIELDS rc=%d\n", rc);
        return;
    }

    struct ble_gap_adv_params adv_params = {0};
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;  // conectable
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;  // visible para todos

    rc = ble_gap_adv_start(s_ble_own_addr_type, NULL, BLE_HS_FOREVER,
                           &adv_params, ble_gap_event_cb, NULL);
    if (rc != 0 && rc != BLE_HS_EALREADY) {
        ESP_LOGE(TAG, "BLE: error iniciando advertising (rc=%d)", rc);
        reportar_a_pantalla("BLE_ADV_ERR_START rc=%d\n", rc);
    } else {
        reportar_a_pantalla("BLE_ADV_OK nombre=%s\n", name);
    }
}

static int ble_gap_event_cb(struct ble_gap_event *event, void *arg) {
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            s_ble_conn_handle = event->connect.conn_handle;
            ESP_LOGI(TAG, "BLE: cliente conectado");
            reportar_a_pantalla("BLE_CLIENTE_CONECTADO\n");
        } else if (s_ble_activo) {
            ble_iniciar_advertising();  // conexion fallida: seguir visible
        }
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        s_ble_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        ESP_LOGI(TAG, "BLE: cliente desconectado");
        reportar_a_pantalla("BLE_CLIENTE_DESCONECTADO\n");
        if (s_ble_activo) ble_iniciar_advertising();
        break;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        if (s_ble_activo) ble_iniciar_advertising();
        break;
    default:
        break;
    }
    return 0;
}

static void ble_on_sync(void) {
    int rc = ble_hs_util_ensure_addr(0);
    if (rc == 0) rc = ble_hs_id_infer_auto(0, &s_ble_own_addr_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "BLE: error obteniendo direccion (rc=%d)", rc);
        reportar_a_pantalla("BLE_SYNC_ERR rc=%d\n", rc);
        return;
    }
    s_ble_sincronizado = true;
    ESP_LOGI(TAG, "BLE: pila lista");
    reportar_a_pantalla("BLE_PILA_LISTA\n");
    if (s_ble_activo) ble_iniciar_advertising();
}

static void ble_host_task(void *param) {
    nimble_port_run();  // no retorna hasta nimble_port_stop()
    nimble_port_freertos_deinit();
}

// Enciende/apaga el Bluetooth. Devuelve true si se aplico el estado pedido.
static bool ble_set(bool encender) {
    if (encender == s_ble_activo) {
        ESP_LOGI(TAG, "Bluetooth ya estaba %s", encender ? "ENCENDIDO" : "APAGADO");
        return true;
    }

    if (encender) {
        if (!s_ble_iniciado) {
            esp_err_t err = nimble_port_init();
            if (err != ESP_OK) {
                ESP_LOGE(TAG, "No se pudo iniciar NimBLE: %s", esp_err_to_name(err));
                reportar_a_pantalla("BLE_INIT_ERR %s\n", esp_err_to_name(err));
                return false;
            }
            ble_hs_cfg.sync_cb = ble_on_sync;
            ble_svc_gap_init();
            ble_svc_gap_device_name_set(BLE_DEVICE_NAME);
            nimble_port_freertos_init(ble_host_task);
            s_ble_iniciado = true;
        }
        s_ble_activo = true;
        if (s_ble_sincronizado) ble_iniciar_advertising();
        // Si la pila aun no esta lista, ble_on_sync() arranca el advertising.
        ESP_LOGI(TAG, "Bluetooth ENCENDIDO (BLE \"" BLE_DEVICE_NAME "\")");
    } else {
        s_ble_activo = false;
        if (s_ble_sincronizado) {
            ble_gap_adv_stop();
            if (s_ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
                ble_gap_terminate(s_ble_conn_handle, BLE_ERR_REM_USER_CONN_TERM);
            }
        }
        ESP_LOGI(TAG, "Bluetooth APAGADO");
    }
    return true;
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

    // Latido de un receptor: se identifica por su MAC y se avisa a la
    // pantalla con una trama UART_MSG_RECEPTOR_ESTADO (no se loguea para no
    // llenar la consola, que comparte linea con la UART hacia la pantalla).
    if (len == 1 && data[0] == MSG_LATIDO_RECEPTOR) {
        for (int i = 0; i < (int)NUM_RECEPTORES; i++) {
            if (memcmp(info->src_addr, receiver_macs[i], ESP_NOW_ETH_ALEN) == 0) {
                uint8_t fila = (uint8_t)i;
                uint8_t frame[6];
                frame[0] = FRAME_START;
                frame[1] = UART_MSG_RECEPTOR_ESTADO;
                frame[2] = 1;
                frame[3] = fila;
                frame[4] = calcular_checksum(UART_MSG_RECEPTOR_ESTADO, 1, &fila);
                frame[5] = FRAME_END;
                // Una sola escritura para que la trama no se mezcle con otras
                uart_write_bytes(UART_PORT_NUM, (const char *)frame, sizeof(frame));
                return;
            }
        }
        return;   // latido de una MAC que no esta en receiver_macs: se ignora
    }

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

        // Comando de la pantalla: encender/apagar Wi-Fi. Se atiende aqui y
        // NO se reenvia por ESP-NOW a los receptores.
        if (tipo == UART_MSG_WIFI) {
            if (plen != 1) {
                ESP_LOGW(TAG, "Trama WIFI con largo invalido (%d), descartada", plen);
                continue;
            }
            bool ok = wifi_ap_set(payload[0] != 0);
            const char *resp = ok ? (s_wifi_ap_activo ? "WIFI_ON\n" : "WIFI_OFF\n")
                                  : "WIFI_ERR\n";
            uart_write_bytes(UART_PORT_NUM, resp, strlen(resp));
            continue;
        }

        // Comando de la pantalla: encender/apagar Bluetooth. Igual que el
        // Wi-Fi, se atiende aqui y NO se reenvia por ESP-NOW.
        if (tipo == UART_MSG_BLUETOOTH) {
            if (plen != 1) {
                ESP_LOGW(TAG, "Trama BLUETOOTH con largo invalido (%d), descartada", plen);
                continue;
            }
            bool ok = ble_set(payload[0] != 0);
            const char *resp = ok ? (s_ble_activo ? "BT_ON\n" : "BT_OFF\n")
                                  : "BT_ERR\n";
            uart_write_bytes(UART_PORT_NUM, resp, strlen(resp));
            continue;
        }

        // Mensaje dirigido a UN receptor: payload[0] = fila (indice en
        // receiver_macs), el resto se reenvia por ESP-NOW unicast a esa MAC.
        // NO se manda a los demas receptores.
        if (tipo == UART_MSG_A_RECEPTOR) {
            if (plen < 2) {
                ESP_LOGW(TAG, "Trama A_RECEPTOR con largo invalido (%d), descartada", plen);
                continue;
            }
            uint8_t fila = payload[0];
            if (fila >= NUM_RECEPTORES) {
                ESP_LOGW(TAG, "Trama A_RECEPTOR con fila invalida (%d), descartada", fila);
                continue;
            }
            esp_err_t result = esp_now_send(receiver_macs[fila], &payload[1], plen - 1);
            if (result != ESP_OK) {
                ESP_LOGW(TAG, "Error envio ESP-NOW a receptor %d: %s", fila + 1, esp_err_to_name(result));
            } else {
                ESP_LOGI(TAG, "  -> Enviado solo al receptor %d (%d bytes)", fila + 1, plen - 1);
            }
            continue;
        }

        // Reenvia el payload por ESP-NOW a los 4 receptores, sea un
        // lanzamiento (3 bytes, pitch_message_t) o una jugada de texto
        // (idioma + texto, tamano variable). El receptor (Jugadores.ino)
        // distingue el tipo de mensaje por el tamano del paquete recibido,
        // asi que el bridge solo tiene que reenviar los bytes tal cual.
        if (plen == sizeof(pitch_message_t)) {
            pitch_message_t *msg = (pitch_message_t *)payload;
            ESP_LOGI(TAG, "  -> Lanzamiento: idioma=%d tipo=%d ubicacion=%d",
                     msg->idioma, msg->tipoLanzamiento, msg->ubicacion);
        } else {
            ESP_LOGI(TAG, "  -> Jugada de texto (%d bytes)", plen);
        }

        for (int i = 0; i < 4; i++) {
            esp_err_t result = esp_now_send(receiver_macs[i], payload, plen);
            if (result != ESP_OK) {
                ESP_LOGW(TAG, "Error envio ESP-NOW a receptor %d: %s", i + 1, esp_err_to_name(result));
            }
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
