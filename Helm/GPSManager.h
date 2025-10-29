#ifndef GPS_MANAGER_H
#define GPS_MANAGER_H

#include <SoftwareSerial.h>
#include "DataModels.h"

class GPSManager {
private:
    SoftwareSerial gpsSerial;
    GPSData currentData;
    char nmeaBuffer[128];
    int bufferIndex;
    
    void parseNMEA(const char* sentence);
    void parseGGA(const char* data);
    void parseRMC(const char* data);
    bool isValidChecksum(const char* sentence);
    float parseCoordinate(const char* coord, char direction);
    
public:
    GPSManager(int rxPin, int txPin);
    bool begin();
    void update();
    GPSData getData() const;
};

#endif