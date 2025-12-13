#pragma once

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_MMC56x3.h>
#include "DataModels.h"

namespace CompassConfig {
    constexpr uint8_t i2cAddress = 0x30;
    constexpr uint8_t sampleCount = 5;
}

class CompassManager {
public:
    CompassManager(uint8_t sdaPin, uint8_t sclPin);

    bool begin();
    float readHeading();
    void setCalibration(const CompassCalibration& cal);
    CompassCalibration getCalibration() const;

private:
    uint8_t _sdaPin;
    uint8_t _sclPin;
    Adafruit_MMC5603 _mmc;
    CompassCalibration _calibration;
    bool _initialized;

    void applyCalibration(float& x, float& y, float& z);
    float normalizeHeading(float heading);
};