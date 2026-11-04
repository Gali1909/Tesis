#include "ui_bluetooth_estado.h"

// Definida en Intento1.ino: arma y manda la trama UART_MSG_BLUETOOTH al modulo C6.
extern void enviarEstadoBluetooth(uint8_t encendido);

// Arranca apagado (igual que el switch dibujado en SquareLine).
static bool s_bluetooth_encendido = false;

bool bluetooth_pantalla_get(void)
{
    return s_bluetooth_encendido;
}

void bluetooth_pantalla_set(bool encendido)
{
    if(encendido == s_bluetooth_encendido) return;
    s_bluetooth_encendido = encendido;
    enviarEstadoBluetooth(encendido ? 1 : 0);
}

static void bluetooth_switch_event_cb(lv_event_t * e)
{
    lv_obj_t * sw = lv_event_get_target(e);
    bluetooth_pantalla_set(lv_obj_has_state(sw, LV_STATE_CHECKED));
}

void bluetooth_pantalla_attach(lv_obj_t * sw)
{
    if(sw == NULL) return;

    // La pantalla se reconstruye desde cero: reflejar el estado real guardado.
    if(s_bluetooth_encendido) lv_obj_add_state(sw, LV_STATE_CHECKED);
    else lv_obj_clear_state(sw, LV_STATE_CHECKED);

    lv_obj_add_event_cb(sw, bluetooth_switch_event_cb, LV_EVENT_VALUE_CHANGED, NULL);
}
