// ui_wifi_popup.h
//
// Ventana emergente para elegir una red WiFi y escribir su contrasena.
// Se abre/cierra desde ui_event_switch_wifi (ver ui_events.c) cuando el
// usuario prende o apaga el switch de WiFi de Ajustes.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Abre el popup (si ya esta abierto, no hace nada) y lanza un escaneo. */
void ui_wifi_popup_open(void);

/* Cierra el popup si esta abierto; seguro de llamar aunque no lo este. */
void ui_wifi_popup_close(void);

#ifdef __cplusplus
}
#endif
