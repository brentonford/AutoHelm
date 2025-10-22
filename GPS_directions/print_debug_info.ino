void printDebugInfo(GPSData gpsData, float heading) {
    static unsigned long lastAdjustment = 0;
    unsigned long currentTime = millis();
    
    if (currentTime - lastAdjustment < 2000) {
        return;
    }

    Serial.print("Time: ");
    Serial.print(gpsData.time);
    Serial.print(", Satellites: ");
    Serial.print(gpsData.satellites);
    Serial.print(", Position: ");
    Serial.print(gpsData.latitude, 6);
    Serial.print(", ");
    Serial.print(gpsData.longitude, 6);
    Serial.print(", Altitude: ");
    Serial.print(gpsData.altitude);
    Serial.print(" m, Fix: ");
    Serial.print(gpsData.has_fix ? "Yes" : "No");
    Serial.print(", Heading: ");
    Serial.println(heading);

    lastAdjustment = currentTime;
}