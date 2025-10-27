#include "CompassManager.h"
#include <Wire.h>

CompassManager::CompassManager() : compass(12345), isCalibrating(false), firstCalibrationReading(true) {
    calibration.calculateOffsets();
}

bool CompassManager::begin() {
    if (!compass.begin(MMC56X3_DEFAULT_ADDRESS, &Wire1)) {
        Serial.println("MMC5603 not detected on Wire1, trying Wire bus...");
        if (!compass.begin(MMC56X3_DEFAULT_ADDRESS, &Wire)) {
            Serial.println("MMC5603 not detected on either I2C bus");
            return false;
        } else {
            Serial.println("Magnetometer initialized on Wire bus");
        }
    } else {
        Serial.println("Magnetometer initialized on Wire1 bus");
    }
    
    return true;
}

float CompassManager::readHeading() {
    sensors_event_t event;
    compass.getEvent(&event);
    
    float x = event.magnetic.x - calibration.magXoffset;
    float y = event.magnetic.y - calibration.magYoffset;
    float z = event.magnetic.z - calibration.magZoffset;
    
    x *= calibration.magXscale;
    y *= calibration.magYscale;
    z *= calibration.magZscale;

    float heading = (atan2(-x, y) * 180.0) / M_PI;
    
    if (heading < 0) {
        heading = 360.0 + heading;
    }
    
    return heading;
}

void CompassManager::startCalibration() {
    isCalibrating = true;
    firstCalibrationReading = true;
    Serial.println("Calibration mode started");
}

void CompassManager::stopCalibration() {
    isCalibrating = false;
    Serial.println("Calibration mode stopped");
}

void CompassManager::updateCalibration(float x, float y, float z) {
    if (firstCalibrationReading) {
        calMagMinX = calMagMaxX = x;
        calMagMinY = calMagMaxY = y;
        calMagMinZ = calMagMaxZ = z;
        firstCalibrationReading = false;
    } else {
        if (x < calMagMinX) calMagMinX = x;
        if (x > calMagMaxX) calMagMaxX = x;
        if (y < calMagMinY) calMagMinY = y;
        if (y > calMagMaxY) calMagMaxY = y;
        if (z < calMagMinZ) calMagMinZ = z;
        if (z > calMagMaxZ) calMagMaxZ = z;
    }
}

bool CompassManager::isCalibrationMode() const {
    return isCalibrating;
}

void CompassManager::getCalibrationData(float& x, float& y, float& z, float& minX, float& minY, float& minZ, float& maxX, float& maxY, float& maxZ) {
    sensors_event_t event;
    compass.getEvent(&event);
    
    x = event.magnetic.x;
    y = event.magnetic.y;
    z = event.magnetic.z;
    
    updateCalibration(x, y, z);
    
    minX = calMagMinX;
    minY = calMagMinY;
    minZ = calMagMinZ;
    maxX = calMagMaxX;
    maxY = calMagMaxY;
    maxZ = calMagMaxZ;
}