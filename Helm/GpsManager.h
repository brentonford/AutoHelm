#pragma once

#include <Arduino.h>
#include <HardwareSerial.h>
#include "DataModels.h"

namespace GpsConfig {
    constexpr uint16_t bufferSize = 128;
    constexpr uint16_t fieldBufferSize = 20;
    constexpr uint32_t staleThresholdMs = 2000;
    constexpr uint32_t debugPrintIntervalMs = 5000;
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
    
    void setDebugEnabled(bool enabled);
    bool isDebugEnabled() const;

private:
    uint8_t _rxPin;
    uint8_t _txPin;
    HardwareSerial _serial;
    GpsData _data;
    char _buffer[GpsConfig::bufferSize];
    uint8_t _bufferIndex;
    bool _initialized;
    uint32_t _lastReceiveTime;
    bool _firstFixReceived;
    uint32_t _lastDebugTime;
    uint16_t _charCount;
    bool _debugEnabled;

    void processBuffer();
    void parseGga(const char* sentence);
    void parseGsa(const char* sentence);
    void parseRmc(const char* sentence);
    bool validateChecksum(const char* sentence) const;
    float parseCoordinate(const char* coord, char direction) const;
    bool extractField(const char* sentence, uint8_t fieldIndex, char* outBuffer, size_t bufferSize) const;
    float parseFloat(const char* str) const;
    int parseInt(const char* str) const;
    void printDebugStatus();
};