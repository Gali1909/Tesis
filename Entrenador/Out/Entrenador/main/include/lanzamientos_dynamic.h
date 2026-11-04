// lanzamientos_dynamic.h
#ifndef LANZAMIENTOS_DYNAMIC_H
#define LANZAMIENTOS_DYNAMIC_H

typedef enum {
    PITCH_RECTA_4C = 0,       //0 ui_Recta            - RECTA DE 4 COSTURAS
    PITCH_CURVA,              //1 ui_Boton_Curva       - CURVA 
    PITCH_CAMBIO_VELOCIDAD,   //2 ui_Boton_CAMBIO_DE_VELOCIDAD - CAMBIO DE VELOCIDAD
    PITCH_RECTA_2C,           //3 ui_Recta2           - RECTA DE 2 COSTURAS
    PITCH_SLIDER,             //4 ui_Boton_SLIDER      - SLIDER
    PITCH_TIRABUZON,          //5 ui_Boton__Tirabuzon  - TIRABUZON
    PITCH_SINKER,             //6 ui_Boton_sinker      - SINKER
    PITCH_SPLITTER,           //7 ui_Boton__SPLITTER   - SPLITTER
    PITCH_CIRCLECHANGE,       //8 ui_Boton__CIRCLECHANGE - CIRCLE CHANGE
    PITCH_CUTTER,             //9 ui_Boton_cutter      - CUTTER
    PITCH_TENEDOR,            //10 ui_Boton__TENEDOR    - TENEDOR
    PITCH_SWEEPER,            //11 ui_Boton_SWEEPER     - SWEEPER
    PITCH_NUDILLERA,          //12 ui_Boton__nudillera  - NUDILLERA
    PITCH_SPLITFINGER,        // ui_Boton_SPLITFINGER - SPLIT-FINGER
    PITCH_NONE = -1
} pitch_type_t;

void lanzamientos_dynamic_init(void);
void lanzamientos_dynamic_reset_selection(void);

#endif