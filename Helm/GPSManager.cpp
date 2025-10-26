#include "GPSManager.h"

GPSManager::GPSManager() : gpsSerial(nullptr), previousFixStatus(false) {
}

void GPSManager::begin() {
    gpsSerial = new SoftwareSerial(SystemConfig::GPS_RX_PIN, SystemConfig::GPS_TX_PIN);
    gpsSerial->begin(9600);
    Serial.println("GPS initialised!");
}

void GPSManager::update() {
    currentData = parseGPS();
}

GPSData GPSManager::getCurrentData() const {
    return currentData;
}

bool GPSManager::hasFixStatusChanged() {
    bool changed = (currentData.hasFix != previousFixStatus);
    previousFixStatus = currentData.hasFix;
    return changed;
}

void GPSManager::printDebugInfo(float heading) {
    static unsigned long lastDebugOutput = 0;
    unsigned long currentTime = millis();
    
    if (currentTime - lastDebugOutput < 2000) {
        return;
    }

    Serial.print("Time: ");
    Serial.print(currentData.time);
    Serial.print(", Satellites: ");
    Serial.print(currentData.satellites);
    Serial.print(", Position: ");
    Serial.print(currentData.latitude, 6);
    Serial.print(", ");
    Serial.print(currentData.longitude, 6);
    Serial.print(", Altitude: ");
    Serial.print(currentData.altitude);
    Serial.print(" m, Fix: ");
    Serial.print(currentData.hasFix ? "Yes" : "No");
    Serial.print(", Heading: ");
    Serial.println(heading);

    lastDebugOutput = currentTime;
}

GPSData GPSManager::parseGPS() {
    GPSData data;
    data.hasFix = false;
    data.satellites = 0;
    data.latitude = 0.0;
    data.longitude = 0.0;
    data.altitude = 0.0;
    data.time = "";
    return data;
}