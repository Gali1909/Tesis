// esp_now_comm.c
#include <stdio.h>
#include <string.h>
#include "esp_log.h"
#include "esp_err.h"
#include "esp_now_comm.h"
#include "uart_bridge.h"
#include "pitch_filter.h"

static const char *TAG = "COMM_UART";

#define UART_MSG_LANZAMIENTO 0x01
#define UART_MSG_CANCELAR    0x02
#define UART_MSG_JUGADA      0x03
#define UART_MSG_IDIOMA_RECEPTOR 0x04 /* payload: [receptor 0..2][idioma 0|1] */
/* UART_MSG_IDIOMA_SYNC (0x07) esta definido en uart_bridge.h */

#define COMANDO_CANCELAR 200
#define COMANDO_CANCELAR_JUGADA 201

#define RECEPTOR_TODOS 0xFF

typedef struct __attribute__((packed)) {
    uint8_t idioma;          /* 0=Espanol, 1=Ingles, etc. */
    uint8_t tipoLanzamiento; /* 0-13, o 200=Cancelar */
    uint8_t ubicacion;       /* 0-8 */
} pitch_message_t;

static uint8_t s_idioma_actual = 0;
static idioma_remoto_cb_t s_idioma_remoto_cb = NULL;

void esp_now_comm_set_idioma_remoto_cb(idioma_remoto_cb_t cb)
{
    s_idioma_remoto_cb = cb;
}

/* Tramas que llegan del C6 (originadas en la otra pantalla). */
static void on_frame_from_c6(uint8_t tipo, const uint8_t *payload, uint8_t len)
{
    /* Perfil de lanzador (0x13) / quitar perfil (0x14) enviados desde la app. */
    if (pitch_filter_on_frame(tipo, payload, len)) {
        return;
    }

    if (tipo != UART_MSG_IDIOMA_SYNC) {
        return; /* otros tipos no se usan por ahora en este sentido */
    }
    if (len != 2) {
        ESP_LOGW(TAG, "IDIOMA_SYNC con largo invalido: %d", len);
        return;
    }

    uint8_t receptor = payload[0];
    uint8_t idioma   = payload[1];
    if ((receptor > 2 && receptor != RECEPTOR_TODOS) || idioma > 1) {
        ESP_LOGW(TAG, "IDIOMA_SYNC con valores invalidos: receptor=%d idioma=%d", receptor, idioma);
        return;
    }

    ESP_LOGI(TAG, "Idioma cambiado desde la otra pantalla: receptor=%d idioma=%d", receptor, idioma);
    if (s_idioma_remoto_cb) {
        s_idioma_remoto_cb(receptor, idioma);
    }
}

esp_err_t esp_now_comm_init(void)
{
    esp_err_t err = uart_bridge_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Error inicializando puente UART: %s", esp_err_to_name(err));
        return err;
    }

    uart_bridge_set_frame_callback(on_frame_from_c6);

    ESP_LOGI(TAG, "Puente de comunicacion listo (UART -> modulo C6 -> ESP-NOW)");
    return ESP_OK;
}

esp_err_t esp_now_send_pitch_signal(int pitch_type, int zone)
{
    pitch_message_t msg = {
        .idioma = s_idioma_actual,
        .tipoLanzamiento = (uint8_t)pitch_type,
        .ubicacion = (uint8_t)zone
    };
    return uart_bridge_send_frame(UART_MSG_LANZAMIENTO, (const uint8_t *)&msg, sizeof(msg));
}

esp_err_t esp_now_send_cancelar(void)
{
    pitch_message_t msg = {
        .idioma = s_idioma_actual,
        .tipoLanzamiento = COMANDO_CANCELAR,
        .ubicacion = 0
    };
    return uart_bridge_send_frame(UART_MSG_CANCELAR, (const uint8_t *)&msg, sizeof(msg));
}

esp_err_t esp_now_send_cancelar_jugada(void)
{
    pitch_message_t msg = {
        .idioma = s_idioma_actual,
        .tipoLanzamiento = COMANDO_CANCELAR_JUGADA,
        .ubicacion = 0
    };
    return uart_bridge_send_frame(UART_MSG_CANCELAR, (const uint8_t *)&msg, sizeof(msg));
}

esp_err_t esp_now_send_idioma_sync(uint8_t receptor, uint8_t idioma)
{
    if ((receptor > 2 && receptor != RECEPTOR_TODOS) || idioma > 1) return ESP_ERR_INVALID_ARG;

    uint8_t payload[2] = { receptor, idioma };
    return uart_bridge_send_frame(UART_MSG_IDIOMA_SYNC, payload, sizeof(payload));
}

esp_err_t esp_now_send_idioma_receptor(uint8_t receptor, uint8_t idioma)
{
    if (receptor > 2 || idioma > 1) return ESP_ERR_INVALID_ARG;

    uint8_t payload[2] = { receptor, idioma };
    esp_err_t err = uart_bridge_send_frame(UART_MSG_IDIOMA_RECEPTOR, payload, sizeof(payload));
    if (err != ESP_OK) return err;

    /* Avisa a la otra pantalla para que refleje el cambio. Si falla, el
     * cambio en el receptor ya se hizo, asi que solo se registra. */
    esp_err_t sync_err = esp_now_send_idioma_sync(receptor, idioma);
    if (sync_err != ESP_OK) {
        ESP_LOGW(TAG, "No se pudo enviar IDIOMA_SYNC: %s", esp_err_to_name(sync_err));
    }
    return ESP_OK;
}

esp_err_t esp_now_send_jugada_texto(const char *texto)
{
    if (texto == NULL) return ESP_ERR_INVALID_ARG;

    /* El paquete lleva 1 byte de idioma al inicio + el texto (sin '\0'), que es
     * el formato que espera reproducirJugada() en Jugadores.ino. El puente C6
     * limita el payload a 64 bytes, por eso el texto puede tener 63 como maximo.
     * El receptor ya usa su propio idioma; este byte solo debe estar presente. */
    size_t len = strlen(texto);
    if (len > 63) {
        ESP_LOGE(TAG, "Texto de jugada demasiado largo: %d caracteres (max 63)", (int)len);
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t buf[64];
    buf[0] = s_idioma_actual;
    memcpy(buf + 1, texto, len);
    return uart_bridge_send_frame(UART_MSG_JUGADA, buf, (uint8_t)(len + 1));
}
