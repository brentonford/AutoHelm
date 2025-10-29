#include "DisplayManager.h"

DisplayManager::DisplayManager() : display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire1, OLED_RESET), initialized(false) {
}

bool DisplayManager::begin() {
    // Will throw exception if I2C communication fails
    if (!display.begin(SSD1306_SWITCHCAPVCC, SystemConfig::SCREEN_ADDRESS)) {
        initialized = false;
        return false;
    }
    
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 0);
    initialized = true;
    return true;
}

void DisplayManager::showStartupScreen() {
    if (!initialized) return;
    
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(0, 10);
    display.println("Helm System");
    display.setTextSize(1);
    display.setCursor(0, 35);
    display.println("Starting...");
    display.display();
    delay(2000);
}

void DisplayManager::showStatus(const char* message) {
    if (!initialized) return;
    
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println(message);
    display.display();
}

void DisplayManager::updateGPSDisplay(const GPSData& data) {
    if (!initialized) return;
    
    display.clearDisplay();
    
    drawSatelliteCount(data.satellites);
    
    if (data.hasFix) {
        drawCoordinates(data.latitude, data.longitude);
        
        // Show altitude if available
        display.setCursor(0, 56);
        display.print("Alt: ");
        display.print(data.altitude, 1);
        display.print("m");
    } else {
        display.setCursor(0, 16);
        display.println("No GPS Fix");
        display.setCursor(0, 32);
        display.println("Searching...");
    }
    
    display.display();
}

void DisplayManager::drawCoordinates(float lat, float lon) {
    display.setCursor(0, 16);
    display.println(lat, 6);
    display.setCursor(0, 32);
    display.println(lon, 6);
}

void DisplayManager::showCompassHeading(float heading) {
    if (!initialized) return;
    
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println("Compass Heading:");
    
    display.setTextSize(2);
    display.setCursor(0, 20);
    display.print(heading, 1);
    display.println("°");
    
    display.display();
}

void DisplayManager::updateGPSAndCompass(const GPSData& data, float heading) {
    if (!initialized) return;
    
    display.clearDisplay();
    
    drawSatelliteCount(data.satellites);
    
    // Show compass heading in top right
    display.setCursor(80, 0);
    display.cp437(true);
    display.print(heading, 0);
    display.write(0xF8);
    
    if (data.hasFix) {
        drawCoordinates(data.latitude, data.longitude);
        
        // Show altitude
        display.setCursor(0, 56);
        display.print("Alt: ");
        display.print(data.altitude, 1);
        display.print("m");
    } else {
        display.setCursor(0, 16);
        display.println("No GPS Fix");
        display.setCursor(0, 32);
        display.println("Searching...");
    }
    
    display.display();
}

void DisplayManager::drawSatelliteCount(int count) {
    display.setCursor(0, 0);
    display.print("GPS: ");
    display.print(count);
    display.print(" sats");
}