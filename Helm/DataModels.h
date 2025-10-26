#ifndef DATA_MODELS_H
#define DATA_MODELS_H

#include <Arduino.h>

struct GPSData {
    bool hasFix;
    int satellites;
    double latitude;
    double longitude;
    double altitude;
    String time;
    
    GPSData() : hasFix(false), satellites(0), latitude(0.0), longitude(0.0), altitude(0.0), time("") {}
};

struct NavigationState {
    bool isNavigating;
    bool hasReachedDestination;
    bool navigationEnabled;
    float targetLatitude;
    float targetLongitude;
    float currentDistance;
    float currentBearing;
    unsigned long lastCorrectionTime;
    
    NavigationState() : isNavigating(false), hasReachedDestination(false), navigationEnabled(false), 
                       targetLatitude(0.0), targetLongitude(0.0), currentDistance(0.0), 
                       currentBearing(0.0), lastCorrectionTime(0) {}
};

struct CompassCalibration {
    float magXmax;
    float magYmax;
    float magZmax;
    float magXmin;
    float magYmin;
    float magZmin;
    float magXoffset;
    float magYoffset;
    float magZoffset;
    float magXscale;
    float magYscale;
    float magZscale;
    
    CompassCalibration() : magXmax(31.91), magYmax(101.72), magZmax(54.58),
                          magXmin(-73.95), magYmin(-6.86), magZmin(-55.41),
                          magXoffset(0.0), magYoffset(0.0), magZoffset(0.0),
                          magXscale(1.0), magYscale(1.0), magZscale(1.0) {}
    
    void calculateOffsets() {
        magXoffset = (magXmax + magXmin) / 2.0;
        magYoffset = (magYmax + magYmin) / 2.0;
        magZoffset = (magZmax + magZmin) / 2.0;
        
        float xRange = magXmax - magXmin;
        float yRange = magYmax - magYmin;
        float zRange = magZmax - magZmin;
        float avgDelta = (xRange + yRange + zRange) / 3.0;
        
        magXscale = (xRange > 0.1) ? avgDelta / xRange : 1.0;
        magYscale = (yRange > 0.1) ? avgDelta / yRange : 1.0;
        magZscale = (zRange > 0.1) ? avgDelta / zRange : 1.0;
    }
};

struct SystemConfig {
    static const float HEADING_TOLERANCE;
    static const float MIN_CORRECTION_INTERVAL;
    static const float MIN_DISTANCE_METERS;
    static const int BUZZER_PIN;
    static const int GPS_RX_PIN;
    static const int GPS_TX_PIN;
    static const uint8_t SCREEN_ADDRESS;
};

#endif