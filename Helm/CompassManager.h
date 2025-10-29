#ifndef COMPASS_MANAGER_H
#define COMPASS_MANAGER_H

#include <Adafruit_MMC56x3.h>
#include <Wire.h>

struct CompassCalibration {
    float minX, minY, minZ;
    float maxX, maxY, maxZ;
    float offsetX, offsetY, offsetZ;
    
    CompassCalibration() : minX(0), minY(0), minZ(0), maxX(0), maxY(0), maxZ(0), 
                          offsetX(0), offsetY(0), offsetZ(0) {}
};

class CompassManager {
private:
    Adafruit_MMC5603 mmc;
    CompassCalibration calibration;
    bool initialized;
    bool calibrationMode;
    
    float calculateHeading(float x, float y, float z);
    void applyCalibration(float& x, float& y, float& z);
    void updateCalibrationBounds(float x, float y, float z);
    
public:
    CompassManager();
    bool begin();
    float readHeading();
    void startCalibration();
    void stopCalibration();
    bool isCalibrating() const;
    CompassCalibration getCalibration() const;
    void setCalibration(const CompassCalibration& cal);
    bool isInitialized() const;
};

#endif