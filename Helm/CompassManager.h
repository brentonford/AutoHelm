#pragma once

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_MMC56x3.h>
#include "DataModels.h"

namespace CompassConfig {
    constexpr uint8_t i2cAddress = 0x30;
    constexpr uint8_t sampleCount = 5;
    constexpr uint32_t calibrationStreamIntervalMs = 50;
}

struct RawMagData {
    float x;
    float y;
    float z;
};

class CompassManager {
public:
    CompassManager(uint8_t sdaPin, uint8_t sclPin);

    bool begin();
    float readHeading();
    RawMagData readRaw();
    void setCalibration(const CompassCalibration& cal);
    CompassCalibration getCalibration() const;
    
    void startCalibration();
    void stopCalibration();
    bool isCalibrating() const;
    bool shouldStreamCalibrationData() const;
    void markCalibrationDataSent();
    String getCalibrationJson() const;
    
    void setDebugEnabled(bool enabled);
    bool isDebugEnabled() const;

private:
    uint8_t _sdaPin;
    uint8_t _sclPin;
    Adafruit_MMC5603 _mmc;
    CompassCalibration _calibration;
    bool _initialized;
    bool _calibrating;
    uint32_t _lastCalibrationStreamTime;
    
    float _calMinX, _calMaxX;
    float _calMinY, _calMaxY;
    float _calMinZ, _calMaxZ;
    uint32_t _calSampleCount;
    
    bool _debugEnabled;
    uint32_t _lastDebugTime;

    void applyCalibration(float& x, float& y, float& z);
    float normalizeHeading(float heading);
    void updateCalibrationMinMax(float x, float y, float z);
};