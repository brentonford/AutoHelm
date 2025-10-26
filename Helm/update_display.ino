void updateDisplay(GPSData gpsData, float heading, float distance, float bearing, bool isConnected, bool isNavigating, bool hasReachedDestination) {
    display.clearDisplay();
    
    if (!gpsData.has_fix) {
        display.setTextColor(SSD1306_WHITE);
        display.setCursor(44, 5);
        display.print("NO FIX!");
        display.setTextSize(1);
        display.setCursor(10, 30);
        display.print("Waiting for GPS...");
        display.setCursor(24, 50);
        display.print("Satellites: ");
        display.print(gpsData.satellites);
        display.display();
        return;
    }
    
    float relativeAngle = fmod((bearing - heading + 360.0), 360.0);
    
    draw_arrow(relativeAngle, 30, 26, 26);
    
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    
    // Status icons at top right
    int iconX = 110;
    int iconY = 2;
    
    // Connection status icon
    if (isConnected) {
        // Connected - small wifi icon
        display.drawPixel(iconX, iconY + 2, SSD1306_WHITE);
        display.drawPixel(iconX + 1, iconY + 1, SSD1306_WHITE);
        display.drawPixel(iconX + 2, iconY, SSD1306_WHITE);
        display.drawPixel(iconX + 3, iconY + 1, SSD1306_WHITE);
        display.drawPixel(iconX + 4, iconY + 2, SSD1306_WHITE);
    }
    iconX += 8;
    
    // Navigation status icon
    if (hasReachedDestination) {
        // Destination reached - checkmark
        display.drawPixel(iconX, iconY + 2, SSD1306_WHITE);
        display.drawPixel(iconX + 1, iconY + 3, SSD1306_WHITE);
        display.drawPixel(iconX + 2, iconY + 2, SSD1306_WHITE);
        display.drawPixel(iconX + 3, iconY + 1, SSD1306_WHITE);
        display.drawPixel(iconX + 4, iconY, SSD1306_WHITE);
    } else if (isNavigating) {
        // Navigating - small arrow
        display.drawPixel(iconX + 2, iconY, SSD1306_WHITE);
        display.drawPixel(iconX + 1, iconY + 1, SSD1306_WHITE);
        display.drawPixel(iconX + 2, iconY + 1, SSD1306_WHITE);
        display.drawPixel(iconX + 3, iconY + 1, SSD1306_WHITE);
        display.drawPixel(iconX + 2, iconY + 2, SSD1306_WHITE);
        display.drawPixel(iconX + 2, iconY + 3, SSD1306_WHITE);
        display.drawPixel(iconX + 2, iconY + 4, SSD1306_WHITE);
    }
    
    if (distance >= 1000) {
        display.setCursor(4, 57);
        display.print(distance/1000, 1);
        display.print(" km");
    } else {
        display.setCursor(4, 57);
        display.print((int)distance);
        display.print(" m");
    }
    
    display.setCursor(94, 57);
    display.print(gpsData.altitude, 1);
    
    display.setCursor(64, 2);
    display.print(gpsData.latitude, 6);
    display.setCursor(64, 12);
    display.print(gpsData.longitude, 6);
    
    // Only show destination coordinates when navigating
    if (isNavigating || hasReachedDestination) {
        display.setCursor(64, 30);
        display.print(DESTINATION_LAT, 6);
        display.setCursor(64, 40);
        display.print(DESTINATION_LON, 6);
    }
    
    display.drawLine(47, 0, 58, 11, SSD1306_WHITE);
    display.drawLine(58, 11, 58, 38, SSD1306_WHITE);
    display.drawLine(58, 38, 47, 49, SSD1306_WHITE);
    display.drawLine(0, 11, 11, 0, SSD1306_WHITE);
    display.drawLine(0, 11, 0, 38, SSD1306_WHITE);          
    display.drawLine(0, 38, 11, 49, SSD1306_WHITE);
    
    display.drawLine(86, 54, 86, 64, SSD1306_WHITE);
    display.drawLine(86, 54, 128, 54, SSD1306_WHITE);
    
    display.drawLine(70, 24, 128, 24, SSD1306_WHITE);
    
    display.display();
}