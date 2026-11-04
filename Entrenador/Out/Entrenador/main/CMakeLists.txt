FILE(GLOB_RECURSE main ${CMAKE_SOURCE_DIR}/main/*.c)

idf_component_register(SRCS ${main}
                        INCLUDE_DIRS "include" "ui" 
                        REQUIRES bsp_extra bsp_display bsp_illuminate bsp_i2c esp_timer esp_wifi esp_wifi_remote esp_hosted lwip nvs_flash)