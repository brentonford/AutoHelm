#ifndef GPS_MANAGER_H
#define GPS_MANAGER_H

#include <Arduino.h>
#include <SoftwareSerial.h>
#include "DataModels.h"

class GPSManager {
private:
    SoftwareSerial* gpsSerial;
    GPSData currentData;
    bool previousFixStatus;
    
public:
    GPSManager();
    void begin();
    void update();
    GPSData getCurrentData() const;
    bool hasFixStatusChanged();
    void printDebugInfo(float heading);
    
private:
    GPSData parseGPS();
};

#endif