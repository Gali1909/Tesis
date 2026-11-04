// Guarda y carga los nombres de los receptores en la memoria NVS del ESP32.
// Lo llama idioma_receptores.c (C), por eso las funciones son extern "C".
#include <Arduino.h>
#include <Preferences.h>

static const char *NVS_NAMESPACE = "receptores";

extern "C" bool nombres_receptores_cargar(uint8_t fila, char *dst, size_t len)
{
    if(len == 0) return false;
    dst[0] = '\0';

    Preferences p;
    if(!p.begin(NVS_NAMESPACE, true)) return false;   // aun no existe: se usa el nombre por defecto

    char key[8];
    snprintf(key, sizeof(key), "n%u", (unsigned)fila);
    bool ok = false;
    if(p.isKey(key)) {
        p.getString(key, dst, len);
        ok = dst[0] != '\0';
    }
    p.end();
    return ok;
}

extern "C" void nombres_receptores_guardar(uint8_t fila, const char *txt)
{
    Preferences p;
    if(!p.begin(NVS_NAMESPACE, false)) return;

    char key[8];
    snprintf(key, sizeof(key), "n%u", (unsigned)fila);
    p.putString(key, txt);
    p.end();
}
