#include "ui_wifi_estado.h"

// Definida en Intento1.ino: arma y manda la trama UART_MSG_WIFI al modulo C6.
extern void enviarEstadoWifi(uint8_t encendido);

// Arranca apagado (igual que el switch dibujado en SquareLine).
static bool s_wifi_encendido = false;

bool wifi_pantalla_get(void)
{
    return s_wifi_encendido;
}

void wifi_pantalla_set(bool encendido)
{
    if(encendido == s_wifi_encendido) return;
    s_wifi_encendido = encendido;
    enviarEstadoWifi(encendido ? 1 : 0);
}

static void wifi_switch_event_cb(lv_event_t * e)
{
    lv_obj_t * sw = lv_event_get_target(e);
    wifi_pantalla_set(lv_obj_has_state(sw, LV_STATE_CHECKED));
}

void wifi_pantalla_attach(lv_obj_t * sw)
{
    if(sw == NULL) return;

    // La pantalla se reconstruye desde cero: reflejar el estado real guardado.
    if(s_wifi_encendido) lv_obj_add_state(sw, LV_STATE_CHECKED);
    else lv_obj_clear_state(sw, LV_STATE_CHECKED);

    lv_obj_add_event_cb(sw, wifi_switch_event_cb, LV_EVENT_VALUE_CHANGED, NULL);
}
