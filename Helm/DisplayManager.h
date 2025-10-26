#ifndef DISPLAY_MANAGER_H
#define DISPLAY_MANAGER_H

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Wire.h>
#include "DataModels.h"

class DisplayManager {
private:
    Adafruit_SSD1306* display;
    
public:
    DisplayManager();
    bool begin();
    void updateDisplay(const GPSData& gpsData, float heading, const NavigationState& navState, bool isConnected);
    void showCalibrationScreen(float x, float y, float z);
    void drawArrow(float angle, int centerX, int centerY, int size);
    
private:
    void drawStatusIcons(bool isConnected, bool isNavigating, bool hasReachedDestination);
    void drawNavigationInfo(const GPSData& gpsData, const NavigationState& navState);
    void drawBorders();
};

#endif