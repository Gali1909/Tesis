#pragma once

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

void alineacion_dynamic_EN_init(void);
void sync_name_global_EN(lv_obj_t *source_btn, const char *new_name);
void sync_field_label_only_EN(lv_obj_t *source_btn, const char *new_name);
void open_edit_player_popup_EN(lv_obj_t *btn);

#ifdef __cplusplus
} /*extern "C"*/
#endif
