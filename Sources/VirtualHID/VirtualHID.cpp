#include "VirtualHID.h"
#include <atomic>
#include <memory>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
namespace {
using Client = pqrs::karabiner::driverkit::virtual_hid_device_service::client;
namespace reports = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report;
std::unique_ptr<Client> client;
std::atomic<bool> ready{false};
std::atomic<bool> pointing_ready{false};
template<class Report> void report(const uint16_t *keys, int count) {
    Report r;
    for (int i = 0; i < count; ++i) r.keys.insert(keys[i]);
    client->async_post_report(r);
}
}
void click_hid_start() {
    if (client) return;
    static const bool initialized = [] { pqrs::dispatcher::extra::initialize_shared_dispatcher(); return true; }();
    (void)initialized;
    client = std::make_unique<Client>();
    client->connected.connect([] {
        client->async_virtual_hid_keyboard_initialize({});
        client->async_virtual_hid_pointing_initialize();
    });
    client->virtual_hid_keyboard_ready.connect([](bool value) { ready = value; });
    client->virtual_hid_pointing_ready.connect([](bool value) { pointing_ready = value; });
    client->closed.connect([] { ready = false; pointing_ready = false; });
    client->error_occurred.connect([](auto&&) { ready = false; pointing_ready = false; });
    client->driver_version_mismatched.connect([](bool value) { if (value) { ready = false; pointing_ready = false; } });
    client->async_start();
}
void click_hid_stop() { ready = false; pointing_ready = false; client.reset(); }
bool click_hid_ready() { return ready; }
bool click_hid_pointing_ready() { return pointing_ready; }
void click_hid_pointing_report(uint32_t buttons, int8_t x, int8_t y, int8_t vertical, int8_t horizontal) {
    if (!client || !pointing_ready) return;
    reports::pointing_input r;
    for (uint32_t i = 0; i < 32; ++i) if (buttons & (uint32_t(1) << i)) r.buttons.insert(i + 1);
    r.x = static_cast<uint8_t>(x); r.y = static_cast<uint8_t>(y);
    r.vertical_wheel = static_cast<uint8_t>(vertical); r.horizontal_wheel = static_cast<uint8_t>(horizontal);
    client->async_post_report(r);
}
void click_hid_report(uint32_t page, const uint16_t *keys, int count) {
    if (!client || !ready || count < 0 || count > 256) return;
    switch (page) {
    case 7: {
        reports::keyboard_input r;
        for (int i = 0; i < count; ++i) {
            if (keys[i] >= 224 && keys[i] <= 231)
                r.modifiers.insert(static_cast<reports::modifier>(1 << (keys[i] - 224)));
            else r.keys.insert(keys[i]);
        }
        client->async_post_report(r); break;
    }
    case 12: report<reports::consumer_input>(keys, count); break;
    case 1: report<reports::generic_desktop_input>(keys, count); break;
    case 0xff01: report<reports::apple_vendor_keyboard_input>(keys, count); break;
    case 0x00ff: report<reports::apple_vendor_top_case_input>(keys, count); break;
    }
}
