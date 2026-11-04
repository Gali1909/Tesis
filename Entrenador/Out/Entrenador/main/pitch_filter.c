// pitch_filter.c
#include "pitch_filter.h"
#include "lanzamientos_dynamic.h"
#include "lanzamientos_dynamic_en.h"
#include "ui.h"
#include "esp_log.h"

static const char *TAG = "PITCH_FILTER";

#define PITCH_COUNT   14
#define MASK_TODOS    ((1u << PITCH_COUNT) - 1u)

static volatile uint16_t s_mask_pedida = MASK_TODOS;   /* escrita por la tarea UART */
static uint16_t          s_mask_aplicada = 0xFFFF;     /* solo la toca LVGL */

/* La mascara se vuelve a aplicar cuando la pantalla de lanzamientos se
 * recrea (punteros nuevos) o cuando se vuelve a entrar a ella: los botones
 * nuevos nacen sin restriccion aunque la mascara no haya cambiado. */
static lv_obj_t *s_ult_btn_es = NULL;
static lv_obj_t *s_ult_btn_en = NULL;
static bool      s_estaba_es = false;
static bool      s_estaba_en = false;

/* La app manda "slots": la posicion del tipo en su lista predeterminada
 * (tiposLanzamientoPredeterminados de database_helper.dart):
 *   0 Four-Seam, 1 Two-Seam, 2 Sinker, 3 Cutter, 4 Split-Finger, 5 Curveball,
 *   6 Slider, 7 Sweeper, 8 Changeup, 9 Circle Change, 10 Splitter,
 *   11 Forkball, 12 Knuckleball, 13 Screwball.
 * Esta tabla traduce cada slot al enum pitch_type_t de la pantalla. */
static const uint8_t s_slot_a_pitch[PITCH_COUNT] = {
    PITCH_RECTA_4C,          /* 0  Four-Seam      */
    PITCH_RECTA_2C,          /* 1  Two-Seam       */
    PITCH_SINKER,            /* 2  Sinker         */
    PITCH_CUTTER,            /* 3  Cutter         */
    PITCH_SPLITFINGER,       /* 4  Split-Finger   */
    PITCH_CURVA,             /* 5  Curveball      */
    PITCH_SLIDER,            /* 6  Slider         */
    PITCH_SWEEPER,           /* 7  Sweeper        */
    PITCH_CAMBIO_VELOCIDAD,  /* 8  Changeup       */
    PITCH_CIRCLECHANGE,      /* 9  Circle Change  */
    PITCH_SPLITTER,          /* 10 Splitter       */
    PITCH_TENEDOR,           /* 11 Forkball       */
    PITCH_NUDILLERA,         /* 12 Knuckleball    */
    PITCH_TIRABUZON          /* 13 Screwball      */
};

/* Boton de cada tipo, indexado por pitch_type_t (mismo orden del enum). */
static lv_obj_t *boton_es(int p)
{
    switch (p) {
    case PITCH_RECTA_4C:         return ui_Recta;
    case PITCH_CURVA:            return ui_Boton_Curva;
    case PITCH_CAMBIO_VELOCIDAD: return ui_Boton_CAMBIO_DE_VELOCIDAD;
    case PITCH_RECTA_2C:         return ui_Recta2;
    case PITCH_SLIDER:           return ui_Boton_SLIDER;
    case PITCH_TIRABUZON:        return ui_Boton__Tirabuzon;
    case PITCH_SINKER:           return ui_Boton_sinker;
    case PITCH_SPLITTER:         return ui_Boton__SPLITTER;
    case PITCH_CIRCLECHANGE:     return ui_Boton__CIRCLECHANGE;
    case PITCH_CUTTER:           return ui_Boton_cutter;
    case PITCH_TENEDOR:          return ui_Boton__TENEDOR;
    case PITCH_SWEEPER:          return ui_Boton_SWEEPER;
    case PITCH_NUDILLERA:        return ui_Boton__nudillera;
    case PITCH_SPLITFINGER:      return ui_Boton_SPLITFINGER;
    default:                     return NULL;
    }
}

static lv_obj_t *boton_en(int p)
{
    switch (p) {
    case PITCH_RECTA_4C:         return ui_Recta_EN;
    case PITCH_CURVA:            return ui_Boton_Curva_EN;
    case PITCH_CAMBIO_VELOCIDAD: return ui_Boton_CAMBIO_DE_VELOCIDAD_EN;
    case PITCH_RECTA_2C:         return ui_Recta2_EN;
    case PITCH_SLIDER:           return ui_Boton_SLIDER_EN;
    case PITCH_TIRABUZON:        return ui_Boton__Tirabuzon_EN;
    case PITCH_SINKER:           return ui_Boton_sinker_EN;
    case PITCH_SPLITTER:         return ui_Boton__SPLITTER_EN;
    case PITCH_CIRCLECHANGE:     return ui_Boton__CIRCLECHANGE_EN;
    case PITCH_CUTTER:           return ui_Boton_cutter_EN;
    case PITCH_TENEDOR:          return ui_Boton__TENEDOR_EN;
    case PITCH_SWEEPER:          return ui_Boton_SWEEPER_EN;
    case PITCH_NUDILLERA:        return ui_Boton__nudillera_EN;
    case PITCH_SPLITFINGER:      return ui_Boton_SPLITFINGER_EN;
    default:                     return NULL;
    }
}

static void poner_estado(lv_obj_t *btn, bool habilitado)
{
    if (btn == NULL) return;
    if (habilitado) {
        lv_obj_clear_state(btn, LV_STATE_DISABLED);
        lv_obj_set_style_opa(btn, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
    } else {
        lv_obj_add_state(btn, LV_STATE_DISABLED);
        lv_obj_set_style_opa(btn, 70, LV_PART_MAIN | LV_STATE_DEFAULT);
    }
}

/* Corre en la tarea de LVGL (timer cada 100 ms). */
static void aplicar_timer_cb(lv_timer_t *t)
{
    (void)t;
    uint16_t mask = s_mask_pedida;

    lv_obj_t *act = lv_screen_active();
    bool aqui_es = (act != NULL) && (ui_LanzamientosUbi != NULL) && (act == ui_LanzamientosUbi);
    bool aqui_en = (act != NULL) && (ui_LanzamientosUbi_EN != NULL) && (act == ui_LanzamientosUbi_EN);
    bool entro   = (aqui_es && !s_estaba_es) || (aqui_en && !s_estaba_en);
    bool nuevos  = (ui_Recta != s_ult_btn_es) || (ui_Recta_EN != s_ult_btn_en);
    s_estaba_es = aqui_es;
    s_estaba_en = aqui_en;

    if (mask == s_mask_aplicada && !entro && !nuevos) return;

    for (int p = 0; p < PITCH_COUNT; p++) {
        bool ok = (mask >> p) & 1u;
        poner_estado(boton_es(p), ok);
        poner_estado(boton_en(p), ok);
    }
    /* Si el tipo que estaba elegido ya no esta permitido, limpiar la seleccion. */
    lanzamientos_dynamic_reset_selection();
    lanzamientos_dynamic_en_reset_selection();

    s_mask_aplicada = mask;
    s_ult_btn_es = ui_Recta;
    s_ult_btn_en = ui_Recta_EN;
    ESP_LOGI(TAG, "Filtro aplicado: mascara=0x%04X (entro=%d nuevos=%d)", mask, entro, nuevos);
}

void pitch_filter_init(void)
{
    static bool creado = false;      /* se puede llamar desde ES y EN: solo crea 1 timer */
    if (creado) return;
    creado = true;
    lv_timer_create(aplicar_timer_cb, 100, NULL);
}

bool pitch_filter_on_frame(uint8_t tipo, const uint8_t *payload, uint8_t len)
{
    if (tipo == UART_MSG_QUITAR_PERFIL) {
        s_mask_pedida = MASK_TODOS;
        ESP_LOGI(TAG, "Perfil quitado: 14 tipos habilitados");
        return true;
    }
    if (tipo == UART_MSG_PERFIL_LANZADOR) {
        uint16_t mask = 0;
        for (uint8_t i = 0; i < len; i++) {
            if (payload[i] < PITCH_COUNT) mask |= (uint16_t)(1u << s_slot_a_pitch[payload[i]]);
            else ESP_LOGW(TAG, "Slot fuera de rango ignorado: %u", payload[i]);
        }
        if (mask == 0) {  /* perfil vacio: no dejar la pantalla sin botones */
            mask = MASK_TODOS;
            ESP_LOGW(TAG, "Perfil sin tipos validos: se habilitan los 14");
        }
        s_mask_pedida = mask;
        ESP_LOGI(TAG, "Perfil recibido: %u tipos, mascara=0x%04X", len, mask);
        return true;
    }
    return false;
}
