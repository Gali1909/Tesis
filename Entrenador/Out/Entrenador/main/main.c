#include "main.h"
#include "ui.h"
#include "jugadas_dynamic.h"
#include "alineacion_dynamic.h"
#include "alineacion_dynamic_EN.h"
#include "banca_bullpen_dynamic.h"
#include "Analisis_dynamic.h"
#include "esp_now_comm.h"
#include "esp_lvgl_port.h"
#include "ajustes_dynamic.h"
//#include "Lanzadores_dynamic.h"
#include "wifi_manager.h"
/* Inclusion para NVS (algunos componentes internos de ESP-IDF la usan) */
#include "nvs_flash.h"
/* WDT: para desvincular temporalmente IDLE0 durante ui_init() */
#include "esp_task_wdt.h"
#include "esp_timer.h"
#include "pitch_filter.h"
#include "perfil_lanzador_ui.h"
#include "perfil_lanzador_rx.h"
/*---------------------------------------------------------------
 * Power / handle storage
 *--------------------------------------------------------------*/

/* LDO channels that power the LCD and the IO domain. */
static esp_ldo_channel_handle_t ldo3 = NULL;
static esp_ldo_channel_handle_t ldo4 = NULL;

/*---------------------------------------------------------------
 * Initialisation helpers
 *--------------------------------------------------------------*/

/**
 * @brief Halt forever and print the failing module name every second.
 * @param module_name Name of the failing module.
 * @param err         Error code returned by the module.
 */
static void init_fail_handler(const char *module_name, esp_err_t err)
{
    while (1) {
        MAIN_ERROR("[%s] init failed: %s", module_name, esp_err_to_name(err));
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

/**
 * @brief Inicializa NVS, el puente de comunicacion UART hacia el modulo C6 externo,
 *        y el gestor de WiFi (switch de Ajustes: encender/apagar + conectar a red).
 *
 * NOTA: la senalizacion de lanzamientos/jugadas viaja por UART hacia el modulo
 * Wireless C6 externo, que maneja su propio ESP-NOW de forma independiente.
 * El WiFi que se inicializa aqui (wifi_manager) es el que usa la pantalla para
 * conectarse a una red y el que controla el switch de WiFi en Ajustes; es
 * independiente del C6 externo y del C6 onboard (esp_hosted).
 */
static void network_init(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    if (ret != ESP_OK) {
        init_fail_handler("NVS", ret);
    }

    /* Inicializar el puente UART hacia el modulo C6 externo */
    ret = esp_now_comm_init();
    if (ret != ESP_OK) {
        init_fail_handler("COMM UART", ret);
    }
    MAIN_INFO("Modulo de comunicacion de jugadas listo");

    /* Inicializar el gestor de WiFi (switch de Ajustes: encender/apagar + conectar a red) */
    ret = wifi_manager_init();
    if (ret != ESP_OK) {
        init_fail_handler("WIFI_MGR", ret);
    }
    MAIN_INFO("wifi_manager listo");
}

/**
 * @brief Bring up LDO power, I2C, touch, LCD and LED GPIO.
 */
static void system_init(void)
{
    esp_err_t err = ESP_OK;

    /* LDO3 = 2.5 V (IO domain), LDO4 = 3.3 V (panel analogue). */
    esp_ldo_channel_config_t ldo3_cof = {
        .chan_id = 3,
        .voltage_mv = 2500,
    };
    err = esp_ldo_acquire_channel(&ldo3_cof, &ldo3);
    if (err != ESP_OK) {
        init_fail_handler("ldo3", err);
    }

    esp_ldo_channel_config_t ldo4_cof = {
        .chan_id = 4,
        .voltage_mv = 3300,
    };
    err = esp_ldo_acquire_channel(&ldo4_cof, &ldo4);
    if (err != ESP_OK) {
        init_fail_handler("ldo4", err);
    }
    MAIN_INFO("LDO3 and LDO4 init success");

    /* I2C is required by the GT911 touch controller. */
    MAIN_INFO("Initializing I2C...");
    err = i2c_init();
    if (err != ESP_OK) {
        init_fail_handler("I2C", err);
    }
    MAIN_INFO("I2C init success");

    /* Touch panel (low-level GT911 driver). */
    MAIN_INFO("Initializing touch panel...");
    err = touch_init();
    if (err != ESP_OK) {
        init_fail_handler("Touch", err);
    }
    MAIN_INFO("Touch panel init success");

    /* LCD + LVGL */
    err = display_init();
    if (err != ESP_OK) {
        init_fail_handler("LCD", err);
    }
    MAIN_INFO("LCD init success");

    /* LED GPIO */
    MAIN_INFO("Initializing GPIO48 for LED...");
    err = gpio_extra_init();
    if (err != ESP_OK) {
        init_fail_handler("GPIO48", err);
    }
    gpio_extra_set_level(false);
    MAIN_INFO("LED initialized to OFF state");
}

/*---------------------------------------------------------------
 * Application entry point
 *--------------------------------------------------------------*/

void app_main(void)
{
    esp_err_t err = ESP_OK;

    MAIN_INFO("Starting application...");

    system_init();

    MAIN_INFO("System initialized successfully");

    /* Inicializar NVS, el puente de comunicacion UART y el gestor de WiFi */
    network_init();

    /* Build the SquareLine-designed UI (loads ui_Menu_principal). */
    /* ---- DIAGNOSTICO TEMPORAL: verifica la velocidad de CPU0 ----
     * 1M iteraciones deberian tardar ~10 ms. Si tarda cientos de ms o mas,
     * la pila de esta tarea sigue en memoria lenta (RAM LP, 0x5010xxxx). */
    {
        volatile uint32_t acc = 0;
        int64_t t0 = esp_timer_get_time();
        for (uint32_t i = 0; i < 1000000; i++) { acc += i; }
        MAIN_INFO("bench CPU0 (1M iter): %lld ms", (esp_timer_get_time() - t0) / 1000);
    }

    /* ui_init() mantiene CPU0 ocupado mucho tiempo: se quita IDLE0 del WDT
     * mientras dura y se vuelve a agregar al terminar. */
    TaskHandle_t idle0 = xTaskGetIdleTaskHandleForCore(0);
    esp_task_wdt_delete(idle0);
    int64_t ui_t0 = esp_timer_get_time();

    if (lvgl_port_lock(0)) { 
        ui_init(); 
        perfil_lanzador_rx_init();
        lvgl_port_unlock(); } 
     else { init_fail_handler("LVGL lock", ESP_FAIL);
         }
    esp_task_wdt_add(idle0);
    MAIN_INFO("ui_init() tardo %lld ms", (esp_timer_get_time() - ui_t0) / 1000);
    MAIN_INFO("UI created successfully");
    MAIN_INFO("Free heap: %lu bytes (min ever: %lu)", esp_get_free_heap_size(), esp_get_minimum_free_heap_size());
    
    /* Give the LVGL task a moment to render the first real frame */
    vTaskDelay(pdMS_TO_TICKS(100));
    err = set_lcd_blight(100);
    if (err != ESP_OK) {
        init_fail_handler("LCD Backlight", err);
    }
    MAIN_INFO("LCD backlight opened (brightness: 100)");

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
