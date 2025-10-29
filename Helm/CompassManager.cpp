#include "CompassManager.h"
#include <Arduino.h>

CompassManager::CompassManager() : initialized(false), calibrationMode(false) {
}

bool CompassManager::begin() {
    // Will fail if I2C communication with MMC5603 fails
    if (!mmc.begin(MMC56X3_DEFAULT_ADDRESS, &Wire1)) {
        initialized = false;
        return false;
    }
    
    initialized = true;
    return true;
}

float CompassManager::readHeading() {
    if (!initialized) return 0.0;
    
    sensors_event_t event;
    // Will fail if sensor communication fails
    mmc.getEvent(&event);
    
    float x = event.magnetic.x;
    float y = event.magnetic.y;
    float z = event.magnetic.z;
    
    if (calibrationMode) {
        updateCalibrationBounds(x, y, z);
    }
    
    applyCalibration(x, y, z);
    return calculateHeading(x, y, z);
}

void CompassManager::startCalibration() {
    if (!initialized) return;
    
    calibrationMode = true;
    // Reset calibration bounds
    calibration.minX = calibration.minY = calibration.minZ = 999999.0;
    calibration.maxX = calibration.maxY = calibration.maxZ = -999999.0;
    Serial.println("Compass calibration started - rotate device in all directions");
}

void CompassManager::stopCalibration() {
    if (!initialized) return;
    
    calibrationMode = false;
    // Calculate offsets from min/max values
    calibration.offsetX = (calibration.maxX + calibration.minX) / 2.0;
    calibration.offsetY = (calibration.maxY + calibration.minY) / 2.0;
    calibration.offsetZ = (calibration.maxZ + calibration.minZ) / 2.0;
    Serial.println("Compass calibration completed");
}

bool CompassManager::isCalibrating() const {
    return calibrationMode;
}

CompassCalibration CompassManager::getCalibration() const {
    return calibration;
}

void CompassManager::setCalibration(const CompassCalibration& cal) {
    calibration = cal;
}

bool CompassManager::isInitialized() const {
    return initialized;
}

float CompassManager::calculateHeading(float x, float y, float z) {
    // Calculate heading using atan2 for X and Y components
    float heading = atan2(y, x) * 180.0 / PI;
    
    // Normalize to 0-360 degrees
    if (heading < 0) {
        heading += 360.0;
    }
    
    return heading;
}

void CompassManager::applyCalibration(float& x, float& y, float& z) {
    x -= calibration.offsetX;
    y -= calibration.offsetY;
    z -= calibration.offsetZ;
}

void CompassManager::updateCalibrationBounds(float x, float y, float z) {
    if (x < calibration.minX) calibration.minX = x;
    if (x > calibration.maxX) calibration.maxX = x;
    if (y < calibration.minY) calibration.minY = y;
    if (y > calibration.maxY) calibration.maxY = y;
    if (z < calibration.minZ) calibration.minZ = z;
    if (z > calibration.maxZ) calibration.maxZ = z;
}