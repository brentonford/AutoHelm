/*
 * GPSReceiver.cpp
 * 
 * Implementation of Bluetooth GPS waypoint receiver
 */

#include "GPSReceiver.h"

GPSReceiver::GPSReceiver() : 
    gpsService("0000FFE0-0000-1000-8000-00805F9B34FB"),
    gpsCharacteristic("0000FFE1-0000-1000-8000-00805F9B34FB", BLEWrite, 256),
    statusCharacteristic("0000FFE2-0000-1000-8000-00805F9B34FB", BLENotify, 512),
    calibrationCommandCharacteristic("0000FFE3-0000-1000-8000-00805F9B34FB", BLEWrite, 64),
    calibrationDataCharacteristic("0000FFE4-0000-1000-8000-00805F9B34FB", BLENotify, 256) {
    targetLatitude = 0.0;
    targetLongitude = 0.0;
    targetAltitude = 0.0;
    hasValidTarget = false;
    inputBuffer = "";
    calibrationMode = false;
    navigationEnabled = true;
}

bool GPSReceiver::begin(const char* deviceName) {
    if (!BLE.begin()) {
        Serial.println("Starting BLE failed!");
        return false;
    }
    
    BLE.setLocalName(deviceName);
    BLE.setAdvertisedService(gpsService);
    gpsService.addCharacteristic(gpsCharacteristic);
    gpsService.addCharacteristic(statusCharacteristic);
    gpsService.addCharacteristic(calibrationCommandCharacteristic);
    gpsService.addCharacteristic(calibrationDataCharacteristic);
    BLE.addService(gpsService);
    BLE.advertise();
    
    Serial.println("BLE GPS Receiver active, waiting for connections...");
    Serial.print("Device name: ");
    Serial.println(deviceName);
    
    return true;
}

void GPSReceiver::update() {
    BLE.poll();
    
    BLEDevice central = BLE.central();
    
    static bool wasConnected = false;
    bool currentlyConnected = central;
    
    // Check for connection status changes
    if (currentlyConnected != wasConnected) {
        if (currentlyConnected) {
            playAppConnected();
        } else if (wasConnected) {
            playAppDisconnected();
        }
        wasConnected = currentlyConnected;
    }
    
    if (central) {
        if (calibrationCommandCharacteristic.written()) {
            handleCalibrationCommand();
        }
        
        if (gpsCharacteristic.written()) {
            int length = gpsCharacteristic.valueLength();
            const uint8_t* value = gpsCharacteristic.value();
            
            for (int i = 0; i < length; i++) {
                char receivedChar = (char)value[i];
                
                if (receivedChar == '\n') {
                    if (inputBuffer.length() > 0) {
                        parseGPSData(inputBuffer);
                        inputBuffer = "";
                    }
                } else {
                    inputBuffer += receivedChar;
                }
            }
        }
    }
}

void GPSReceiver::parseGPSData(String data) {
    if (!data.startsWith("$GPS,") || !data.endsWith("*")) {
        return;
    }
    
    data = data.substring(5, data.length() - 1);
    
    int firstComma = data.indexOf(',');
    if (firstComma == -1) {
        return;
    }
    
    int secondComma = data.indexOf(',', firstComma + 1);
    if (secondComma == -1) {
        return;
    }
    
    String latStr = data.substring(0, firstComma);
    String lonStr = data.substring(firstComma + 1, secondComma);
    String altStr = data.substring(secondComma + 1);
    
    targetLatitude = latStr.toDouble();
    targetLongitude = lonStr.toDouble();
    targetAltitude = altStr.toDouble();
    hasValidTarget = true;
    
    Serial.print("Target received - Lat: ");
    Serial.print(targetLatitude, 6);
    Serial.print(" Lon: ");
    Serial.print(targetLongitude, 6);
    Serial.print(" Alt: ");
    Serial.println(targetAltitude, 2);
}

bool GPSReceiver::hasTarget() {
    return hasValidTarget;
}

double GPSReceiver::getLatitude() {
    return targetLatitude;
}

double GPSReceiver::getLongitude() {
    return targetLongitude;
}

double GPSReceiver::getAltitude() {
    return targetAltitude;
}

void GPSReceiver::clearTarget() {
    hasValidTarget = false;
    targetLatitude = 0.0;
    targetLongitude = 0.0;
    targetAltitude = 0.0;
}

bool GPSReceiver::isConnected() {
    return BLE.central();
}

void GPSReceiver::sendNavigationStatus(bool hasGpsFix, int satellites, double currentLat, double currentLon,
                                       double altitude, float heading, float distance, float bearing,
                                       double targetLat, double targetLon, bool isNavigating, bool hasReachedDestination) {
    if (!BLE.central()) {
        return;
    }
    
    String statusJson = "{";
    statusJson += "\"hasGpsFix\":" + String(hasGpsFix ? "true" : "false") + ",";
    statusJson += "\"satellites\":" + String(satellites) + ",";
    statusJson += "\"currentLat\":" + String(currentLat, 6) + ",";
    statusJson += "\"currentLon\":" + String(currentLon, 6) + ",";
    statusJson += "\"altitude\":" + String(altitude, 2) + ",";
    statusJson += "\"heading\":" + String(heading, 1) + ",";
    statusJson += "\"distance\":" + String(distance, 1) + ",";
    statusJson += "\"bearing\":" + String(bearing, 1) + ",";
    statusJson += "\"targetLat\":" + String(targetLat, 6) + ",";
    statusJson += "\"targetLon\":" + String(targetLon, 6);
    statusJson += "}";
    
    statusCharacteristic.writeValue(statusJson.c_str());
}

void GPSReceiver::handleCalibrationCommand() {
    if (!BLE.central()) return;
    
    int length = calibrationCommandCharacteristic.valueLength();
    const uint8_t* value = calibrationCommandCharacteristic.value();
    
    if (length > 0) {
        String command = String((char*)value).substring(0, length);
        command.trim();
        
        if (command == "START_CAL") {
            calibrationMode = true;
            Serial.println("Calibration mode started");
        } else if (command == "STOP_CAL") {
            calibrationMode = false;
            Serial.println("Calibration mode stopped");
        } else if (command.startsWith("SAVE_CAL:")) {
            // Parse calibration values and save them
            Serial.println("Calibration values received: " + command);
            calibrationMode = false;
        } else if (command == "NAV_ENABLE") {
            navigationEnabled = true;
            Serial.println("Navigation enabled");
        } else if (command == "NAV_DISABLE") {
            navigationEnabled = false;
            Serial.println("Navigation disabled");
        }
    }
}

void GPSReceiver::sendCalibrationData(float x, float y, float z, float minX, float minY, float minZ, float maxX, float maxY, float maxZ) {
    if (!BLE.central() || !calibrationMode) return;
    
    String calData = "{\"x\":" + String(x, 3) + ",\"y\":" + String(y, 3) + ",\"z\":" + String(z, 3) + ",";
    calData += "\"minX\":" + String(minX, 3) + ",\"minY\":" + String(minY, 3) + ",\"minZ\":" + String(minZ, 3) + ",";
    calData += "\"maxX\":" + String(maxX, 3) + ",\"maxY\":" + String(maxY, 3) + ",\"maxZ\":" + String(maxZ, 3) + "}";
    
    calibrationDataCharacteristic.writeValue(calData.c_str());
}

bool GPSReceiver::isCalibrationMode() {
    return calibrationMode;
}

void GPSReceiver::setCalibrationMode(bool enabled) {
    calibrationMode = enabled;
}

void GPSReceiver::setNavigationEnabled(bool enabled) {
    navigationEnabled = enabled;
}

bool GPSReceiver::isNavigationEnabled() {
    return navigationEnabled;
}