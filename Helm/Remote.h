#pragma once

#include <Arduino.h>
#include <driver/rmt.h>
#include <esp_pm.h>
#include "CC1101.h"
#include "secrets.h"

namespace RmtConfig {
    constexpr rmt_channel_t txChannel = RMT_CHANNEL_0;
    constexpr uint8_t clkDiv = 80;  // 80 MHz / 80 = 1µs resolution
}

namespace ManchesterTiming {
    constexpr uint16_t halfBitUs = 52;
    constexpr uint16_t bitPeriodUs = 104;
    constexpr uint16_t maxBits = 140;
}

namespace RemoteProtocol {
    constexpr const char* preamble = "2aaaaaaa";
    constexpr const char* syncWord = "d391d391";
    constexpr uint16_t burstGapMs = 68;
    constexpr uint16_t defaultHoldMs = 1000;
}

enum class Button : uint8_t {
    Right,
    Left,
    Up,
    Down,
    Motor,
    Momentary,
    Release,
    Count
};

class Remote {
public:
    Remote(CC1101& radio, uint8_t gdo0Pin);

    bool begin();
    void transmitSingle(Button button);
    void transmitHold(Button button, uint16_t durationMs = RemoteProtocol::defaultHoldMs);

private:
    CC1101& _radio;
    uint8_t _gdo0Pin;
    rmt_item32_t _rmtItems[ManchesterTiming::maxBits + 1];
    esp_pm_lock_handle_t _pmLock;
    bool _initialized;

    char _payloads[static_cast<uint8_t>(Button::Count)][38];

    void buildPayloads();
    uint8_t hexCharToNibble(char c);
    uint16_t buildManchesterItems(const char* hexPayload);
    void transmitBurst(Button button);
    const char* buttonName(Button button);
};