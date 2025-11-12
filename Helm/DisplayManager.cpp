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

void DisplayManager::drawNavigationArrow(float relativeAngle) {
    if (!initialized) return;
    
    // Arrow center position
    int centerX = 64;
    int centerY = 32;
    int arrowLength = 20;
    
    // Convert relative angle to radians
    float angleRad = (relativeAngle - 90.0) * PI / 180.0;
    
    // Calculate arrow tip position
    int tipX = centerX + arrowLength * cos(angleRad);
    int tipY = centerY + arrowLength * sin(angleRad);
    
    // Calculate arrow base positions
    float baseAngle1 = angleRad + (150.0 * PI / 180.0);
    float baseAngle2 = angleRad - (150.0 * PI / 180.0);
    int baseLength = 12;
    
    int base1X = centerX + baseLength * cos(baseAngle1);
    int base1Y = centerY + baseLength * sin(baseAngle1);
    int base2X = centerX + baseLength * cos(baseAngle2);
    int base2Y = centerY + baseLength * sin(baseAngle2);
    
    // Draw arrow lines
    display.drawLine(centerX, centerY, tipX, tipY, SSD1306_WHITE);
    display.drawLine(tipX, tipY, base1X, base1Y, SSD1306_WHITE);
    display.drawLine(tipX, tipY, base2X, base2Y, SSD1306_WHITE);
}

void DisplayManager::drawCompass(float heading) {
    if (!initialized) return;
    
    // Draw compass circle
    int compassX = 100;
    int compassY = 16;
    int compassRadius = 12;
    
    display.drawCircle(compassX, compassY, compassRadius, SSD1306_WHITE);
    
    // Draw north indicator
    float northAngle = (-heading - 90.0) * PI / 180.0;
    int northX = compassX + (compassRadius - 3) * cos(northAngle);
    int northY = compassY + (compassRadius - 3) * sin(northAngle);
    display.drawLine(compassX, compassY, northX, northY, SSD1306_WHITE);
}

void DisplayManager::updateNavigationDisplay(const NavigationState& nav, float heading) {
    if (!initialized) return;

    display.clearDisplay();

    // Navigation status in top left
    display.setCursor(0, 0);
    switch(nav.mode) {
        case NavigationMode::IDLE:
            display.print("NAV: IDLE");
            break;
        case NavigationMode::NAVIGATING:
            display.print("NAV: ACTIVE");
            // Show target coordinates
            display.setCursor(0, 24);
            display.print("TGT:");
            display.println(nav.targetLatitude, 4);
            display.print("    ");
            display.println(nav.targetLongitude, 4);
            break;
        case NavigationMode::ARRIVED:
            display.print("ARRIVED!");
            break;
    }
    
    // Draw compass in top right
    drawCompass(heading);
    
    // Draw navigation arrow if navigating
    if (nav.mode == NavigationMode::NAVIGATING) {
        drawNavigationArrow(nav.relativeAngle);
    }
    
    // Distance to target (bottom left)
    if (nav.mode != NavigationMode::IDLE) {
        display.setCursor(0, 48);
        if (nav.distanceToTarget >= 1000.0) {
            display.print(nav.distanceToTarget / 1000.0, 1);
            display.print("km");
        } else {
            display.print(nav.distanceToTarget, 0);
            display.print("m");
        }
    }
    
    // Bearing to target (bottom right)
    if (nav.mode != NavigationMode::IDLE) {
        display.setCursor(70, 48);
        display.print(nav.bearingToTarget, 0);
        display.cp437(true);
        display.write(0xF8);
    }
    
    // Current heading (bottom center)
    display.setCursor(0, 56);
    display.print("HDG: ");
    display.print(heading, 0);
    display.cp437(true);
    display.write(0xF8);
    
    display.display();
}