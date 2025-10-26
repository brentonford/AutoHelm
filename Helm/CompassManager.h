#ifndef COMPASS_MANAGER_H
#define COMPASS_MANAGER_H

#include <Adafruit_MMC56x3.h>
#include <Wire.h>
#include "DataModels.h"

class CompassManager {
private:
    Adafruit_MMC5603 compass;
    CompassCalibration calibration;
    bool isCalibrating;
    float calMagMinX, calMagMaxX;
    float calMagMinY, calMagMaxY;
    float calMagMinZ, calMagMaxZ;
    bool firstCalibrationReading;
    
public:
    CompassManager();
    bool begin();
    float readHeading();
    void startCalibration();
    void stopCalibration();
    void updateCalibration(float x, float y, float z);
    bool isCalibrationMode() const;
    void getCalibrationData(float& x, float& y, float& z, float& minX, float& minY, float& minZ, float& maxX, float& maxY, float& maxZ);
    
private:
    void initializeCalibration();
};

#endif