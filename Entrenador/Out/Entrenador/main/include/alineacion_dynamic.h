#pragma once

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

void alineacion_dynamic_init(void);
void sync_name_global(lv_obj_t *source_btn, const char *new_name);
void sync_field_label_only(lv_obj_t *source_btn, const char *new_name);
void open_edit_player_popup(lv_obj_t *btn);

#ifdef __cplusplus
} /*extern "C"*/
#endif