#include "CompassManager.h"

CompassManager::CompassManager(uint8_t sdaPin, uint8_t sclPin)
    : _sdaPin(sdaPin)
    , _sclPin(sclPin)
    , _initialized(false) {
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
    while (heading < 0.0f)
        heading += 360.0f;
    while (heading >= 360.0f)
        heading -= 360.0f;
    return heading;
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

    applyCalibration(x, y, z);

    float heading = atan2(y, x) * 180.0f / PI;
    return normalizeHeading(heading);
}

void CompassManager::setCalibration(const CompassCalibration& cal) {
    _calibration = cal;
}

CompassCalibration CompassManager::getCalibration() const {
    return _calibration;
}