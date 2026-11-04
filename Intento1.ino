#include "pins_config.h"
#include "LovyanGFX_Driver.h"
// #include "demos/lv_demos.h"

#include <Arduino.h>
#include <lvgl.h>
#include <Wire.h>
#include <SPI.h>

#include <stdbool.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_GFX.h>

#include <WiFi.h>
#include <esp_now.h>

#include "ui.h"

LGFX gfx;

/* Change to your screen resolution */
static lv_disp_draw_buf_t draw_buf;
static lv_color_t *buf;
static lv_color_t *buf1;

// ===================== BRILLO DE PANTALLA (PWM) =====================
#define PIN_BACKLIGHT 38

// Se llama desde el evento del slider en ui_AJUSTES.c
// porcentaje: 0 a 100 (viene directo del valor del lv_slider)
extern "C" void ajustarBrillo(uint8_t porcentaje) {
  if (porcentaje > 100) porcentaje = 100;

  // El slider va de 0-100, pero el PWM real va de 0-255
  uint8_t valorPWM = map(porcentaje, 0, 100, 0, 255);

  ledcWrite(PIN_BACKLIGHT, valorPWM);
}
// =======================================================================

// ===================== ESP-NOW =====================
// Ahora un "lanzamiento" se arma en DOS pasos: primero se presiona un boton
// de TIPO (Recta, Curva, Slider, ...) y despues un boton de UBICACION
// (Alta pegada, Medio, Abajo y afuera, ...). Cuando ya se tienen los dos
// datos, se envia UN SOLO mensaje ESP-NOW con ambos valores juntos.
//
// IDs de TIPO DE LANZAMIENTO (asignalos tu mismo en ui_events.c,
// esto es solo una propuesta de numeracion, en el mismo orden de tu lista):
//   1 = Recta                6 = Screwball        11 = Tenedor
//   2 = Curva                7 = Spitter
//   3 = Cambio                8 = Circle Change
//   4 = Recta 2 costuras     9 = Sinker
//   5 = Slider               10 = Cutter
//
// IDs de UBICACION:
//   1 = Alta pegada           6 = Afuera y en el medio
//   2 = Alta en el medio      7 = Pegada y abajo
//   3 = Alta y afuera         8 = En el medio y abajo
//   4 = Pegada y en el medio  9 = Abajo y afuera
//   5 = Medio
//
// IDs de IDIOMA (elegido con el "Roller" en ui_DISPOSITIVOS_E_IDIOMA.c):
//   0 = Espanol   1 = Ingles   2 = Italiano   3 = Japones
//
// El 0 se reserva como "todavia no hay seleccion" (para tipo y ubicacion;
// para idioma, 0 es un valor valido: Espanol, que es el idioma por defecto).
//
// COMANDO_CANCELAR: valor especial de tipoLanzamiento (fuera del rango 1-11)
// que se usa SOLO para avisarle al receptor que se cancelo la seleccion,
// para que reproduzca un audio de "cancelado" en vez de un lanzamiento.
#define COMANDO_CANCELAR 200

// Estructura del mensaje que se envia por ESP-NOW: viaja el idioma, el tipo
// Y la ubicacion juntos, en un solo paquete.
typedef struct {
  uint8_t idioma;          // 0-3, ver tabla de arriba
  uint8_t tipoLanzamiento; // 1-11, ver tabla de arriba (0 = mensaje "solo idioma")
  uint8_t ubicacion;       // 1-9,  ver tabla de arriba (0 = mensaje "solo idioma")
} pitch_message_t;

pitch_message_t datosLanzamiento;

// Idioma actualmente seleccionado en el Roller. Se manda junto con cada
// lanzamiento, para que el receptor sepa de que carpeta (Espanol,
// Ingles...) debe tomar el audio. Empieza en 0 (Espanol) por defecto.
uint8_t idiomaSeleccionado = 0;

// Guarda que TIPO se presiono, mientras se espera a que se presione la
// UBICACION. 0 significa "todavia no se ha elegido ningun tipo".
uint8_t tipoSeleccionado = 0;

// Guardan el ultimo combo enviado con exito, para poder repetirlo con el
// boton "Repetir ultimo lanzamiento" sin tener que volver a tocar los dos
// botones.
uint8_t ultimoTipoEnviado = 0;
uint8_t ultimaUbicacionEnviada = 0;

// ⚠️ REEMPLAZA esta dirección con la MAC real del XIAO ESP32C6 receptor
// (la que te imprimió el sketch ObtenerMAC_C6.ino en el Monitor Serie)
// Ejemplo de formato: si la MAC es 34:85:18:AB:CD:EF, se escribe:
// uint8_t receiverAddress[] = {0x34, 0x85, 0x18, 0xAB, 0xCD, 0xEF};
//uint8_t receiverAddress[] = {0x58,0xE6, 0xC5, 0x1A, 0xF9, 0x30};  // <-- CAMBIAR 58:E6:C5:13:6C:F4
//uint8_t receiverAddress[] = {0x58,0xE6, 0xC5, 0x13, 0x6C, 0xF4}; 
uint8_t receiverAddress[] = {0x58,0xE6, 0xC5, 0x13, 0xC2, 0xF8}; //58:E6:C5:13:C2:F8
// Callback que confirma si el envío tuvo éxito (se ve en el Monitor Serie)
void onDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  Serial.print("Envio ESP-NOW: ");
  Serial.println(status == ESP_NOW_SEND_SUCCESS ? "OK" : "FALLO");
}

void espnow_init() {
  WiFi.mode(WIFI_STA);

  if (esp_now_init() != ESP_OK) {
    Serial.println("Error iniciando ESP-NOW");
    return;
  }

  esp_now_register_send_cb(onDataSent);

  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, receiverAddress, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;

  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("Error agregando peer ESP-NOW");
  }
}

// Funcion interna que arma el paquete con idioma+tipo+ubicacion y lo envia.
// La usan seleccionarUbicacion() y repetirUltimoLanzamiento().
void enviarLanzamiento(uint8_t tipo, uint8_t ubicacion) {
  datosLanzamiento.idioma = idiomaSeleccionado;
  datosLanzamiento.tipoLanzamiento = tipo;
  datosLanzamiento.ubicacion = ubicacion;

  esp_err_t result = esp_now_send(receiverAddress, (uint8_t *)&datosLanzamiento, sizeof(datosLanzamiento));

  Serial.print("Enviando lanzamiento -> idioma: ");
  Serial.print(idiomaSeleccionado);
  Serial.print(" | tipo: ");
  Serial.print(tipo);
  Serial.print(" | ubicacion: ");
  Serial.println(ubicacion);

  if (result != ESP_OK) {
    Serial.println("Error al enviar por ESP-NOW");
  }
}

// Llamar desde el evento "value changed" del Roller de idioma en
// ui_DISPOSITIVOS_E_IDIOMA.c, pasando el indice seleccionado (0=Espanol,
// 1=Ingles, 2=Italiano, 3=Japones). Guarda el idioma para que se use en el
// PROXIMO lanzamiento que se envie, y ademas manda un mensaje inmediato con
// tipo=0 y ubicacion=0 para que el receptor actualice su idioma actual sin
// tener que esperar a un lanzamiento.
extern "C" void seleccionarIdioma(uint8_t idiomaId) {
  idiomaSeleccionado = idiomaId;

  Serial.print("Idioma seleccionado: ");
  Serial.println(idiomaId);

  datosLanzamiento.idioma = idiomaSeleccionado;
  datosLanzamiento.tipoLanzamiento = 0; // 0 = este mensaje es "solo idioma"
  datosLanzamiento.ubicacion = 0;

  esp_err_t result = esp_now_send(receiverAddress, (uint8_t *)&datosLanzamiento, sizeof(datosLanzamiento));
  if (result != ESP_OK) {
    Serial.println("Error al enviar el cambio de idioma por ESP-NOW");
  }
}

// Llamar desde el evento "clicked" de CADA boton de tipo de lanzamiento
// (Recta, Curva, Cambio, Slider, etc.), pasando el ID que le corresponda
// segun la tabla de arriba. Solo GUARDA la seleccion, todavia no envia nada.
extern "C" void seleccionarTipoLanzamiento(uint8_t tipoId) {
  tipoSeleccionado = tipoId;
  Serial.print("Tipo de lanzamiento seleccionado: ");
  Serial.println(tipoId);
}

// Llamar desde el evento "clicked" de CADA boton de ubicacion (Alta pegada,
// Medio, Abajo y afuera, etc.), pasando el ID que le corresponda. Si ya
// habia un tipo seleccionado, arma y envia el mensaje completo por ESP-NOW.
extern "C" void seleccionarUbicacion(uint8_t ubicacionId) {
  if (tipoSeleccionado == 0) {
    Serial.println("Selecciona primero un tipo de lanzamiento");
    return;
  }

  enviarLanzamiento(tipoSeleccionado, ubicacionId);

  ultimoTipoEnviado = tipoSeleccionado;
  ultimaUbicacionEnviada = ubicacionId;

  // Se limpia la seleccion para que el siguiente lanzamiento empiece de cero
  tipoSeleccionado = 0;
}

// Llamar desde el boton "Cancelar lanzamiento": borra el tipo que se
// hubiera presionado Y le avisa al receptor (con COMANDO_CANCELAR) para que
// reproduzca un audio de "lanzamiento cancelado".
extern "C" void cancelarLanzamiento() {
  tipoSeleccionado = 0;
  Serial.println("Seleccion cancelada");

  datosLanzamiento.idioma = idiomaSeleccionado;
  datosLanzamiento.tipoLanzamiento = COMANDO_CANCELAR;
  datosLanzamiento.ubicacion = 0;

  esp_err_t result = esp_now_send(receiverAddress, (uint8_t *)&datosLanzamiento, sizeof(datosLanzamiento));

  Serial.println("Enviando aviso de cancelacion por ESP-NOW");

  if (result != ESP_OK) {
    Serial.println("Error al enviar el aviso de cancelacion por ESP-NOW");
  }
}

// Llamar desde el boton "Repetir ultimo lanzamiento": vuelve a enviar el
// ultimo combo tipo+ubicacion que se envio con exito.
extern "C" void repetirUltimoLanzamiento() {
  if (ultimoTipoEnviado == 0) {
    Serial.println("Todavia no hay un lanzamiento previo para repetir");
    return;
  }
  enviarLanzamiento(ultimoTipoEnviado, ultimaUbicacionEnviada);
}
// =====================================================
// Display refresh
void my_disp_flush(lv_disp_drv_t *disp, const lv_area_t *area, lv_color_t *color_p) {
  if (gfx.getStartCount() > 0) {
    gfx.endWrite();
  }
  gfx.pushImageDMA(area->x1, area->y1, area->x2 - area->x1 + 1, area->y2 - area->y1 + 1, (lgfx::rgb565_t *)&color_p->full);
  lv_disp_flush_ready(disp);  // Tell lvgl that the refresh is complete
}

#include "touch.h"
uint16_t touchX, touchY;
void my_touchpad_read(lv_indev_drv_t *indev_driver, lv_indev_data_t *data) {
  data->state = LV_INDEV_STATE_REL;
  if ( gfx.getTouch( &touchX, &touchY ) ) {
    data->state = LV_INDEV_STATE_PR;
    //Set coordinates (the Y-axis of the screen on Longxian is opposite, and the X-axis of the screen on Puyang is opposite)
//    data->point.x = touchX;
//    data->point.y = LCD_V_RES - touchY; //After rotation, the Y-axis is reversed
    // data->point.x = LCD_H_RES - touchX;
    // data->point.y = touchY;
    data->point.x = touchX;
    data->point.y = touchY;

    Serial.print( "Data x " );
    Serial.println( data->point.x );
    Serial.print( "Data y " );
    Serial.println( data->point.y );
  }
}

void setup()
{
  Serial.begin(115200); // Init Display

  pinMode(18, OUTPUT);
  
  Wire.begin(15, 16);
  delay(50);

  // Init Display
  gfx.init();
  gfx.initDMA();
  gfx.startWrite();
  gfx.fillScreen(TFT_BLACK);

  lv_init();
  size_t buffer_size = sizeof(lv_color_t) * LCD_H_RES * LCD_V_RES;
  buf = (lv_color_t *)heap_caps_malloc(buffer_size, MALLOC_CAP_SPIRAM);
  buf1 = (lv_color_t *)heap_caps_malloc(buffer_size, MALLOC_CAP_SPIRAM);

  lv_disp_draw_buf_init(&draw_buf, buf, buf1, LCD_H_RES * LCD_V_RES);

  // Initialize display
  static lv_disp_drv_t disp_drv;
  lv_disp_drv_init(&disp_drv);
  // Change the following lines to your display resolution
  disp_drv.hor_res = LCD_H_RES;
  disp_drv.ver_res = LCD_V_RES;
  disp_drv.flush_cb = my_disp_flush;
  disp_drv.draw_buf = &draw_buf;
  lv_disp_drv_register(&disp_drv);

  // Initialize input device driver program
  static lv_indev_drv_t indev_drv;
  lv_indev_drv_init(&indev_drv);
  indev_drv.type = LV_INDEV_TYPE_POINTER;
  indev_drv.read_cb = my_touchpad_read;
  lv_indev_drv_register(&indev_drv);

  // Scan iic ***
  uint8_t gt911_address;
  delay(100);

  /* Turn on backlight (ahora controlado por PWM para variar el brillo) */
  ledcAttach(PIN_BACKLIGHT, 5000, 8);   // pin, frecuencia 5kHz, resolucion 8 bits (0-255)
  ledcWrite(PIN_BACKLIGHT, 255);        // arranca al 100% de brillo

  // Init touch device
  gt911_address = 0x14;
  touch_init(gt911_address);

  // Init ESP-NOW
  espnow_init();

  gfx.fillScreen(TFT_BLACK);
  // lv_demo_widgets();//Main UI interface
  ui_init();

  Serial.println( "Setup done" );
}

void loop()
{
  lv_timer_handler(); /* let the GUI do its work */
  delay(5);
}
