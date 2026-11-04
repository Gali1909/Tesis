#include "ui_idioma_dispositivo.h"

// Valor por defecto: español. Se mantiene en memoria mientras el equipo
// esté encendido, sin importar cuántas veces se destruyan/recreen las
// pantallas de ajustes o se cambie el idioma de la pantalla.
static idioma_dispositivo_t idioma_dispositivo_actual = IDIOMA_DISPOSITIVO_ES;

void idioma_dispositivo_set(idioma_dispositivo_t idioma)
{
    idioma_dispositivo_actual = idioma;
}

idioma_dispositivo_t idioma_dispositivo_get(void)
{
    return idioma_dispositivo_actual;
}
