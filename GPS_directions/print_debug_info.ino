void printDebugInfo(GPSData gpsData, float heading) {
    Serial.print("Satellites: ");
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
}