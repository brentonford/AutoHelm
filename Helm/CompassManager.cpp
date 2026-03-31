#include "CompassManager.h"

CompassManager::CompassManager(uint8_t sdaPin, uint8_t sclPin)
    : _sdaPin(sdaPin)
    , _sclPin(sclPin)
    , _initialized(false)
    , _calibrating(false)
    , _lastCalibrationStreamTime(0)
    , _calibrationStartTime(0)
    , _calMinX(9999.0f), _calMaxX(-9999.0f)
    , _calMinY(9999.0f), _calMaxY(-9999.0f)
    , _calMinZ(9999.0f), _calMaxZ(-9999.0f)
    , _calSampleCount(0)
    , _debugEnabled(false)
    , _lastDebugTime(0) {
}

bool CompassManager::begin() {
    Wire.begin(_sdaPin, _sclPin);

    if (!_mmc.begin(CompassConfig::i2cAddress, &Wire)) {
        Serial.println("[Compass] MMC5603 not found at 0x30");
        return false;
    }

    _mmc.setDataRate(100);
    _mmc.setContinuousMode(true);

    _initialized = true;
    Serial.println("[Compass] MMC5603 initialized");
    return true;
}

void CompassManager::applyCalibration(float& x, float& y, float& z) {
    x = (x - _calibration.offsetX) * _calibration.scaleX;
    y = (y - _calibration.offsetY) * _calibration.scaleY;
    z = (z - _calibration.offsetZ) * _calibration.scaleZ;
}

float CompassManager::normalizeHeading(float heading) {
    // Guard against NaN/Inf from a failed I2C read — infinite loop would hang the main task.
    if (!isfinite(heading)) return 0.0f;
    heading = fmodf(heading, 360.0f);
    if (heading < 0.0f) heading += 360.0f;
    return heading;
}

RawMagData CompassManager::readRaw() {
    RawMagData data = {0.0f, 0.0f, 0.0f};
    
    if (!_initialized)
        return data;

    sensors_event_t event;
    _mmc.getEvent(&event);

    data.x = event.magnetic.x;
    data.y = event.magnetic.y;
    data.z = event.magnetic.z;

    return data;
}

float CompassManager::readHeading() {
    if (!_initialized)
        return 0.0f;

    float sumX = 0.0f;
    float sumY = 0.0f;
    float sumZ = 0.0f;

    for (uint8_t i = 0; i < CompassConfig::sampleCount; i++) {
        sensors_event_t event;
        _mmc.getEvent(&event);

        sumX += event.magnetic.x;
        sumY += event.magnetic.y;
        sumZ += event.magnetic.z;

        delay(10);
    }

    float x = sumX / CompassConfig::sampleCount;
    float y = sumY / CompassConfig::sampleCount;
    float z = sumZ / CompassConfig::sampleCount;

    if (_calibrating) {
        updateCalibrationMinMax(x, y, z);
    }

    if (_debugEnabled) {
        uint32_t now = millis();
        if ((now - _lastDebugTime) >= 1000) {
            Serial.printf("[Compass] Raw: X=%.2f Y=%.2f Z=%.2f\n", x, y, z);
            _lastDebugTime = now;
        }
    }

    float rawX = x, rawY = y, rawZ = z;
    applyCalibration(x, y, z);

    if (_debugEnabled) {
        Serial.printf("[Compass] Calibrated: X=%.2f Y=%.2f Z=%.2f\n", x, y, z);
    }

    // Calculate heading with headingOffset applied
    float heading = atan2(y, x) * 180.0f / PI;
    heading -= _calibration.headingOffset;
    heading = normalizeHeading(heading);
    
    if (_debugEnabled) {
        Serial.printf("[Compass] Heading: %.1f° (offset: %.1f°)\n", heading, _calibration.headingOffset);
    }

    return heading;
}

void CompassManager::setDebugEnabled(bool enabled) {
    _debugEnabled = enabled;
    _lastDebugTime = 0;
    Serial.printf("[Compass] Debug output %s\n", enabled ? "ENABLED" : "DISABLED");
}

bool CompassManager::isDebugEnabled() const {
    return _debugEnabled;
}

void CompassManager::setCalibration(const CompassCalibration& cal) {
    _calibration = cal;
    Serial.printf("[Compass] Calibration set - Offsets: %.2f, %.2f, %.2f  Scales: %.3f, %.3f, %.3f  HeadingOffset: %.1f\n",
        cal.offsetX, cal.offsetY, cal.offsetZ,
        cal.scaleX, cal.scaleY, cal.scaleZ,
        cal.headingOffset);
}

CompassCalibration CompassManager::getCalibration() const {
    return _calibration;
}

void CompassManager::startCalibration() {
    _calibrating = true;
    _calMinX = 9999.0f;
    _calMaxX = -9999.0f;
    _calMinY = 9999.0f;
    _calMaxY = -9999.0f;
    _calMinZ = 9999.0f;
    _calMaxZ = -9999.0f;
    _calSampleCount = 0;
    _lastCalibrationStreamTime = 0;
    _calibrationStartTime = millis();
    Serial.println("[Compass] Calibration started - rotate device slowly");
    Serial.printf("[Compass] Minimum requirements: %lu samples, %lu ms duration\n",
        CompassConfig::minCalibrationSamples, CompassConfig::minCalibrationDurationMs);
}

void CompassManager::stopCalibration() {
    _calibrating = false;

    uint32_t calibrationDuration = millis() - _calibrationStartTime;

    // Validate both sample count AND duration for quality calibration
    if (_calSampleCount < CompassConfig::minCalibrationSamples) {
        Serial.printf("[Compass] Calibration stopped - insufficient samples (%lu < %lu required)\n",
            _calSampleCount, CompassConfig::minCalibrationSamples);
        return;
    }

    if (calibrationDuration < CompassConfig::minCalibrationDurationMs) {
        Serial.printf("[Compass] Calibration stopped - insufficient duration (%lu ms < %lu ms required)\n",
            calibrationDuration, CompassConfig::minCalibrationDurationMs);
        return;
    }

    float offsetX = (_calMaxX + _calMinX) / 2.0f;
    float offsetY = (_calMaxY + _calMinY) / 2.0f;
    float offsetZ = (_calMaxZ + _calMinZ) / 2.0f;

    float avgDeltaX = (_calMaxX - _calMinX) / 2.0f;
    float avgDeltaY = (_calMaxY - _calMinY) / 2.0f;
    float avgDeltaZ = (_calMaxZ - _calMinZ) / 2.0f;

    float avgDelta = (avgDeltaX + avgDeltaY + avgDeltaZ) / 3.0f;

    float scaleX = (avgDeltaX != 0.0f) ? avgDelta / avgDeltaX : 1.0f;
    float scaleY = (avgDeltaY != 0.0f) ? avgDelta / avgDeltaY : 1.0f;
    float scaleZ = (avgDeltaZ != 0.0f) ? avgDelta / avgDeltaZ : 1.0f;

    _calibration.offsetX = offsetX;
    _calibration.offsetY = offsetY;
    _calibration.offsetZ = offsetZ;
    _calibration.scaleX = scaleX;
    _calibration.scaleY = scaleY;
    _calibration.scaleZ = scaleZ;
    // Note: headingOffset is NOT changed during magnetometer calibration

    Serial.printf("[Compass] Calibration complete - %lu samples in %lu ms\n", _calSampleCount, calibrationDuration);
    Serial.printf("[Compass] Min: %.2f, %.2f, %.2f  Max: %.2f, %.2f, %.2f\n",
        _calMinX, _calMinY, _calMinZ, _calMaxX, _calMaxY, _calMaxZ);
    Serial.printf("[Compass] Offsets: %.2f, %.2f, %.2f  Scales: %.3f, %.3f, %.3f\n",
        offsetX, offsetY, offsetZ, scaleX, scaleY, scaleZ);
}

bool CompassManager::isCalibrating() const {
    return _calibrating;
}

bool CompassManager::shouldStreamCalibrationData() const {
    if (!_calibrating)
        return false;
    return (millis() - _lastCalibrationStreamTime) >= CompassConfig::calibrationStreamIntervalMs;
}

void CompassManager::markCalibrationDataSent() {
    _lastCalibrationStreamTime = millis();
}

void CompassManager::updateCalibrationMinMax(float x, float y, float z) {
    // Reject obvious outliers (valid magnetometer readings are typically -150 to +150 µT)
    // Using configurable threshold for flexibility
    const float threshold = CompassConfig::outlierThresholdMicroTesla;
    bool validReading = (abs(x) < threshold && abs(y) < threshold && abs(z) < threshold);

    if (!validReading) {
        Serial.printf("[Compass] REJECTED outlier: X=%.2f Y=%.2f Z=%.2f (threshold: %.1f uT)\n",
            x, y, z, threshold);
        return;
    }

    if (x < _calMinX) _calMinX = x;
    if (x > _calMaxX) _calMaxX = x;
    if (y < _calMinY) _calMinY = y;
    if (y > _calMaxY) _calMaxY = y;
    if (z < _calMinZ) _calMinZ = z;
    if (z > _calMaxZ) _calMaxZ = z;
    _calSampleCount++;
}

String CompassManager::getCalibrationJson() const {
    String json = "{\"cal\":true,";
    json += "\"samples\":" + String(_calSampleCount) + ",";
    json += "\"minX\":" + String(_calMinX, 2) + ",";
    json += "\"maxX\":" + String(_calMaxX, 2) + ",";
    json += "\"minY\":" + String(_calMinY, 2) + ",";
    json += "\"maxY\":" + String(_calMaxY, 2) + ",";
    json += "\"minZ\":" + String(_calMinZ, 2) + ",";
    json += "\"maxZ\":" + String(_calMaxZ, 2);
    
    RawMagData raw;
    raw.x = (_calSampleCount > 0) ? (_calMaxX + _calMinX) / 2.0f : 0.0f;
    raw.y = (_calSampleCount > 0) ? (_calMaxY + _calMinY) / 2.0f : 0.0f;
    raw.z = (_calSampleCount > 0) ? (_calMaxZ + _calMinZ) / 2.0f : 0.0f;
    
    json += ",\"rawX\":" + String(raw.x, 2);
    json += ",\"rawY\":" + String(raw.y, 2);
    json += ",\"rawZ\":" + String(raw.z, 2);
    json += "}";
    
    return json;
}