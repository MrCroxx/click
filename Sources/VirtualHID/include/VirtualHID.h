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
void click_hid_report(uint32_t page, const uint16_t *keys, int count);

#ifdef __cplusplus
}
#endif
