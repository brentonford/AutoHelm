#include "DisplayManager.h"
#include <Wire.h>

DisplayManager::DisplayManager() : display(nullptr) {
}

bool DisplayManager::begin() {
    display = new Adafruit_SSD1306(128, 64, &Wire1, -1);
    
    if(!display->begin(SSD1306_SWITCHCAPVCC, SystemConfig::SCREEN_ADDRESS)) {
        Serial.println(F("SSD1306 allocation failed"));
        return false;
    }
    
    Serial.println("OLED initialised!");
    display->clearDisplay();
    display->display();
    return true;
}

void DisplayManager::updateDisplay(const GPSData& gpsData, float heading, const NavigationState& navState, bool isConnected) {
    display->clearDisplay();
    
    if (!gpsData.hasFix) {
        display->setTextColor(SSD1306_WHITE);
        display->setCursor(44, 5);
        display->print("NO FIX!");
        display->setTextSize(1);
        display->setCursor(10, 30);
        display->print("Waiting for GPS...");
        display->setCursor(24, 50);
        display->print("Satellites: ");
        display->print(gpsData.satellites);
        display->display();
        return;
    }
    
    float relativeAngle = fmod((navState.currentBearing - heading + 360.0), 360.0);
    drawArrow(relativeAngle, 30, 26, 26);
    
    drawStatusIcons(isConnected, navState.isNavigating, navState.hasReachedDestination);
    drawNavigationInfo(gpsData, navState);
    drawBorders();
    
    display->display();
}

void DisplayManager::showCalibrationScreen(float x, float y, float z) {
    display->clearDisplay();
    display->setTextSize(1);
    display->setTextColor(SSD1306_WHITE);
    display->setCursor(16, 5);
    display->print("CALIBRATION MODE");
    display->setCursor(4, 20);
    display->print("Rotate device slowly");
    display->setCursor(8, 30);
    display->print("in all directions");
    display->setCursor(4, 45);
    display->print("X: ");
    display->print(x, 1);
    display->setCursor(4, 55);
    display->print("Y: ");
    display->print(y, 1);
    display->setCursor(64, 55);
    display->print("Z: ");
    display->print(z, 1);
    display->display();
}

void DisplayManager::drawArrow(float angle, int centerX, int centerY, int size) {
    float radAngle = angle * M_PI / 180.0;
    
    int tipX = centerX + size * sin(radAngle);
    int tipY = centerY - size * cos(radAngle);
    
    float baseAngle1 = radAngle + 150.0 * M_PI / 180.0;
    float baseAngle2 = radAngle - 150.0 * M_PI / 180.0;
    
    int baseX1 = centerX + (size/2) * sin(baseAngle1);
    int baseY1 = centerY - (size/2) * cos(baseAngle1);
    
    int baseX2 = centerX + (size/2) * sin(baseAngle2);
    int baseY2 = centerY - (size/2) * cos(baseAngle2);
    
    display->drawLine(centerX, centerY, tipX, tipY, SSD1306_WHITE);
    display->drawLine(tipX, tipY, baseX1, baseY1, SSD1306_WHITE);
    display->drawLine(tipX, tipY, baseX2, baseY2, SSD1306_WHITE);
}

void DisplayManager::drawStatusIcons(bool isConnected, bool isNavigating, bool hasReachedDestination) {
    display->setTextSize(1);
    display->setTextColor(SSD1306_WHITE);
    
    int iconX = 110;
    int iconY = 2;
    
    if (isConnected) {
        display->drawPixel(iconX, iconY + 2, SSD1306_WHITE);
        display->drawPixel(iconX + 1, iconY + 1, SSD1306_WHITE);
        display->drawPixel(iconX + 2, iconY, SSD1306_WHITE);
        display->drawPixel(iconX + 3, iconY + 1, SSD1306_WHITE);
        display->drawPixel(iconX + 4, iconY + 2, SSD1306_WHITE);
    }
    iconX += 8;
    
    if (hasReachedDestination) {
        display->drawPixel(iconX, iconY + 2, SSD1306_WHITE);
        display->drawPixel(iconX + 1, iconY + 3, SSD1306_WHITE);
        display->drawPixel(iconX + 2, iconY + 2, SSD1306_WHITE);
        display->drawPixel(iconX + 3, iconY + 1, SSD1306_WHITE);
        display->drawPixel(iconX + 4, iconY, SSD1306_WHITE);
    } else if (isNavigating) {
        display->drawPixel(iconX + 2, iconY, SSD1306_WHITE);
        display->drawPixel(iconX + 1, iconY + 1, SSD1306_WHITE);
        display->drawPixel(iconX + 2, iconY + 1, SSD1306_WHITE);
        display->drawPixel(iconX + 3, iconY + 1, SSD1306_WHITE);
        display->drawPixel(iconX + 2, iconY + 2, SSD1306_WHITE);
        display->drawPixel(iconX + 2, iconY + 3, SSD1306_WHITE);
        display->drawPixel(iconX + 2, iconY + 4, SSD1306_WHITE);
    }
}

void DisplayManager::drawNavigationInfo(const GPSData& gpsData, const NavigationState& navState) {
    if (navState.currentDistance >= 1000) {
        display->setCursor(4, 57);
        display->print(navState.currentDistance/1000, 1);
        display->print(" km");
    } else {
        display->setCursor(4, 57);
        display->print((int)navState.currentDistance);
        display->print(" m");
    }
    
    display->setCursor(94, 57);
    display->print(gpsData.altitude, 1);
    
    display->setCursor(64, 2);
    display->print(gpsData.latitude, 6);
    display->setCursor(64, 12);
    display->print(gpsData.longitude, 6);
    
    if (navState.isNavigating || navState.hasReachedDestination) {
        display->setCursor(64, 30);
        display->print(navState.targetLatitude, 6);
        display->setCursor(64, 40);
        display->print(navState.targetLongitude, 6);
    }
}

void DisplayManager::drawBorders() {
    display->drawLine(47, 0, 58, 11, SSD1306_WHITE);
    display->drawLine(58, 11, 58, 38, SSD1306_WHITE);
    display->drawLine(58, 38, 47, 49, SSD1306_WHITE);
    display->drawLine(0, 11, 11, 0, SSD1306_WHITE);
    display->drawLine(0, 11, 0, 38, SSD1306_WHITE);          
    display->drawLine(0, 38, 11, 49, SSD1306_WHITE);
    display->drawLine(86, 54, 86, 64, SSD1306_WHITE);
    display->drawLine(86, 54, 128, 54, SSD1306_WHITE);
    display->drawLine(70, 24, 128, 24, SSD1306_WHITE);
}