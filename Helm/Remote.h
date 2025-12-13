#pragma once

#include <Arduino.h>
#include <driver/rmt.h>
#include "CC1101.h"

namespace RmtConfig {
    constexpr rmt_channel_t txChannel = RMT_CHANNEL_0;
    constexpr uint8_t clkDiv = 80;  // 80 MHz / 80 = 1µs resolution
}

namespace ManchesterTiming {
    constexpr uint16_t halfBitUs = 52;
    constexpr uint16_t bitPeriodUs = 104;
    constexpr uint16_t maxBits = 140;
}

class Remote {
public:
    Remote(CC1101& radio, uint8_t gdo0Pin);

    bool begin();
    void transmitPayload(const char* hexPayload);

private:
    CC1101& _radio;
    uint8_t _gdo0Pin;
    rmt_item32_t _rmtItems[ManchesterTiming::maxBits + 1];
    bool _initialized;

    uint8_t hexCharToNibble(char c);
    uint16_t buildManchesterItems(const char* hexPayload);
};