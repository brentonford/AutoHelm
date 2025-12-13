#pragma once

#include <cstdint>

namespace Pins {
    // SPI - CC1101 RF Module
    constexpr uint8_t cc1101Cs   = 5;
    constexpr uint8_t cc1101Gdo0 = 4;
    constexpr uint8_t cc1101Sck  = 18;
    constexpr uint8_t cc1101Miso = 19;
    constexpr uint8_t cc1101Mosi = 23;

    // UART2 - GPS Module
    constexpr uint8_t gpsRx = 16;
    constexpr uint8_t gpsTx = 17;

    // I2C - Magnetometer
    constexpr uint8_t i2cSda = 21;
    constexpr uint8_t i2cScl = 22;
}

namespace Config {
    constexpr uint32_t serialBaud = 115200;
    constexpr uint32_t gpsBaud    = 9600;
}

struct GpsData {
    float latitude;
    float longitude;
    float altitude;
    float hdop;
    float vdop;
    float pdop;
    uint8_t satellites;
    bool hasFix;
    uint32_t timestamp;

    GpsData()
        : latitude(0.0f)
        , longitude(0.0f)
        , altitude(0.0f)
        , hdop(99.0f)
        , vdop(99.0f)
        , pdop(99.0f)
        , satellites(0)
        , hasFix(false)
        , timestamp(0) {
    }
};