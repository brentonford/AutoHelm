#include "GPSManager.h"
#include <Arduino.h>

GPSManager::GPSManager(int rxPin, int txPin) : gpsSerial(rxPin, txPin), bufferIndex(0) {
    currentData.latitude = 0.0;
    currentData.longitude = 0.0;
    currentData.altitude = 0.0;
    currentData.satellites = 0;
    currentData.hasFix = false;
    currentData.timestamp = 0;
}

bool GPSManager::begin() {
    gpsSerial.begin(9600);
    return true;
}

void GPSManager::update() {
    while (gpsSerial.available()) {
        char c = gpsSerial.read();
        
        if (c == '$') {
            bufferIndex = 0;
        }
        
        if (bufferIndex < sizeof(nmeaBuffer) - 1) {
            nmeaBuffer[bufferIndex++] = c;
        }
        
        if (c == '\n') {
            nmeaBuffer[bufferIndex] = '\0';
            parseNMEA(nmeaBuffer);
            bufferIndex = 0;
        }
    }
}

void GPSManager::parseNMEA(const char* sentence) {
    if (!isValidChecksum(sentence)) {
        return;
    }
    
    Serial.print("GPS: ");
    Serial.println(sentence);
    
    if (strncmp(sentence, "$GPGGA", 6) == 0 || strncmp(sentence, "$GNGGA", 6) == 0) {
        parseGGA(sentence);
    }
    else if (strncmp(sentence, "$GPRMC", 6) == 0 || strncmp(sentence, "$GNRMC", 6) == 0) {
        parseRMC(sentence);
    }
}

void GPSManager::parseGGA(const char* data) {
    char* tokens[15];
    char buffer[128];
    strcpy(buffer, data);
    
    int tokenCount = 0;
    char* token = strtok(buffer, ",");
    while (token != NULL && tokenCount < 15) {
        tokens[tokenCount++] = token;
        token = strtok(NULL, ",");
    }
    
    if (tokenCount >= 13) {
        // Fix quality (token 6)
        int fixQuality = atoi(tokens[6]);
        currentData.hasFix = (fixQuality > 0);
        
        if (currentData.hasFix) {
            // Latitude (tokens 2,3)
            currentData.latitude = parseCoordinate(tokens[2], tokens[3][0]);
            
            // Longitude (tokens 4,5)
            currentData.longitude = parseCoordinate(tokens[4], tokens[5][0]);
            
            // Satellites (token 7)
            currentData.satellites = atoi(tokens[7]);
            
            // Altitude (token 9)
            currentData.altitude = atof(tokens[9]);
            
            currentData.timestamp = millis();
        }
    }
}

void GPSManager::parseRMC(const char* data) {
    // RMC parsing for additional data if needed in future
}

bool GPSManager::isValidChecksum(const char* sentence) {
    if (strlen(sentence) < 4) return false;
    
    // Find checksum position
    const char* checksumPos = strrchr(sentence, '*');
    if (!checksumPos) return false;
    
    // Calculate checksum
    uint8_t checksum = 0;
    for (const char* p = sentence + 1; p < checksumPos; p++) {
        checksum ^= *p;
    }
    
    // Parse received checksum
    uint8_t receivedChecksum = strtol(checksumPos + 1, NULL, 16);
    
    return checksum == receivedChecksum;
}

float GPSManager::parseCoordinate(const char* coord, char direction) {
    if (strlen(coord) == 0) return 0.0;
    
    float value = atof(coord);
    int degrees = (int)(value / 100);
    float minutes = value - (degrees * 100);
    
    float result = degrees + (minutes / 60.0);
    
    if (direction == 'S' || direction == 'W') {
        result = -result;
    }
    
    return result;
}

GPSData GPSManager::getData() const {
    return currentData;
}