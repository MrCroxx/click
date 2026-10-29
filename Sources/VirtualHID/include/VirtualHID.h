#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// All calls except the atomic readiness query are made on the daemon's main queue.
void click_hid_start(void);
void click_hid_stop(void);
bool click_hid_ready(void);
bool click_hid_pointing_ready(void);
void click_hid_report(uint32_t page, const uint16_t *keys, int count);
void click_hid_pointing_report(uint32_t buttons, int8_t x, int8_t y, int8_t vertical, int8_t horizontal);

#ifdef __cplusplus
}
#endif
