// ajustes_dynamic.c
//
// La implementacion de slider_brillo_event_cb se movio a ui_events.c,
// porque SquareLine genera y gestiona ese archivo directamente para los
// eventos configurados como "Call Function". Tenerla duplicada aqui
// causaba un error de linker (multiple definition), igual que paso antes
// con ui_event_ATRAS5 entre ui_Ajustes_.c y ui_AUDIOS_GUARDADOS.c.
//
// Este archivo queda vacio a proposito, listo para futuras funciones
// custom de la pantalla de Ajustes que NO se conecten via el mecanismo
// de eventos de SquareLine (por ejemplo, logica de inicializacion o
// sincronizacion de estado que se llame manualmente desde otro lado).

#include "ajustes_dynamic.h"
