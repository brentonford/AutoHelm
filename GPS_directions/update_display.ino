void updateDisplay(GPSData gpsData, float heading, float distance, float bearing) {
    display.clearDisplay();
    
    if (!gpsData.has_fix) {
        display.setTextSize(1);
        display.setTextColor(SSD1306_WHITE);
        display.setCursor(14, 20);
        display.print("Waiting for GPS");
        display.setCursor(44, 35);
        display.print("No Fix");
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
    
    display.setCursor(64, 30);
    display.print(DESTINATION_LAT, 6);
    display.setCursor(64, 40);
    display.print(DESTINATION_LON, 6);
    
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