#ifndef DISPLAY_MANAGER_H
#define DISPLAY_MANAGER_H

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Wire.h>
#include "DataModels.h"

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1

class DisplayManager {
private:
    Adafruit_SSD1306 display;
    bool initialized;
    
public:
    DisplayManager();
    bool begin();
    void showStartupScreen();
    void showStatus(const char* message);
    void updateGPSDisplay(const GPSData& data);
    void showCompassHeading(float heading);
    void updateGPSAndCompass(const GPSData& data, float heading);
    void drawCoordinates(float lat, float lon);
    void drawSatelliteCount(int count);
};

#endif