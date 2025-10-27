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
    navigationEnabled = false;
}

bool GPSReceiver::begin(const char* deviceName) {
    Serial.println("Starting BLE GPS Receiver initialization...");
    
    // Initialize BLE with multiple attempts
    int bleAttempts = 0;
    bool bleSuccess = false;
    
    while (bleAttempts < 3 && !bleSuccess) {
        Serial.print("BLE init attempt ");
        Serial.println(bleAttempts + 1);
        
        if (BLE.begin()) {
            bleSuccess = true;
            Serial.println("BLE initialization successful!");
        } else {
            Serial.print("BLE init failed on attempt ");
            Serial.println(bleAttempts + 1);
            delay(1000);
        }
        bleAttempts++;
    }
    
    if (!bleSuccess) {
        Serial.println("BLE initialization failed - all attempts exhausted");
        return false;
    }
    
    // Set device name and local name
    BLE.setLocalName(deviceName);
    BLE.setDeviceName(deviceName);
    
    Serial.print("Setting device name: ");
    Serial.println(deviceName);
    
    // Add characteristics to service
    gpsService.addCharacteristic(gpsCharacteristic);
    gpsService.addCharacteristic(statusCharacteristic);
    gpsService.addCharacteristic(calibrationCommandCharacteristic);
    gpsService.addCharacteristic(calibrationDataCharacteristic);
    
    // Add service to BLE
    BLE.addService(gpsService);
    
    // Set advertised service UUID
    BLE.setAdvertisedService(gpsService);
    
    // Configure advertising parameters for better discoverability
    BLE.setAdvertisingInterval(160); // 100ms intervals for faster discovery
    BLE.setConnectable(true);
    
    // Start advertising
    bool advertiseSuccess = BLE.advertise();
    if (!advertiseSuccess) {
        Serial.println("Failed to start BLE advertising!");
        return false;
    }
    
    Serial.println("BLE GPS Receiver active, waiting for connections...");
    Serial.print("Device name: ");
    Serial.println(deviceName);
    Serial.print("Service UUID: ");
    Serial.println("0000FFE0-0000-1000-8000-00805F9B34FB");
    Serial.println("Ready for iOS app connection...");
    
    return true;
}

void GPSReceiver::update() {
    BLE.poll();
    
    BLEDevice central = BLE.central();
    
    static bool wasConnected = false;
    static unsigned long lastConnectionCheck = 0;
    bool currentlyConnected = central;
    
    // Periodic connection status logging
    if (millis() - lastConnectionCheck > 10000) { // Every 10 seconds
        if (currentlyConnected) {
            Serial.println("BLE Status: Connected to central device");
            Serial.print("Central address: ");
            Serial.println(central.address());
        } else {
            Serial.println("BLE Status: Advertising, waiting for connection...");
            // Restart advertising if needed
            if (!BLE.advertise()) {
                Serial.println("Restarting BLE advertising...");
                BLE.advertise();
            }
        }
        lastConnectionCheck = millis();
    }
    
    // Check for connection status changes
    if (currentlyConnected != wasConnected) {
        if (currentlyConnected) {
            Serial.println("BLE: Device connected!");
            Serial.print("Connected to: ");
            Serial.println(central.address());
            playAppConnected();
        } else if (wasConnected) {
            Serial.println("BLE: Device disconnected!");
            playAppDisconnected();
            // Restart advertising after disconnect
            delay(100);
            BLE.advertise();
        }
        wasConnected = currentlyConnected;
    }
    
    if (central) {
        if (calibrationCommandCharacteristic.written()) {
            Serial.println("Calibration command received");
            handleCalibrationCommand();
        }
        
        if (gpsCharacteristic.written()) {
            Serial.println("GPS data received");
            int length = gpsCharacteristic.valueLength();
            const uint8_t* value = gpsCharacteristic.value();
            
            Serial.print("Received data length: ");
            Serial.println(length);
            
            for (int i = 0; i < length; i++) {
                char receivedChar = (char)value[i];
                
                if (receivedChar == '\n') {
                    if (inputBuffer.length() > 0) {
                        Serial.print("Processing GPS data: ");
                        Serial.println(inputBuffer);
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
    Serial.print("Parsing GPS data: ");
    Serial.println(data);
    
    if (!data.startsWith("$GPS,") || !data.endsWith("*")) {
        Serial.println("Invalid GPS data format - missing header/footer");
        return;
    }
    
    data = data.substring(5, data.length() - 1);
    
    int firstComma = data.indexOf(',');
    if (firstComma == -1) {
        Serial.println("Invalid GPS data format - missing first comma");
        return;
    }
    
    int secondComma = data.indexOf(',', firstComma + 1);
    if (secondComma == -1) {
        Serial.println("Invalid GPS data format - missing second comma");
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
        
        Serial.print("Calibration command: ");
        Serial.println(command);
        
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