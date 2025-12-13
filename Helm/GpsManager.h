#pragma once

#include <Arduino.h>
#include <HardwareSerial.h>
#include "DataModels.h"

namespace GpsConfig {
    constexpr uint16_t bufferSize = 128;
    constexpr uint32_t staleThresholdMs = 2000;
}

class GpsManager {
public:
    GpsManager(uint8_t rxPin, uint8_t txPin);

    bool begin();
    void update();
    GpsData getData() const;
    bool isDataFresh() const;
    bool hasValidFix() const;
    bool hasSufficientSatellites() const;
    bool hasAcceptableDop() const;

private:
    uint8_t _rxPin;
    uint8_t _txPin;
    HardwareSerial _serial;
    GpsData _data;
    char _buffer[GpsConfig::bufferSize];
    uint8_t _bufferIndex;
    bool _initialized;

    void processBuffer();
    void parseGga(const char* sentence);
    void parseGsa(const char* sentence);
    void parseRmc(const char* sentence);
    bool validateChecksum(const char* sentence);
    float parseCoordinate(const char* coord, const char* direction);
    const char* getField(const char* sentence, uint8_t fieldIndex);
    float parseFloat(const char* str);
    int parseInt(const char* str);
};