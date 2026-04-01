#pragma once

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_MMC56x3.h>
#include "DataModels.h"

namespace CompassConfig {
    constexpr uint8_t i2cAddress = 0x30;
    constexpr uint8_t sampleCount = 5;
    constexpr uint32_t calibrationStreamIntervalMs = 50;
    constexpr uint32_t minCalibrationDurationMs = 5000;  // Minimum 5 seconds of calibration
    constexpr uint32_t minCalibrationSamples = 50;       // Minimum 50 samples for valid calibration
    constexpr float outlierThresholdMicroTesla = 200.0f; // Valid magnetometer range (typically -150 to +150 uT)
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

    // Tilt-compensated heading using pitch and roll from an accelerometer (radians).
    // Corrects for magnetic field projection errors when the sensor is not level.
    // Axis orientation note: assumes X=forward, Y=starboard, Z=down relative to the
    // mounted board.  If heading is systematically wrong when heeled, swap ax/ay in
    // LIS3DHManager or exchange x/y in the Xh/Yh formulas.
    float readHeadingTilted(float pitchRad, float rollRad);

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
    uint32_t _calibrationStartTime;  // Track when calibration started

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