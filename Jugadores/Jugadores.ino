/*
  ESP32C6 XIAO - Reproductor controlado por ESP-NOW
  ----------------------------------------------------------------
  Recibe por ESP-NOW un mensaje con DOS datos: el TIPO de lanzamiento
  (Recta, Curva, Slider...) y la UBICACION (Alta pegada, Medio,
  Abajo y afuera...), enviados juntos desde la pantalla (Intento1.ino)
  cuando el usuario presiona primero un boton de tipo y despues uno
  de ubicacion. Con esos dos numeros se busca en una tabla el archivo
  de audio que corresponde a esa combinacion exacta y se reproduce.

  Solo quedan 2 botones fisicos: subir y bajar volumen.

  Usa la libreria "ESP8266Audio" de Earle Philhower (single-core,
  compatible con el ESP32-C6).

  INSTALAR PRIMERO:
    Arduino IDE -> Herramientas -> Administrar Bibliotecas
    -> buscar "ESP8266Audio" (autor: Earle Philhower) -> Instalar

  Los archivos deben estar en la raiz de la SD. Por ahora solo existen
  los audios del tipo "Recta" (tipo 1), nombrados Lanzamiento1.mp3 a
  Lanzamiento9.mp3, uno por cada ubicacion (falta Lanzamiento7.mp3).
  A medida que grabes los audios de los demas tipos (Curva, Cambio,
  Slider, etc.) solo hay que agregar sus nombres en la tabla
  NOMBRES_LANZAMIENTOS mas abajo, no hay que tocar nada mas del codigo.

  CONEXIONES SD (SPI):
    Modulo SD VCC  -> 3V3
    Modulo SD GND  -> GND
    Modulo SD MISO -> D9
    Modulo SD MOSI -> D10
    Modulo SD CLK  -> D8
    Modulo SD CS   -> D6

  CONEXIONES MAX98357A (I2S):
    VIN  -> 5V (VBUS) o 3.3V-OUT
    GND  -> GND
    SD   -> sin conectar
    GAIN -> sin conectar
    DIN  -> D3
    BCLK -> D1
    LRC  -> D2

  CONEXIONES BOTONES (cada uno: un lado al pin, otro lado a GND):
    Boton subir volumen -> D0
    Boton bajar volumen -> D4
*/

#include <SPI.h> 
#include <SD.h>
#include <AudioFileSourceSD.h>
#include <AudioGeneratorMP3.h>
#include <AudioOutputI2S.h>

#include <WiFi.h>
#include <esp_now.h>

// ---- Pines SD ----
#define SD_CS   D6
#define SD_MOSI D10
#define SD_SCK  D8
#define SD_MISO D9

// ---- Pines I2S (hacia el MAX98357A) ----
#define I2S_BCLK D1
#define I2S_LRC  D2
#define I2S_DOUT D3

// ---- Pines de los botones de volumen ----
#define BOTON_VOL_SUBIR  D0
#define BOTON_VOL_BAJAR  D5

// ---- Carpetas de audio por idioma ----
// La estructura real en la SD es: /Espanol/Lanzamientos/Lanzamiento1.mp3,
// /Ingles/Lanzamientos/..., etc. El indice de este arreglo debe coincidir
// con el ID de idioma que manda la pantalla (Roller en
// ui_DISPOSITIVOS_E_IDIOMA.c): 0=Espanol 1=Ingles 2=Italiano 3=Japones.
// Si todavia no tienes audios grabados en un idioma, deja su carpeta como
// nullptr: el codigo avisara por Serial y no intentara reproducir nada raro.
#define MAX_IDIOMAS 4

// Valor especial de tipoLanzamiento que la pantalla manda cuando se
// presiona "Cancelar lanzamiento". Debe ser el MISMO numero que
// COMANDO_CANCELAR en Intento1.ino.
#define COMANDO_CANCELAR 200
const char* CARPETAS_IDIOMA[MAX_IDIOMAS] = {
  "/Espanol/Lanzamientos",   // 0 = Espanol
  "/Ingles/Lanzamientos",                    // 1 = Ingles   (agregar carpeta cuando existan los audios)
  "/Italiano/Lanzamientos",                    // 2 = Italiano (agregar carpeta cuando existan los audios)
  "/Japones/Lanzamientos",                    // 3 = Japones  (agregar carpeta cuando existan los audios)
};

// Idioma actualmente seleccionado (llega desde la pantalla). Empieza en 0
// (Espanol) para que el aparato funcione aunque todavia no hayas tocado el
// Roller de idioma.
uint8_t idiomaActual = 0;

// ---- Tabla de audios: [tipoLanzamiento][ubicacion] -> nombre del archivo ----
// Debe usar EXACTAMENTE los mismos IDs de tipo y de ubicacion que la pantalla
// (Intento1.ino):
//   TIPOS:  1=Recta  2=Curva  3=Cambio  4=Recta 2 costuras  5=Slider
//           6=Screwball  7=Spitter  8=Circle Change  9=Sinker  10=Cutter
//           11=Tenedor
//   UBICACIONES: 1=Alta pegada  2=Alta en el medio  3=Alta y afuera
//           4=Pegada y en el medio  5=Medio  6=Afuera y en el medio
//           7=Pegada y abajo  8=En el medio y abajo  9=Abajo y afuera
//
// El indice 0 (de tipo y de ubicacion) no se usa, se deja vacio para poder
// indexar directamente con el numero real (1 a 11, 1 a 9) sin restar 1.
// Todo lo que quede en NULL significa "todavia no hay audio grabado para
// esa combinacion".
// IMPORTANTE: aqui solo va el NOMBRE del archivo (sin la carpeta); la
// carpeta CARPETA_LANZAMIENTOS se le agrega automaticamente en
// reproducirLanzamiento(), asi que si luego mueves los audios a otra
// carpeta, solo cambias CARPETA_LANZAMIENTOS y no esta tabla.
#define MAX_TIPOS       11
#define MAX_UBICACIONES 9

const char* NOMBRES_LANZAMIENTOS[MAX_TIPOS + 1][MAX_UBICACIONES + 1] = {};

// Llena la tabla de arriba. Se llama una sola vez desde setup().
// Para agregar un tipo nuevo cuando grabes sus audios, copia el bloque de
// "Recta" y cambia el primer indice (el tipo) y los nombres de archivo.
void configurarNombresAudios() {
  // ---- Tipo 1: Recta ----
  NOMBRES_LANZAMIENTOS[1][1] = "Lanzamiento1.mp3"; // Recta + Alta pegada
  NOMBRES_LANZAMIENTOS[1][2] = "Lanzamiento2.mp3"; // Recta + Alta en el medio
  NOMBRES_LANZAMIENTOS[1][3] = "Lanzamiento3.mp3"; // Recta + Alta y afuera
  NOMBRES_LANZAMIENTOS[1][4] = "Lanzamiento4.mp3"; // Recta + Pegada y en el medio
  NOMBRES_LANZAMIENTOS[1][5] = "Lanzamiento5.mp3"; // Recta + Medio
  NOMBRES_LANZAMIENTOS[1][6] = "Lanzamiento6.mp3"; // Recta + Afuera y en el medio
  NOMBRES_LANZAMIENTOS[1][7] = "Lanzamiento7.mp3"; //(Recta + Pegada y abajo)
  NOMBRES_LANZAMIENTOS[1][8] = "Lanzamiento8.mp3"; // Recta + En el medio y abajo
  NOMBRES_LANZAMIENTOS[1][9] = "Lanzamiento9.mp3"; // Recta + Abajo y afuera
  NOMBRES_LANZAMIENTOS[2][1] = "Lanzamiento10.mp3";
  NOMBRES_LANZAMIENTOS[2][2] = "Lanzamiento11.mp3";
  NOMBRES_LANZAMIENTOS[2][3] = "Lanzamiento12.mp3";
  NOMBRES_LANZAMIENTOS[2][4] = "Lanzamiento13.mp3";
  NOMBRES_LANZAMIENTOS[2][5] = "Lanzamiento14.mp3";  
  NOMBRES_LANZAMIENTOS[2][6] = "Lanzamiento15.mp3";  
  NOMBRES_LANZAMIENTOS[2][7] = "Lanzamiento16.mp3";  
  NOMBRES_LANZAMIENTOS[2][8] = "Lanzamiento17.mp3";  
  NOMBRES_LANZAMIENTOS[2][9] = "Lanzamiento18.mp3";  
  NOMBRES_LANZAMIENTOS[3][1] = "Lanzamiento19.mp3";  
  NOMBRES_LANZAMIENTOS[3][2] = "Lanzamiento20.mp3";  
  NOMBRES_LANZAMIENTOS[3][3] = "Lanzamiento21.mp3";  
  NOMBRES_LANZAMIENTOS[3][4] = "Lanzamiento22.mp3";  
  NOMBRES_LANZAMIENTOS[3][5] = "Lanzamiento23.mp3";  
  NOMBRES_LANZAMIENTOS[3][6] = "Lanzamiento24.mp3";  
  NOMBRES_LANZAMIENTOS[3][7] = "Lanzamiento25.mp3";  
  NOMBRES_LANZAMIENTOS[3][8] = "Lanzamiento26.mp3";  
  NOMBRES_LANZAMIENTOS[3][9] = "Lanzamiento27.mp3";  
  NOMBRES_LANZAMIENTOS[4][1] = "Lanzamiento28.mp3";  
  NOMBRES_LANZAMIENTOS[4][2] = "Lanzamiento29.mp3";  
  NOMBRES_LANZAMIENTOS[4][3] = "Lanzamiento30.mp3";  
  NOMBRES_LANZAMIENTOS[4][4] = "Lanzamiento31.mp3";  
  NOMBRES_LANZAMIENTOS[4][5] = "Lanzamiento32.mp3";  
  NOMBRES_LANZAMIENTOS[4][6] = "Lanzamiento33.mp3";  
  NOMBRES_LANZAMIENTOS[4][7] = "Lanzamiento34.mp3";  
  NOMBRES_LANZAMIENTOS[4][8] = "Lanzamiento35.mp3";  
  NOMBRES_LANZAMIENTOS[4][9] = "Lanzamiento36.mp3"; 
  NOMBRES_LANZAMIENTOS[5][1] = "Lanzamiento37.mp3";  
  NOMBRES_LANZAMIENTOS[5][2] = "Lanzamiento38.mp3";  
  NOMBRES_LANZAMIENTOS[5][3] = "Lanzamiento39.mp3";  
  NOMBRES_LANZAMIENTOS[5][4] = "Lanzamiento40.mp3";  
  NOMBRES_LANZAMIENTOS[5][5] = "Lanzamiento41.mp3";  
  NOMBRES_LANZAMIENTOS[5][6] = "Lanzamiento42.mp3";  
  NOMBRES_LANZAMIENTOS[5][7] = "Lanzamiento43.mp3";  
  NOMBRES_LANZAMIENTOS[5][8] = "Lanzamiento44.mp3";  
  NOMBRES_LANZAMIENTOS[5][9] = "Lanzamiento45.mp3";
  NOMBRES_LANZAMIENTOS[6][1] = "Lanzamiento46.mp3";  
  NOMBRES_LANZAMIENTOS[6][2] = "Lanzamiento47.mp3";  
  NOMBRES_LANZAMIENTOS[6][3] = "Lanzamiento48.mp3";  
  NOMBRES_LANZAMIENTOS[6][4] = "Lanzamiento49.mp3";  
  NOMBRES_LANZAMIENTOS[6][5] = "Lanzamiento50.mp3";  
  NOMBRES_LANZAMIENTOS[6][6] = "Lanzamiento51.mp3";  
  NOMBRES_LANZAMIENTOS[6][7] = "Lanzamiento52.mp3";  
  NOMBRES_LANZAMIENTOS[6][8] = "Lanzamiento53.mp3";  
  NOMBRES_LANZAMIENTOS[6][9] = "Lanzamiento54.mp3";
  NOMBRES_LANZAMIENTOS[7][1] = "Lanzamiento55.mp3";  
  NOMBRES_LANZAMIENTOS[7][2] = "Lanzamiento56.mp3";  
  NOMBRES_LANZAMIENTOS[7][3] = "Lanzamiento57.mp3";  
  NOMBRES_LANZAMIENTOS[7][4] = "Lanzamiento58.mp3";  
  NOMBRES_LANZAMIENTOS[7][5] = "Lanzamiento59.mp3";  
  NOMBRES_LANZAMIENTOS[7][6] = "Lanzamiento60.mp3";  
  NOMBRES_LANZAMIENTOS[7][7] = "Lanzamiento61.mp3";  
  NOMBRES_LANZAMIENTOS[7][8] = "Lanzamiento62.mp3";  
  NOMBRES_LANZAMIENTOS[7][9] = "Lanzamiento63.mp3";
  NOMBRES_LANZAMIENTOS[8][1] = "Lanzamiento64.mp3";  
  NOMBRES_LANZAMIENTOS[8][2] = "Lanzamiento65.mp3";  
  NOMBRES_LANZAMIENTOS[8][3] = "Lanzamiento66.mp3";  
  NOMBRES_LANZAMIENTOS[8][4] = "Lanzamiento67.mp3";  
  NOMBRES_LANZAMIENTOS[8][5] = "Lanzamiento68.mp3";  
  NOMBRES_LANZAMIENTOS[8][6] = "Lanzamiento69.mp3";  
  NOMBRES_LANZAMIENTOS[8][7] = "Lanzamiento70.mp3";  
  NOMBRES_LANZAMIENTOS[8][8] = "Lanzamiento71.mp3";  
  NOMBRES_LANZAMIENTOS[8][9] = "Lanzamiento72.mp3";
  NOMBRES_LANZAMIENTOS[9][1] = "Lanzamiento73.mp3";  
  NOMBRES_LANZAMIENTOS[9][2] = "Lanzamiento74.mp3";  
  NOMBRES_LANZAMIENTOS[9][3] = "Lanzamiento75.mp3";  
  NOMBRES_LANZAMIENTOS[9][4] = "Lanzamiento76.mp3";  
  NOMBRES_LANZAMIENTOS[9][5] = "Lanzamiento77.mp3";  
  NOMBRES_LANZAMIENTOS[9][6] = "Lanzamiento78.mp3";  
  NOMBRES_LANZAMIENTOS[9][7] = "Lanzamiento79.mp3";  
  NOMBRES_LANZAMIENTOS[9][8] = "Lanzamiento80.mp3";  
  NOMBRES_LANZAMIENTOS[9][9] = "Lanzamiento81.mp3";
  NOMBRES_LANZAMIENTOS[10][1] = "Lanzamiento82.mp3";  
  NOMBRES_LANZAMIENTOS[10][2] = "Lanzamiento83.mp3";  
  NOMBRES_LANZAMIENTOS[10][3] = "Lanzamiento84.mp3";  
  NOMBRES_LANZAMIENTOS[10][4] = "Lanzamiento85.mp3";  
  NOMBRES_LANZAMIENTOS[10][5] = "Lanzamiento86.mp3";  
  NOMBRES_LANZAMIENTOS[10][6] = "Lanzamiento87.mp3";  
  NOMBRES_LANZAMIENTOS[10][7] = "Lanzamiento88.mp3";  
  NOMBRES_LANZAMIENTOS[10][8] = "Lanzamiento89.mp3";  
  NOMBRES_LANZAMIENTOS[10][9] = "Lanzamiento90.mp3";
  NOMBRES_LANZAMIENTOS[11][1] = "Lanzamiento91.mp3";  
  NOMBRES_LANZAMIENTOS[11][2] = "Lanzamiento92.mp3";  
  NOMBRES_LANZAMIENTOS[11][3] = "Lanzamiento93.mp3";  
  NOMBRES_LANZAMIENTOS[11][4] = "Lanzamiento94.mp3";  
  NOMBRES_LANZAMIENTOS[11][5] = "Lanzamiento95.mp3";  
  NOMBRES_LANZAMIENTOS[11][6] = "Lanzamiento96.mp3";  
  NOMBRES_LANZAMIENTOS[11][7] = "Lanzamiento97.mp3";  
  NOMBRES_LANZAMIENTOS[11][8] = "Lanzamiento98.mp3";  
  NOMBRES_LANZAMIENTOS[11][9] = "Lanzamiento99.mp3";
  // ---- Tipos 2 a 11 (Curva, Cambio, Recta 2 costuras, Slider, Screwball,
  //      Spitter, Circle Change, Sinker, Cutter, Tenedor) ----
  // Agrega aqui sus 9 lineas cada uno cuando tengas los audios, por ejemplo:
  // NOMBRES_LANZAMIENTOS[2][1] = "/Curva_AltaPegada.mp3";
  // NOMBRES_LANZAMIENTOS[2][2] = "/Curva_AltaMedio.mp3";
  // ...
}

AudioFileSourceSD *fuente = nullptr;
AudioGeneratorMP3  *mp3    = nullptr;
AudioOutputI2S     *salida = nullptr;

// Para el anti-rebote (debounce) de cada boton
unsigned long ultimoPressSubir = 0;
unsigned long ultimoPressBajar = 0;
const unsigned long DEBOUNCE_MS = 200;

// Volumen actual (SetGain admite valores desde 0.0; evitamos pasar de 2.0 para no distorsionar)
float volumenActual = 1.1;
const float PASO_VOLUMEN = 0.1;
const float VOLUMEN_MIN = 0.0;
const float VOLUMEN_MAX = 2.0;

// ===================== ESP-NOW =====================
// Debe coincidir EXACTAMENTE con la estructura usada en la pantalla (Intento1.ino)
typedef struct {
  uint8_t idioma;          // 0-3
  uint8_t tipoLanzamiento; // 1-11 (0 = mensaje "solo idioma", no reproducir nada)
  uint8_t ubicacion;       // 1-9  (0 = mensaje "solo idioma", no reproducir nada)
} pitch_message_t;

void detenerReproduccion() {
  if (mp3 != nullptr && mp3->isRunning()) {
    mp3->stop();
  }
  if (fuente != nullptr) {
    delete fuente;
    fuente = nullptr;
  }
}

void reproducirCancion(const char* archivo) {
  Serial.print("Reproduciendo: ");
  Serial.println(archivo);

  if (!SD.exists(archivo)) {
    Serial.println("ERROR: ese archivo no existe en la SD");
    return;
  }

  detenerReproduccion();

  fuente = new AudioFileSourceSD(archivo);
  mp3->begin(fuente, salida);
}

// Busca en la tabla el audio que corresponde a la combinacion tipo+ubicacion
// recibida (dentro de la carpeta del idioma actual) y lo reproduce. Si esa
// combinacion todavia no tiene audio asignado, o el idioma actual todavia
// no tiene carpeta configurada, avisa por Serial y no hace nada.
void reproducirLanzamiento(uint8_t tipo, uint8_t ubicacion) {
  if (tipo < 1 || tipo > MAX_TIPOS || ubicacion < 1 || ubicacion > MAX_UBICACIONES) {
    Serial.println("ERROR: tipo o ubicacion fuera de rango, se ignora");
    return;
  }

  if (idiomaActual >= MAX_IDIOMAS || CARPETAS_IDIOMA[idiomaActual] == nullptr) {
    Serial.print("Todavia no hay audios para el idioma ");
    Serial.println(idiomaActual);
    return;
  }

  const char* nombreArchivo = NOMBRES_LANZAMIENTOS[tipo][ubicacion];

  if (nombreArchivo == nullptr) {
    Serial.print("Todavia no hay audio para tipo=");
    Serial.print(tipo);
    Serial.print(" ubicacion=");
    Serial.println(ubicacion);
    return;
  }

  // Arma la ruta completa: carpeta del idioma actual + "/" + nombre del archivo
  String rutaCompleta = String(CARPETAS_IDIOMA[idiomaActual]) + "/" + nombreArchivo;
  reproducirCancion(rutaCompleta.c_str());
}

// Reproduce el audio que avisa que se cancelo el lanzamiento. Busca el
// archivo "Cancelar.mp3" dentro de la carpeta del idioma actual (por
// ejemplo /Espanol/Lanzamientos/Cancelar.mp3). Debes grabar y subir ese
// archivo con ese nombre exacto en cada carpeta de idioma que uses.
void reproducirCancelacion() {
  if (idiomaActual >= MAX_IDIOMAS || CARPETAS_IDIOMA[idiomaActual] == nullptr) {
    Serial.print("Todavia no hay audios para el idioma ");
    Serial.println(idiomaActual);
    return;
  }

  String rutaCompleta = String(CARPETAS_IDIOMA[idiomaActual]) + "/Cancelar.mp3";
  reproducirCancion(rutaCompleta.c_str());
}

// Callback que se ejecuta cada vez que llega un mensaje ESP-NOW
void onDataRecv(const esp_now_recv_info_t *info, const uint8_t *incomingData, int len) {
  if (len != sizeof(pitch_message_t)) {
    Serial.println("Mensaje ESP-NOW con tamano inesperado, se ignora");
    return;
  }

  pitch_message_t incoming;
  memcpy(&incoming, incomingData, sizeof(incoming));

  Serial.print("Recibido -> idioma: ");
  Serial.print(incoming.idioma);
  Serial.print(" | tipo: ");
  Serial.print(incoming.tipoLanzamiento);
  Serial.print(" | ubicacion: ");
  Serial.println(incoming.ubicacion);

  // El idioma siempre se guarda, venga o no acompañado de un lanzamiento
  idiomaActual = incoming.idioma;

  // tipo=0 y ubicacion=0 es el mensaje especial que la pantalla manda solo
  // para avisar que cambiaste de idioma (por ejemplo al mover el Roller),
  // sin que eso signifique que hay que reproducir nada todavia.
  if (incoming.tipoLanzamiento == 0 && incoming.ubicacion == 0) {
    Serial.println("Solo se actualizo el idioma, no se reproduce nada");
    return;
  }

  // COMANDO_CANCELAR: se presiono "Cancelar lanzamiento" en la pantalla.
  // Se reproduce un audio especial en vez de buscar en la tabla de tipos.
  if (incoming.tipoLanzamiento == COMANDO_CANCELAR) {
    Serial.println("Lanzamiento cancelado, reproduciendo aviso");
    reproducirCancelacion();
    return;
  }

  reproducirLanzamiento(incoming.tipoLanzamiento, incoming.ubicacion);
}

void espnow_init() {
  WiFi.mode(WIFI_STA);

  if (esp_now_init() != ESP_OK) {
    Serial.println("Error iniciando ESP-NOW");
    return;
  }

  esp_now_register_recv_cb(onDataRecv);

  Serial.print("Direccion MAC de este receptor: ");
  Serial.println(WiFi.macAddress());
}
// =====================================================

void setup() {
  Serial.begin(115200);
  delay(1000);

  // --- Botones de volumen con pull-up interno ---
  pinMode(BOTON_VOL_SUBIR, INPUT_PULLUP);
  pinMode(BOTON_VOL_BAJAR, INPUT_PULLUP);

  // --- Iniciar SD ---
  SPI.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
  if (!SD.begin(SD_CS, SPI, 20000000)) {
    Serial.println("Error: no se detecto la SD");
    return;
  }
  Serial.println("SD detectada correctamente");

  // --- Iniciar I2S / amplificador ---
  salida = new AudioOutputI2S();
  salida->SetPinout(I2S_BCLK, I2S_LRC, I2S_DOUT);
  salida->SetGain(volumenActual);

  mp3 = new AudioGeneratorMP3();

  // --- Llenar la tabla de nombres de audio (tipo x ubicacion) ---
  configurarNombresAudios();

  // --- Iniciar ESP-NOW ---
  espnow_init();

  Serial.println("Listo. Esperando comandos de la pantalla...");
}

void loop() {
  if (mp3 != nullptr && mp3->isRunning()) {
    if (!mp3->loop()) {
      mp3->stop();
      Serial.println("Cancion terminada.");
    }
  }

  unsigned long ahora = millis();

  // Subir volumen
  if (digitalRead(BOTON_VOL_SUBIR) == LOW && (ahora - ultimoPressSubir) > DEBOUNCE_MS) {
    ultimoPressSubir = ahora;
    volumenActual += PASO_VOLUMEN;
    if (volumenActual > VOLUMEN_MAX) volumenActual = VOLUMEN_MAX;
    salida->SetGain(volumenActual);
    Serial.print("Volumen: ");
    Serial.println(volumenActual);
  }

  // Bajar volumen
  if (digitalRead(BOTON_VOL_BAJAR) == LOW && (ahora - ultimoPressBajar) > DEBOUNCE_MS) {
    ultimoPressBajar = ahora;
    volumenActual -= PASO_VOLUMEN;
    if (volumenActual < VOLUMEN_MIN) volumenActual = VOLUMEN_MIN;
    salida->SetGain(volumenActual);
    Serial.print("Volumen: ");
    Serial.println(volumenActual);
  }
}
