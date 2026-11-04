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

// Bluetooth LE (NimBLE) -- requiere habilitar Bluetooth/NimBLE en menuconfig
// (Component config -> Bluetooth -> NimBLE) y "bt" en el REQUIRES del
// CMakeLists.txt de este componente.
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

static const char *TAG = "BRIDGE_C6";

// Pines UART asignados en el ESP32-C6
// Segun el datasheet oficial del modulo (Elecrow DAC0010), el conector del
// socket "Wireless Module" expone U0TXD/U0RXD (UART0 por defecto del chip),
// que en el ESP32-C6 son fijos: U0TXD = GPIO16, U0RXD = GPIO17.
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

// Numero real de receptores (XIAO C6 con Jugadores.ino) en la cancha.
// Antes el arreglo estaba declarado como [3] pero tenia 4 MACs cargadas
// y los bucles usaban "3" fijo -- el 4to receptor nunca se registraba
// como peer ni recibia nada. Ahora todo se deriva de esta constante.
#define NUM_RECEIVERS      4

// Protocolo de trama usado por el P4 (uart_bridge.c):
// [FRAME_START][tipo][len][payload...][checksum][FRAME_END]
// checksum = tipo ^ len ^ payload[0] ^ payload[1] ^ ... ^ payload[len-1]
#define FRAME_START   0xAA
#define FRAME_END     0x55
#define MAX_PAYLOAD   64

// Mensaje P4 -> C6: fijar el idioma de UN receptor. Payload de 2 bytes:
// [receptor 0..NUM_RECEIVERS-1][idioma 0=ES 1=EN]. Se reenvia por ESP-NOW
// solo a ese receptor, como pitch_message_t con este comando en tipoLanzamiento.
#define UART_MSG_IDIOMA_RECEPTOR 0x04
#define COMANDO_IDIOMA_RECEPTOR  202

// Mensaje P4 -> C6: encender/apagar el Wi-Fi (SoftAP). Payload: 1 byte,
// 1 = encender, 0 = apagar. IMPORTANTE: hay que agregar el envio de esta
// trama en uart_bridge.c del lado P4 (mismo framing) para poder dispararla
// desde la pantalla; este C6 solo la atiende si le llega.
#define UART_MSG_WIFI       0x05

// Mensaje P4 -> C6: encender/apagar el Bluetooth (BLE). Payload: 1 byte,
// 1 = encender, 0 = apagar. Igual que UART_MSG_WIFI, falta agregarla en
// uart_bridge.c del P4.
#define UART_MSG_BLUETOOTH  0x06

// Mensaje P4 <-> C6 <-> C6 de la otra pantalla: sincronizar idioma de receptor
// entre las dos pantallas. Payload UART: 2 bytes [receptor 0..NUM_RECEIVERS-1
// o 0xFF = todos][idioma 0=ES 1=EN]. NO va a los receptores: se manda solo,
// por ESP-NOW unicast, al C6 de la otra pantalla. Por el aire viaja con un
// byte de tipo delante: [0x07][receptor][idioma] (3 bytes).
#define UART_MSG_IDIOMA_SYNC 0x07
#define SYNC_TODOS           0xFF

// Mensajes app -> C6 (por BLE) que se reenvian a la P4 por UART:
//   0x10 tipos de lanzamiento (solo se muestra en el log, para revisar el orden)
//   0x13 perfil de lanzador: la app manda texto "nombre\nnumero\nn\nslots\n"
//        (slots separados por coma); a la P4 se le manda solo la lista de
//        slots, 1 byte por slot.
//   0x14 quitar perfil (payload vacio)
#define APP_T_TIPOS          0x10
#define APP_T_PERFIL         0x13
#define APP_T_QUITAR_PERFIL  0x14
#define APP_T_PERFIL_DATOS   0x15
#define APP_T_PERFIL_TIPOS   0x17
#define APP_T_PERFIL_VISTA   0x16
// MAC del C6 de la OTRA pantalla (la S3). Debe ser distinta de la MAC propia
// que este modulo imprime al arrancar; si coinciden, se avisa en el log.
static const uint8_t MAC_PANTALLA_REMOTA[ESP_NOW_ETH_ALEN] =
    {0x58, 0xE6, 0xC5, 0xD3, 0x98, 0xE4};

// Punto de acceso (SoftAP) que se levanta cuando la pantalla pide encender
// el Wi-Fi. Cambia SSID y clave a tu gusto (la clave debe tener 8+ caracteres).
// Va fijo en el mismo canal que ESP-NOW (WIFI_CHANNEL) para no romper los
// lanzamientos -- a diferencia de conectarse como STA a un router externo,
// el SoftAP no depende de que nadie mas decida el canal.
#define WIFI_AP_SSID       "CanchaP4-C6"
#define WIFI_AP_PASS       "12345678"
#define WIFI_AP_MAX_CONN   4

// Nombre BLE con el que aparece el modulo en el telefono.
#define BLE_DEVICE_NAME    "CanchaP4-BLE"

// Estructura de 3 bytes (coincide con Jugadores.ino)
typedef struct __attribute__((packed)) {
    uint8_t idioma;
    uint8_t tipoLanzamiento;
    uint8_t ubicacion;
} pitch_message_t;

// MACs reales de los 4 receptores (MAC_ESP32-C6.txt)
static const uint8_t receiver_macs[NUM_RECEIVERS][ESP_NOW_ETH_ALEN] = {
    {0x58, 0xE6, 0xC5, 0x13, 0x6C, 0xF4}, // Receptor 1
    {0x58, 0xE6, 0xC5, 0x1A, 0x62, 0x78}, // Receptor 2
    {0x58, 0xE6, 0xC5, 0x13, 0xC2, 0xF8}, // Receptor 3
    {0x58, 0xE6, 0xC5, 0x1A, 0xF9, 0x30}, // Receptor 4
};

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

// Manda un mensaje de diagnostico a la pantalla por UART (aparece del lado
// del P4 como texto suelto, fuera del framing). Sirve para ver que paso con
// el Wi-Fi/BLE dentro del C6 sin tener que conectarle el USB directamente.
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

    uint8_t propia_mac[ESP_NOW_ETH_ALEN];
    ESP_ERROR_CHECK(esp_wifi_get_mac(WIFI_IF_STA, propia_mac));
    ESP_LOGI(TAG, "MAC de este modulo C6 (STA): %02X:%02X:%02X:%02X:%02X:%02X",
             propia_mac[0], propia_mac[1], propia_mac[2], propia_mac[3], propia_mac[4], propia_mac[5]);

    if (memcmp(propia_mac, MAC_PANTALLA_REMOTA, ESP_NOW_ETH_ALEN) == 0) {
        ESP_LOGE(TAG, "MAC_PANTALLA_REMOTA es la MAC de ESTE modulo: cambiala por la del C6 de la otra pantalla");
    }

    // Fijar canal a 1 (los receptores nunca llaman esp_wifi_set_channel,
    // asi que arrancan en el canal por defecto)
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous(true));
    ESP_ERROR_CHECK(esp_wifi_set_channel(WIFI_CHANNEL, WIFI_SECOND_CHAN_NONE));
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous(false));

    ESP_ERROR_CHECK(esp_now_init());

    // Registrar los peers (sin cifrado, segun lo acordado)
    esp_now_peer_info_t peer_info = {
        .channel = WIFI_CHANNEL,
        .ifidx = WIFI_IF_STA,
        .encrypt = false
    };

    for (int i = 0; i < NUM_RECEIVERS; i++) {
        memcpy(peer_info.peer_addr, receiver_macs[i], ESP_NOW_ETH_ALEN);
        if (esp_now_add_peer(&peer_info) != ESP_OK) {
            ESP_LOGE(TAG, "Fallo al registrar peer %d", i + 1);
        } else {
            ESP_LOGI(TAG, "Peer %d registrado correctamente", i + 1);
        }
    }

    // Peer del C6 de la otra pantalla (sincronizacion de idioma, tipo 0x07)
    memcpy(peer_info.peer_addr, MAC_PANTALLA_REMOTA, ESP_NOW_ETH_ALEN);
    if (esp_now_add_peer(&peer_info) != ESP_OK) {
        ESP_LOGE(TAG, "Fallo al registrar peer de la otra pantalla");
    } else {
        ESP_LOGI(TAG, "Peer otra pantalla registrado correctamente");
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
// ---------------- Servicio de datos app <-> pantalla (GATT) ----------------
// Servicio tipo Nordic UART: la app escribe tramas en RX y esta pantalla
// responde por notificaciones en TX. Trama de la app (por BLE):
//   0xAA 0x55 | tipo | seq | largo(2, little endian) | payload | xor
// con xor = tipo ^ seq ^ largo_lo ^ largo_hi ^ payload. Es un formato
// DISTINTO al de la UART con el P4: aqui el payload puede llegar a 2048 bytes.
#define APP_T_ACK        0x20
#define APP_MAX_PAYLOAD  2048

static const ble_uuid128_t UUID_APP_SVC = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x01, 0x00, 0x40, 0x6e);
static const ble_uuid128_t UUID_APP_RX = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x02, 0x00, 0x40, 0x6e);
static const ble_uuid128_t UUID_APP_TX = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x03, 0x00, 0x40, 0x6e);

static uint16_t s_app_tx_handle;
static uint8_t s_app_rx[APP_MAX_PAYLOAD + 16];
static size_t s_app_rx_n = 0;

static void app_enviar_ack(uint8_t seq, uint8_t estado) {
    if (s_ble_conn_handle == BLE_HS_CONN_HANDLE_NONE) return;
    uint8_t t[8] = { 0xAA, 0x55, APP_T_ACK, seq, 1, 0, estado, 0 };
    t[7] = APP_T_ACK ^ seq ^ 1 ^ 0 ^ estado;
    struct os_mbuf *om = ble_hs_mbuf_from_flat(t, sizeof(t));
    if (!om) return;
    ble_gatts_notify_custom(s_ble_conn_handle, s_app_tx_handle, om);
}

static void enviar_trama_uart(uint8_t tipo, const uint8_t *payload, uint8_t len);

// Extrae la lista de slots (4ta linea) del texto del perfil y la reenvia a la
// P4. Devuelve true si se envio.
static bool app_reenviar_perfil(const uint8_t *p, size_t largo) {
    size_t i = 0;
    int lineas = 0;
    while (i < largo && lineas < 3) {            // saltar nombre, numero y cantidad
        if (p[i] == '\n') lineas++;
        i++;
    }
    if (lineas < 3) return false;

    uint8_t slots[MAX_PAYLOAD];
    uint8_t n = 0;
    int val = -1;
    for (; i < largo && p[i] != '\n'; i++) {
        if (p[i] >= '0' && p[i] <= '9') {
            val = (val < 0 ? 0 : val) * 10 + (p[i] - '0');
            if (val > 255) return false;
        } else if (p[i] == ',') {
            if (val >= 0 && n < MAX_PAYLOAD) slots[n++] = (uint8_t)val;
            val = -1;
        }
    }
    if (val >= 0 && n < MAX_PAYLOAD) slots[n++] = (uint8_t)val;
    if (n == 0) return false;

    enviar_trama_uart(APP_T_PERFIL, slots, n);
    ESP_LOGI(TAG, "Perfil de lanzador reenviado a la P4: %u slots", n);
    return true;
}

// ETAPA 2: por ahora solo se reporta y se confirma. Mas adelante aqui se
// reenviara el contenido al P4 por UART.
static void app_mensaje_recibido(uint8_t tipo, uint8_t seq, const uint8_t *p, size_t largo) {
    ESP_LOGI(TAG, "App BLE: tipo=0x%02X seq=%u largo=%u", tipo, seq, (unsigned)largo);
    reportar_a_pantalla("APP_MSG tipo=0x%02X seq=%u largo=%u\n", tipo, seq, (unsigned)largo);

    uint8_t estado = 0;
    if (tipo == APP_T_TIPOS) {
        // Diagnostico: ver en el log USB del C6 el orden de los tipos de la app.
        ESP_LOGI(TAG, "Tipos de la app:\n%.*s", (int)largo, (const char *)p);
    } else if (tipo == APP_T_PERFIL) {
        if (!app_reenviar_perfil(p, largo)) {
            ESP_LOGW(TAG, "Perfil de lanzador con formato invalido");
            estado = 3;
        }
        } else if (tipo == APP_T_QUITAR_PERFIL) {
        enviar_trama_uart(APP_T_QUITAR_PERFIL, NULL, 0);
        ESP_LOGI(TAG, "Quitar perfil reenviado a la P4");
    } else if (tipo == APP_T_PERFIL_TIPOS) {
        if (largo < 1 || largo > MAX_PAYLOAD) {
            ESP_LOGW(TAG, "Tipos 0x17 con largo invalido (%u)", (unsigned)largo);
            estado = 3;
        } else {
            enviar_trama_uart(APP_T_PERFIL_TIPOS, p, (uint8_t)largo);
        }
    } else if (tipo == APP_T_PERFIL_VISTA) {
        if (largo < 5 || largo > MAX_PAYLOAD) {
            ESP_LOGW(TAG, "Vista 0x16 con largo invalido (%u)", (unsigned)largo);
            estado = 3;
        } else {
            enviar_trama_uart(APP_T_PERFIL_VISTA, p, (uint8_t)largo);
        }
    } else if (tipo == APP_T_PERFIL_DATOS) {
        if (largo < 40 || largo > MAX_PAYLOAD) {
            ESP_LOGW(TAG, "Perfil 0x15 con largo invalido (%u)", (unsigned)largo);
            estado = 3;
        } else {
            enviar_trama_uart(APP_T_PERFIL_DATOS, p, (uint8_t)largo);
            ESP_LOGI(TAG, "Datos de perfil reenviados a la P4 (%u bytes)", (unsigned)largo);
        }
    }
    app_enviar_ack(seq, estado);
}

static void app_rx_quitar(size_t k) {
    memmove(s_app_rx, s_app_rx + k, s_app_rx_n - k);
    s_app_rx_n -= k;
}

static void app_procesar_rx(void) {
    while (s_app_rx_n >= 7) {
        if (s_app_rx[0] != 0xAA || s_app_rx[1] != 0x55) { app_rx_quitar(1); continue; }
        size_t largo = s_app_rx[4] | (s_app_rx[5] << 8);
        if (largo > APP_MAX_PAYLOAD) { app_rx_quitar(1); continue; }
        size_t total = 7 + largo;
        if (s_app_rx_n < total) break;
        uint8_t x = 0;
        for (size_t i = 2; i < total - 1; i++) x ^= s_app_rx[i];
        uint8_t tipo = s_app_rx[2];
        uint8_t seq = s_app_rx[3];
        if (x != s_app_rx[total - 1]) {
            ESP_LOGW(TAG, "App BLE: XOR incorrecto (tipo=0x%02X)", tipo);
            reportar_a_pantalla("APP_ERR_XOR tipo=0x%02X\n", tipo);
            app_enviar_ack(seq, 2);
        } else {
            app_mensaje_recibido(tipo, seq, &s_app_rx[6], largo);
        }
        app_rx_quitar(total);
    }
}

static int gatt_app_acceso_cb(uint16_t conn_handle, uint16_t attr_handle,
                              struct ble_gatt_access_ctxt *ctxt, void *arg) {
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    if (len > sizeof(s_app_rx)) return BLE_ATT_ERR_INSUFFICIENT_RES;
    if (s_app_rx_n + len > sizeof(s_app_rx)) s_app_rx_n = 0;
    if (os_mbuf_copydata(ctxt->om, 0, len, &s_app_rx[s_app_rx_n]) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    s_app_rx_n += len;
    app_procesar_rx();
    return 0;
}

static const struct ble_gatt_svc_def gatt_app_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &UUID_APP_SVC.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &UUID_APP_RX.u,
                .access_cb = gatt_app_acceso_cb,
                .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
            },
            {
                .uuid = &UUID_APP_TX.u,
                .access_cb = gatt_app_acceso_cb,
                .val_handle = &s_app_tx_handle,
                .flags = BLE_GATT_CHR_F_NOTIFY,
            },
            { 0 }
        },
    },
    { 0 }
};
static int ble_gap_event_cb(struct ble_gap_event *event, void *arg);

static void ble_iniciar_advertising(void) {
    struct ble_hs_adv_fields fields = {0};
    const char *name = ble_svc_gap_device_name();

    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = (ble_uuid128_t *)&UUID_APP_SVC;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;

    int rc = ble_gap_adv_set_fields(&fields);
    if (rc == 0) {
        struct ble_hs_adv_fields rsp = {0};
        rsp.name = (uint8_t *)name;
        rsp.name_len = strlen(name);
        rsp.name_is_complete = 1;
        rc = ble_gap_adv_rsp_set_fields(&rsp);
    }
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
            s_app_rx_n = 0;
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
            ble_svc_gatt_init();
            ble_att_set_preferred_mtu(247);
            if (ble_gatts_count_cfg(gatt_app_svcs) != 0 || ble_gatts_add_svcs(gatt_app_svcs) != 0) {
                ESP_LOGE(TAG, "BLE: no se pudo registrar el servicio de datos");
                reportar_a_pantalla("BLE_GATT_ERR\n");
            }
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

// Debe coincidir exactamente con calcular_checksum() en uart_bridge.c del P4
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

// Arma una trama completa y la manda al P4 en UNA sola llamada a
// uart_write_bytes (atomica frente a otras tareas que escriben texto suelto).
static void enviar_trama_uart(uint8_t tipo, const uint8_t *payload, uint8_t len) {
    if (len > MAX_PAYLOAD) return;
    uint8_t frame[MAX_PAYLOAD + 5];
    frame[0] = FRAME_START;
    frame[1] = tipo;
    frame[2] = len;
    if (len) memcpy(&frame[3], payload, len);
    frame[3 + len] = calcular_checksum(tipo, len, payload);
    frame[4 + len] = FRAME_END;
    uart_write_bytes(UART_PORT_NUM, frame, len + 5);
}

// Recepcion ESP-NOW (tarea Wi-Fi: mantenerla corta). Solo acepta mensajes de
// idioma que vengan de la MAC de la otra pantalla; todo lo demas se ignora.
// Firma de ESP-IDF 5.x (esp_now_recv_info_t).
static void on_espnow_recv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
    if (!info || !data) return;
    if (memcmp(info->src_addr, MAC_PANTALLA_REMOTA, ESP_NOW_ETH_ALEN) != 0) return;
    if (len != 3 || data[0] != UART_MSG_IDIOMA_SYNC) {
        ESP_LOGW(TAG, "Mensaje de la otra pantalla ignorado (len=%d)", len);
        return;
    }
    if (!(data[1] < NUM_RECEIVERS || data[1] == SYNC_TODOS) || data[2] > 1) {
        ESP_LOGW(TAG, "Sync de idioma invalido de la otra pantalla");
        return;
    }
    enviar_trama_uart(UART_MSG_IDIOMA_SYNC, &data[1], 2);
    ESP_LOGI(TAG, "Sync idioma desde otra pantalla -> P4 (receptor=0x%02X idioma=%d)", data[1], data[2]);
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

        ESP_LOGI(TAG, "Trama valida recibida del P4 (tipo=0x%02X, %d bytes de payload)", tipo, plen);

        // Confirmar recepcion de vuelta al P4 (visible en el monitor del P4, COM20)
        const char ack_msg[] = "ACK_C6\n";
        uart_write_bytes(UART_PORT_NUM, ack_msg, strlen(ack_msg));

        // Idioma de un receptor concreto: va solo a esa MAC, no a los 4.
        if (tipo == UART_MSG_IDIOMA_RECEPTOR) {
            if (plen != 2 || payload[0] >= NUM_RECEIVERS || payload[1] > 1) {
                ESP_LOGW(TAG, "Mensaje de idioma invalido (len=%d), descartado", plen);
                continue;
            }
            pitch_message_t msg_idioma = {
                .idioma = payload[1],
                .tipoLanzamiento = COMANDO_IDIOMA_RECEPTOR,
                .ubicacion = 0
            };
            esp_err_t r = esp_now_send(receiver_macs[payload[0]], (const uint8_t *)&msg_idioma, sizeof(msg_idioma));
            ESP_LOGI(TAG, "  -> Idioma %d para receptor %d: %s",
                     payload[1], payload[0] + 1, esp_err_to_name(r));
            continue;
        }

        // Comando del P4: encender/apagar Wi-Fi. Se atiende aqui y NO se
        // reenvia por ESP-NOW a los receptores.
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

        // Comando del P4: encender/apagar Bluetooth. Igual que el Wi-Fi, se
        // atiende aqui y NO se reenvia por ESP-NOW.
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

        // Sincronizacion de idioma con la otra pantalla: solo a su C6, NUNCA
        // a los receptores (la leerian como una jugada).
        if (tipo == UART_MSG_IDIOMA_SYNC) {
            if (plen != 2 || !(payload[0] < NUM_RECEIVERS || payload[0] == SYNC_TODOS) || payload[1] > 1) {
                ESP_LOGW(TAG, "Trama SYNC invalida (len=%d), descartada", plen);
                continue;
            }
            const uint8_t aire[3] = { UART_MSG_IDIOMA_SYNC, payload[0], payload[1] };
            esp_err_t r = esp_now_send(MAC_PANTALLA_REMOTA, aire, sizeof(aire));
            ESP_LOGI(TAG, "  -> Sync idioma a otra pantalla: %s", esp_err_to_name(r));
            continue;
        }

        // Reenviar SIEMPRE el payload por ESP-NOW a los 4 receptores, sin
        // importar su tamano: 3 bytes = lanzamiento/cancelar (pitch_message_t),
        // cualquier otro tamano = texto de una jugada (esp_now_send_jugada_texto
        // en la pantalla manda el texto crudo, sin envolverlo en pitch_message_t).
        // Antes este bloque solo reenviaba cuando plen == sizeof(pitch_message_t),
        // por eso las jugadas nunca llegaban a los jugadores: se descartaban aqui
        // mismo, antes de salir por el aire.
        if (plen == sizeof(pitch_message_t)) {
            pitch_message_t *msg = (pitch_message_t *)payload;
            ESP_LOGI(TAG, "  -> Idioma: %d, Tipo: %d, Ubicacion: %d",
                     msg->idioma, msg->tipoLanzamiento, msg->ubicacion);
        } else {
            ESP_LOGI(TAG, "  -> Texto de jugada (%d bytes)", plen);
        }

        for (int i = 0; i < NUM_RECEIVERS; i++) {
            esp_err_t result = esp_now_send(receiver_macs[i], payload, plen);
            if (result != ESP_OK) {
                ESP_LOGW(TAG, "Error envio ESP-NOW a receptor %d: %s", i + 1, esp_err_to_name(result));
            }
        }
    }
}

void app_main(void) {
    ESP_LOGI(TAG, "Iniciando C6 UART-ESPNOW Bridge (P4 10.1\")...");
    init_nvs();
    init_wifi_espnow();
    init_uart();
    // Despues de init_uart(): el callback escribe por UART.
    ESP_ERROR_CHECK(esp_now_register_recv_cb(on_espnow_recv));

    xTaskCreate(uart_espnow_bridge_task, "bridge_task", 4096, NULL, 5, NULL);
}
