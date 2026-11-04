#include "pins_config.h"
#include "LovyanGFX_Driver.h"
// #include "demos/lv_demos.h"
#include "pins_config.h"

#include <Arduino.h>
#include <lvgl.h>
#include <Wire.h>
#include <SPI.h>

#include <stdbool.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_GFX.h>

#include "ui.h"
#include "ui_idioma_dispositivo.h"
#include "ui_wifi_estado.h"
#include "ui_bluetooth_estado.h"

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

// ===================== PUENTE UART -> MODULO C6 (ESP-NOW) =====================
// Misma arquitectura que usa el CrowPanel P4 (esp_now_comm.c + uart_bridge.c):
// esta pantalla YA NO habla ESP-NOW directamente. En vez de eso arma una
// trama y la manda por UART a un modulo XIAO ESP32-C6 externo, que es quien
// hace el ESP-NOW real hacia los receptores (Jugadores.ino, etc). Esto evita
// depender del radio WiFi de esta pantalla y reutiliza el mismo bridge C6
// que ya funciona en el P4.
//
// IDs de TIPO DE LANZAMIENTO. Deben coincidir EXACTAMENTE con el enum
// pitch_type_t de lanzamientos_dynamic.h del P4 (0-indexado):
//   0 = Recta 4 costuras      7 = Sweeper
//   1 = Recta 2 costuras      8 = Cambio de velocidad
//   2 = Sinker                9 = Circle change
//   3 = Cutter                10 = Splitter
//   4 = Split-finger          11 = Tenedor
//   5 = Curva                 12 = Nudillera
//   6 = Slider                13 = Tirabuzon
//
// IDs de UBICACION (0-indexado):
//   0 = Alta pegada           5 = Afuera y en el medio
//   1 = Alta en el medio      6 = Pegada y abajo
//   2 = Alta y afuera         7 = En el medio y abajo
//   3 = Pegada y en el medio  8 = Abajo y afuera
//   4 = Medio
//
// IDs de IDIOMA (elegido con el "Roller" en ui_DISPOSITIVOS_E_IDIOMA.c):
//   0 = Espanol   1 = Ingles   2 = Italiano   3 = Japones
//
// COMANDO_CANCELAR: valor especial de tipoLanzamiento (fuera del rango
// 0-13) que se usa SOLO para avisarle al receptor que se cancelo la
// seleccion, para que reproduzca un audio de "cancelado" en vez de un
// lanzamiento.
#define COMANDO_CANCELAR 200

// Valor especial que se usa cuando se presiona "Cancelar jugada" (pantalla
// ui_Estrategia_defensiva_), distinto de COMANDO_CANCELAR para que el
// receptor reproduzca un aviso distinto. Debe ser el MISMO numero que
// COMANDO_CANCELAR_JUGADA en Jugadores.ino.
#define COMANDO_CANCELAR_JUGADA 201

// Comando (en tipoLanzamiento) para fijar el idioma de los RECEPTORES.
// El campo "idioma" trae 0=Espanol, 1=Ingles. Debe ser el MISMO numero que
// COMANDO_IDIOMA_RECEPTOR en Jugadores.ino.
#define COMANDO_IDIOMA_RECEPTOR 202

// Longitud maxima del texto de una jugada (sin contar el byte de idioma).
// Debe coincidir con LONGITUD_MAX_JUGADA en Jugadores.ino.
#define LONGITUD_MAX_JUGADA 64

// TIPO_SIN_SELECCION: valor centinela para "todavia no hay tipo elegido" Y
// para el mensaje "solo cambio el idioma". Debe ser el MISMO numero que
// TIPO_SIN_SELECCION en Jugadores.ino y en esp_now_comm.c (P4).
#define TIPO_SIN_SELECCION 255

// Estructura del mensaje que viaja dentro del payload de la trama UART:
// idioma, tipo Y ubicacion juntos, en un solo paquete. Debe coincidir
// EXACTAMENTE con pitch_message_t de Jugadores.ino y de esp_now_comm.c (P4).
typedef struct __attribute__((packed)) {
  uint8_t idioma;          // 0-3, ver tabla de arriba
  uint8_t tipoLanzamiento; // 0-13, ver tabla de arriba; 200=Cancelar; 255=sin seleccion/solo idioma
  uint8_t ubicacion;       // 0-8,  ver tabla de arriba
} pitch_message_t;

pitch_message_t datosLanzamiento;

// --- Protocolo de trama UART (identico a uart_bridge.c del P4) ---
// [FRAME_START][tipo][len][payload...][checksum][FRAME_END]
// checksum = tipo ^ len ^ payload[0] ^ payload[1] ^ ... ^ payload[len-1]
#define FRAME_START 0xAA
#define FRAME_END   0x55
#define MAX_PAYLOAD 64

// Tipos de trama (mismos valores que UART_MSG_* en esp_now_comm.c del P4)
#define UART_MSG_LANZAMIENTO 0x01
#define UART_MSG_CANCELAR    0x02
#define UART_MSG_JUGADA      0x03
#define UART_MSG_WIFI        0x04  // payload: 1 byte, 0 = apagar Wi-Fi, 1 = encender
#define UART_MSG_BLUETOOTH   0x05  // payload: 1 byte, 0 = apagar Bluetooth, 1 = encender
#define UART_MSG_A_RECEPTOR  0x06  // payload: 1 byte de fila (0..3) + 3 bytes de pitch_message_t; el C6 lo manda SOLO a esa MAC
#define UART_MSG_RECEPTOR_ESTADO 0x07  // C6 -> pantalla. Payload: 1 byte con la fila (0..3) del receptor que acaba de dar señal de vida

// Confirmado en el esquematico Eagle oficial del fabricante (V1.2/1.3/1.4):
// las redes del socket "Wireless module" estan nombradas literalmente
// IO1_ESP_TXD2 (-> GPIO1 del ESP32-S3) e IO2_ESP_RXD2 (-> GPIO2). Por eso se
// usan estos GPIO directos en vez de macros RX2/TX2 genericas.
#define UART_BRIDGE_TX_PIN 1
#define UART_BRIDGE_RX_PIN 2
#define UART_BRIDGE_BAUD   115200

// UART2 del ESP32-S3, el mismo puerto que el esquematico marca como
// ESP_TXD2/ESP_RXD2 hacia el socket del modulo C6 (Serial/UART0 queda libre
// para el Monitor Serie/USB, igual que en el P4).
HardwareSerial SerialC6(2);

// El idioma que se manda en cada lanzamiento/jugada ya NO se guarda aqui:
// viene de ui_idioma_dispositivo.get() (ver ui_idioma_dispositivo.h/.c),
// que es lo que actualizan los botones ESPAÑOL/SPANISH e INGLES/ENGLISH
// de ui_DISPOSITIVOS_E_IDIOMA.c / ui_DISPOSITIVOS_E_IDIOMA_EN.c. Se
// mantiene la MISMA convencion de siempre: 0 = Espanol, 1 = Ingles.

// Guarda que TIPO se presiono, mientras se espera a que se presione la
// UBICACION. TIPO_SIN_SELECCION significa "todavia no se ha elegido
// ningun tipo".
uint8_t tipoSeleccionado = TIPO_SIN_SELECCION;

// Guardan el ultimo combo enviado con exito, para poder repetirlo con el
// boton "Repetir ultimo lanzamiento" sin tener que volver a tocar los dos
// botones.
uint8_t ultimoTipoEnviado = TIPO_SIN_SELECCION;
uint8_t ultimaUbicacionEnviada = 0;

// Guarda el texto de la ultima jugada enviada con exito (pantalla
// ui_Estrategia_defensiva_), para el boton "Repetir jugada".
char ultimaJugadaTexto[LONGITUD_MAX_JUGADA + 1] = "";
bool hayJugadaPrevia = false;

// Inicializa el puerto UART hacia el modulo C6. Reemplaza al viejo
// espnow_init() (ya no hay WiFi/ESP-NOW en esta pantalla).
void uartBridgeInit() {
  SerialC6.begin(UART_BRIDGE_BAUD, SERIAL_8N1, UART_BRIDGE_RX_PIN, UART_BRIDGE_TX_PIN);
  Serial.print("Puente UART2 hacia modulo C6 listo en TX=GPIO");
  Serial.print(UART_BRIDGE_TX_PIN);
  Serial.print(" RX=GPIO");
  Serial.print(UART_BRIDGE_RX_PIN);
  Serial.print(" @ ");
  Serial.print(UART_BRIDGE_BAUD);
  Serial.println(" baud");
}

// Mismo calculo de checksum que calcular_checksum() en uart_bridge.c (P4).
uint8_t calcularChecksum(uint8_t tipo, uint8_t len, const uint8_t *payload) {
  uint8_t chk = tipo ^ len;
  for (uint8_t i = 0; i < len; i++) {
    chk ^= payload[i];
  }
  return chk;
}

// Arma y envia una trama completa por UART hacia el modulo C6. Equivalente
// Arduino de uart_bridge_send_frame() del P4.
bool uartBridgeSendFrame(uint8_t tipo, const uint8_t *payload, uint8_t len) {
  if (len > MAX_PAYLOAD) {
    Serial.println("Error: payload demasiado grande para la trama UART");
    return false;
  }

  uint8_t frame[3 + MAX_PAYLOAD + 2];
  size_t idx = 0;

  frame[idx++] = FRAME_START;
  frame[idx++] = tipo;
  frame[idx++] = len;
  memcpy(&frame[idx], payload, len);
  idx += len;
  frame[idx++] = calcularChecksum(tipo, len, payload);
  frame[idx++] = FRAME_END;

  size_t escritos = SerialC6.write(frame, idx);
  if (escritos != idx) {
    Serial.print("Error enviando trama UART: escritos ");
    Serial.print(escritos);
    Serial.print(" de ");
    Serial.println((int)idx);
    return false;
  }

  Serial.print("Trama UART enviada (tipo=0x");
  Serial.print(tipo, HEX);
  Serial.print(", ");
  Serial.print(len);
  Serial.println(" bytes de payload)");
  return true;
}

// Manda al C6 el comando de encender (1) / apagar (0) el Wi-Fi. Lo llama
// wifi_pantalla_set() (ui_wifi_estado.c) cuando cambia el switch de Wi-Fi.
extern "C" void enviarEstadoWifi(uint8_t encendido) {
  uint8_t payload = encendido ? 1 : 0;
  Serial.print("Enviando estado Wi-Fi al C6: ");
  Serial.println(payload ? "ON" : "OFF");
  uartBridgeSendFrame(UART_MSG_WIFI, &payload, 1);
}

// Manda al C6 el comando de encender (1) / apagar (0) el Bluetooth. Lo llama
// bluetooth_pantalla_set() (ui_bluetooth_estado.c) cuando cambia el switch.
extern "C" void enviarEstadoBluetooth(uint8_t encendido) {
  uint8_t payload = encendido ? 1 : 0;
  Serial.print("Enviando estado Bluetooth al C6: ");
  Serial.println(payload ? "ON" : "OFF");
  uartBridgeSendFrame(UART_MSG_BLUETOOTH, &payload, 1);
}

// Marca el receptor de esa fila como conectado (circulo verde en la pantalla
// DISPOSITIVOS E IDIOMA). Definida en idioma_receptores.c.
extern "C" void idioma_receptor_latido(uint8_t fila);

// Procesa una trama completa y valida que llego del C6.
void procesarTramaC6(uint8_t tipo, const uint8_t *payload, uint8_t len) {
  if (tipo == UART_MSG_RECEPTOR_ESTADO && len == 1) {
    idioma_receptor_latido(payload[0]);
  }
  // Otros tipos (p. ej. 0x01 = dato entrante de un receptor) no se usan aqui.
}

// Lee lo que llega del modulo C6. Dos tipos de contenido comparten la linea:
//   - Tramas binarias [0xAA][tipo][len][payload][checksum][0x55] (latidos...)
//   - Texto de diagnostico del C6 ("ACK_C6", "WIFI_ON", logs), que es ASCII
//     (< 0x80) y por eso nunca se confunde con FRAME_START (0xAA).
// Es una maquina de estados no bloqueante: se llama en cada loop().
enum EstadoRxC6 { RX_INICIO, RX_TIPO, RX_LEN, RX_PAYLOAD, RX_CHK, RX_FIN };

void leerRespuestaC6() {
  static EstadoRxC6 estado = RX_INICIO;
  static uint8_t rxTipo = 0, rxLen = 0, rxIdx = 0, rxChk = 0;
  static uint8_t rxPayload[MAX_PAYLOAD];
  static bool textoActivo = false;

  while (SerialC6.available()) {
    uint8_t b = (uint8_t)SerialC6.read();

    switch (estado) {
      case RX_INICIO:
        if (b == FRAME_START) {
          if (textoActivo) { Serial.println(); textoActivo = false; }
          estado = RX_TIPO;
        } else {
          if (!textoActivo) { Serial.print("Recibido del C6: "); textoActivo = true; }
          Serial.write(b);
          if (b == '\n') textoActivo = false;
        }
        break;

      case RX_TIPO:
        rxTipo = b;
        estado = RX_LEN;
        break;

      case RX_LEN:
        rxLen = b;
        rxIdx = 0;
        if (rxLen > MAX_PAYLOAD) { estado = RX_INICIO; }          // trama invalida
        else estado = (rxLen == 0) ? RX_CHK : RX_PAYLOAD;
        break;

      case RX_PAYLOAD:
        rxPayload[rxIdx++] = b;
        if (rxIdx >= rxLen) estado = RX_CHK;
        break;

      case RX_CHK:
        rxChk = b;
        estado = RX_FIN;
        break;

      case RX_FIN:
        if (b == FRAME_END && rxChk == calcularChecksum(rxTipo, rxLen, rxPayload)) {
          procesarTramaC6(rxTipo, rxPayload, rxLen);
        }
        estado = RX_INICIO;   // trama buena o mala: se vuelve a esperar inicio
        break;
    }
  }
}

// Funcion interna que arma el paquete con idioma+tipo+ubicacion y lo envia
// como trama UART_MSG_LANZAMIENTO. La usan seleccionarUbicacion() y
// repetirUltimoLanzamiento().
void enviarLanzamiento(uint8_t tipo, uint8_t ubicacion) {
  datosLanzamiento.idioma = (uint8_t)idioma_dispositivo_get();
  datosLanzamiento.tipoLanzamiento = tipo;
  datosLanzamiento.ubicacion = ubicacion;

  Serial.print("Enviando lanzamiento -> idioma: ");
  Serial.print(datosLanzamiento.idioma);
  Serial.print(" | tipo: ");
  Serial.print(tipo);
  Serial.print(" | ubicacion: ");
  Serial.println(ubicacion);

  uartBridgeSendFrame(UART_MSG_LANZAMIENTO, (uint8_t *)&datosLanzamiento, sizeof(datosLanzamiento));
}

// Le dice a los receptores en que idioma reproducir los audios (0=ES, 1=EN).
// Usa el mismo paquete de 3 bytes (pitch_message_t) que Jugadores.ino ya
// interpreta; el C6 lo reenvia tal cual por ESP-NOW. El receptor lo guarda
// en flash. Llamar desde los botones ESPANOL/INGLES de las pantallas
// DISPOSITIVOS E IDIOMA (ES y EN).
extern "C" void enviarIdiomaReceptor(uint8_t idioma) {
  datosLanzamiento.idioma = idioma;
  datosLanzamiento.tipoLanzamiento = COMANDO_IDIOMA_RECEPTOR;
  datosLanzamiento.ubicacion = 0;

  Serial.print("Enviando idioma a los receptores: ");
  Serial.println(idioma);

  uartBridgeSendFrame(UART_MSG_LANZAMIENTO, (uint8_t *)&datosLanzamiento, sizeof(datosLanzamiento));
}

// Igual que enviarIdiomaReceptor(), pero SOLO para el receptor de esa fila
// de la pantalla DISPOSITIVOS E IDIOMA (0..3). La tabla de MAC vive en el
// C6 (receiver_macs[] en main.c del puente): aqui solo se manda el indice
// de fila + el mismo pitch_message_t de 3 bytes que ya entiende Jugadores.ino.
extern "C" void enviarIdiomaReceptorA(uint8_t fila, uint8_t idioma) {
  pitch_message_t msg;
  msg.idioma = idioma;
  msg.tipoLanzamiento = COMANDO_IDIOMA_RECEPTOR;
  msg.ubicacion = 0;

  uint8_t payload[1 + sizeof(pitch_message_t)];
  payload[0] = fila;
  memcpy(payload + 1, &msg, sizeof(msg));

  Serial.print("Enviando idioma ");
  Serial.print(idioma);
  Serial.print(" al receptor de la fila ");
  Serial.println(fila);

  uartBridgeSendFrame(UART_MSG_A_RECEPTOR, payload, sizeof(payload));
}

// Llamar desde el evento "value changed" del Roller de idioma en
// ui_DISPOSITIVOS_E_IDIOMA.c, pasando el indice seleccionado (0=Espanol,
// 1=Ingles, 2=Italiano, 3=Japones). Guarda el idioma para que se use en el
// PROXIMO lanzamiento que se envie, y ademas manda un mensaje inmediato con
// tipoLanzamiento=TIPO_SIN_SELECCION para que el receptor actualice su
// idioma actual sin tener que esperar a un lanzamiento (y sin que lo
// confunda con una jugada real).
// NOTA: ya no la usa un Roller (esa pantalla ahora tiene botones ES/EN que
// llaman directo a idioma_dispositivo_set()), pero se deja disponible por
// si algo mas la necesita; internamente usa la misma fuente de verdad.
extern "C" void seleccionarIdioma(uint8_t idiomaId) {
  idioma_dispositivo_set((idioma_dispositivo_t)idiomaId);

  Serial.print("Idioma seleccionado: ");
  Serial.println(idiomaId);

  datosLanzamiento.idioma = (uint8_t)idioma_dispositivo_get();
  datosLanzamiento.tipoLanzamiento = TIPO_SIN_SELECCION; // "solo idioma"
  datosLanzamiento.ubicacion = 0;

  uartBridgeSendFrame(UART_MSG_LANZAMIENTO, (uint8_t *)&datosLanzamiento, sizeof(datosLanzamiento));
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
// habia un tipo seleccionado, arma y envia el mensaje completo por UART.
extern "C" void seleccionarUbicacion(uint8_t ubicacionId) {
  if (tipoSeleccionado == TIPO_SIN_SELECCION) {
    Serial.println("Selecciona primero un tipo de lanzamiento");
    return;
  }

  enviarLanzamiento(tipoSeleccionado, ubicacionId);

  ultimoTipoEnviado = tipoSeleccionado;
  ultimaUbicacionEnviada = ubicacionId;

  // Se limpia la seleccion para que el siguiente lanzamiento empiece de cero
  tipoSeleccionado = TIPO_SIN_SELECCION;
}

// Llamar desde el boton "Cancelar lanzamiento": borra el tipo que se
// hubiera presionado Y le avisa al receptor (con COMANDO_CANCELAR, en una
// trama UART_MSG_CANCELAR) para que reproduzca un audio de "cancelado".
extern "C" void cancelarLanzamiento() {
  tipoSeleccionado = TIPO_SIN_SELECCION;
  Serial.println("Seleccion cancelada");

  datosLanzamiento.idioma = (uint8_t)idioma_dispositivo_get();
  datosLanzamiento.tipoLanzamiento = COMANDO_CANCELAR;
  datosLanzamiento.ubicacion = 0;

  Serial.println("Enviando aviso de cancelacion por UART");

  uartBridgeSendFrame(UART_MSG_CANCELAR, (uint8_t *)&datosLanzamiento, sizeof(datosLanzamiento));
}

// Llamar desde el boton "Repetir ultimo lanzamiento": vuelve a enviar el
// ultimo combo tipo+ubicacion que se envio con exito.
extern "C" void repetirUltimoLanzamiento() {
  if (ultimoTipoEnviado == TIPO_SIN_SELECCION) {
    Serial.println("Todavia no hay un lanzamiento previo para repetir");
    return;
  }
  enviarLanzamiento(ultimoTipoEnviado, ultimaUbicacionEnviada);
}

// ---- Jugadas de texto libre (pantalla ui_Estrategia_defensiva_) ----
// Equivalente Arduino de esp_now_send_jugada_texto() del P4: en vez de
// idioma+tipo+ubicacion, el payload es idioma (1 byte) + el texto tal
// cual, sin pitch_message_t. El receptor (Jugadores.ino) reconoce la
// jugada comparando ese texto letra por letra contra su tabla
// TEXTOS_JUGADAS_ES/_EN, asi que el texto que se mande aqui tiene que
// coincidir EXACTO con una entrada de esa tabla.
extern "C" void enviarJugadaTexto(const char *texto) {
  if (texto == NULL) return;

  size_t len = strlen(texto);
  if (len > LONGITUD_MAX_JUGADA) {
    Serial.println("Texto de jugada demasiado largo, se ignora");
    return;
  }

  uint8_t payload[LONGITUD_MAX_JUGADA + 1];
  payload[0] = (uint8_t)idioma_dispositivo_get();
  memcpy(&payload[1], texto, len);

  Serial.print("Enviando jugada -> idioma: ");
  Serial.print(payload[0]);
  Serial.print(" | texto: ");
  Serial.println(texto);

  uartBridgeSendFrame(UART_MSG_JUGADA, payload, (uint8_t)(len + 1));

  strncpy(ultimaJugadaTexto, texto, LONGITUD_MAX_JUGADA);
  ultimaJugadaTexto[LONGITUD_MAX_JUGADA] = '\0';
  hayJugadaPrevia = true;
}

// Llamar desde el boton "Cancelar jugada": avisa al receptor con
// COMANDO_CANCELAR_JUGADA (trama UART_MSG_CANCELAR, 3 bytes), igual que
// hace esp_now_send_cancelar_jugada() en el P4.
extern "C" void cancelarJugada() {
  datosLanzamiento.idioma = (uint8_t)idioma_dispositivo_get();
  datosLanzamiento.tipoLanzamiento = COMANDO_CANCELAR_JUGADA;
  datosLanzamiento.ubicacion = 0;

  Serial.println("Enviando aviso de jugada cancelada por UART");

  uartBridgeSendFrame(UART_MSG_CANCELAR, (uint8_t *)&datosLanzamiento, sizeof(datosLanzamiento));
}

// Llamar desde el boton "Repetir jugada": vuelve a enviar la ultima
// jugada de texto que se envio con exito.
extern "C" void repetirUltimaJugada() {
  if (!hayJugadaPrevia) {
    Serial.println("Todavia no hay una jugada previa para repetir");
    return;
  }
  enviarJugadaTexto(ultimaJugadaTexto);
}
// ================================================================================
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

  // Init puente UART hacia el modulo C6 (ESP-NOW real vive en el C6)
  uartBridgeInit();

  gfx.fillScreen(TFT_BLACK);
  // lv_demo_widgets();//Main UI interface
  ui_init();

  Serial.println( "Setup done" );
}

void loop()
{
  lv_timer_handler(); /* let the GUI do its work */
  leerRespuestaC6();  /* muestra por Serie lo que responda el modulo C6 */
  delay(5);
}
