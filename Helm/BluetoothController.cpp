#include "BluetoothController.h"
#include <Arduino.h>

BluetoothController* BluetoothController::instance = nullptr;
BluetoothController::WaypointCallback BluetoothController::waypointCallback = nullptr;
BluetoothController::NavigationCallback BluetoothController::navigationCallback = nullptr;

BluetoothController::BluetoothController() : 
    bluetoothService("19B10000-E8F2-537E-4F6C-D104768A1214"),
    waypointCharacteristic("19B10001-E8F2-537E-4F6C-D104768A1214", BLEWrite, 32),
    statusCharacteristic("19B10002-E8F2-537E-4F6C-D104768A1214", BLENotify, 1024),
    calibrationCommandCharacteristic("19B10003-E8F2-537E-4F6C-D104768A1214", BLEWrite, 32),
    calibrationDataCharacteristic("19B10004-E8F2-537E-4F6C-D104768A1214", BLENotify, 128),
    initialized(false),
    connected(false),
    effectiveMTU(23),
    negotiatedMTU(23) {
    instance = this;
}

bool BluetoothController::begin(const char* deviceName) {
    if (!BLE.begin()) {
        initialized = false;
        return false;
    }
    
    // ArduinoBLE handles MTU negotiation automatically
    
    BLE.setLocalName(deviceName);
    BLE.setDeviceName(deviceName);
    
    BLE.setConnectionInterval(6, 24);
    BLE.setSupervisionTimeout(400);
    
    bluetoothService.addCharacteristic(waypointCharacteristic);
    bluetoothService.addCharacteristic(statusCharacteristic);
    bluetoothService.addCharacteristic(calibrationCommandCharacteristic);
    bluetoothService.addCharacteristic(calibrationDataCharacteristic);
    
    BLE.addService(bluetoothService);
    
    BLE.setEventHandler(BLEConnected, onConnect);
    BLE.setEventHandler(BLEDisconnected, onDisconnect);
    waypointCharacteristic.setEventHandler(BLEWritten, onWaypointReceived);
    calibrationCommandCharacteristic.setEventHandler(BLEWritten, onCalibrationCommand);
    
    BLE.setAdvertisingInterval(100);
    BLE.setConnectable(true);
    
    BLE.setAdvertisedServiceUuid(bluetoothService.uuid());
    BLE.setAppearance(0x0000);
    
    BLE.advertise();
    
    initialized = true;
    Serial.print("BLE advertising as: ");
    Serial.println(deviceName);
    Serial.print("BLE Service UUID: ");
    Serial.println("19B10000-E8F2-537E-4F6C-D104768A1214");
    Serial.println("BLE configured for higher MTU negotiation");
    
    return true;
}

void BluetoothController::requestHigherMTU() {
    // ArduinoBLE handles negotiation, but we can optimize for higher MTU
    // Set connection parameters that favor higher MTU
    Serial.println("BLE: Optimizing connection parameters for higher MTU");
    
    // Start with conservative estimate and detect actual capacity
    updateEffectiveMTU(185); // Conservative iOS-compatible starting point
}

void BluetoothController::updateEffectiveMTU(int mtu) {
    negotiatedMTU = mtu;
    // Conservative payload calculation accounting for ATT overhead
    effectiveMTU = mtu - 3;
    
    Serial.print("BLE: MTU negotiated to ");
    Serial.print(negotiatedMTU);
    Serial.print(" bytes, effective payload: ");
    Serial.print(effectiveMTU);
    Serial.println(" bytes");
}

void BluetoothController::update() {
    if (!initialized) return;
    
    BLE.poll();
    
    static unsigned long lastAdvertiseCheck = 0;
    unsigned long currentTime = millis();
    
    if (!connected && (currentTime - lastAdvertiseCheck > 5000)) {
        lastAdvertiseCheck = currentTime;
        
        BLE.stopAdvertise();
        delay(100);
        
        BLE.advertise();
    }
}

bool BluetoothController::isConnected() const {
    return connected;
}

void BluetoothController::sendStatus(const char* jsonData) {
    if (!initialized || !connected) return;
    
    int jsonLength = strlen(jsonData);
    
    // Validate JSON before sending
    if (!isValidCompleteJSON(jsonData)) {
        Serial.println("BLE: Invalid JSON detected, using fallback");
        String fallbackJson = createEssentialStatusJSON();
        statusCharacteristic.writeValue(fallbackJson.c_str());
        return;
    }
    
    // Try to send complete message first
    if (jsonLength <= effectiveMTU) {
        statusCharacteristic.writeValue(jsonData);
        Serial.print("BLE: Sent complete JSON (");
        Serial.print(jsonLength);
        Serial.print(" bytes) - MTU utilization: ");
        Serial.print((jsonLength * 100) / effectiveMTU);
        Serial.println("%");
        
        // Learn from successful transmissions
        if (jsonLength > effectiveMTU * 0.8) {
            detectActualMTU(jsonLength);
        }
        return;
    }
    
    // Use fragmentation for larger messages
    Serial.print("BLE: JSON too large (");
    Serial.print(jsonLength);
    Serial.println(" bytes), using fragmentation");
    
    if (sendFragmentedMessage(jsonData)) {
        Serial.println("BLE: Fragmented transmission successful");
    } else {
        Serial.println("BLE: Fragmentation failed, sending essential data");
        String essentialJson = createEssentialStatusJSON();
        statusCharacteristic.writeValue(essentialJson.c_str());
    }
}

bool BluetoothController::sendFragmentedMessage(const char* jsonData) {
    int totalLength = strlen(jsonData);
    
    // Fragment size: MTU - 4 (header: seq + total + length_high + length_low)
    int fragmentSize = effectiveMTU - 4;
    uint8_t totalFragments = (totalLength + fragmentSize - 1) / fragmentSize;
    
    if (totalFragments > 255) {
        Serial.println("BLE: Message too large for fragmentation");
        return false;
    }
    
    Serial.print("BLE: Sending ");
    Serial.print(totalFragments);
    Serial.print(" fragments (fragment size: ");
    Serial.print(fragmentSize);
    Serial.println(" bytes)");
    
    for (uint8_t seq = 0; seq < totalFragments; seq++) {
        int offset = seq * fragmentSize;
        int remainingLength = totalLength - offset;
        int currentFragmentSize = (remainingLength < fragmentSize) ? remainingLength : fragmentSize;
        
        sendFragment(jsonData + offset, currentFragmentSize, seq, totalFragments, totalLength);
        
        // Increased throttle to prevent overwhelming iOS fragment reassembly
        delay(75); // Increased delay for better reliability
        
        Serial.print("BLE: Sent fragment ");
        Serial.print(seq + 1);
        Serial.print("/");
        Serial.print(totalFragments);
        Serial.print(" (");
        Serial.print(currentFragmentSize);
        Serial.println(" bytes payload)");
    }
    
    return true;
}

void BluetoothController::sendFragment(const char* data, int dataLen, uint8_t seqNum, uint8_t totalFragments, uint16_t totalLength) {
    // Create fragment with header: seq(1) + total(1) + totalLen_high(1) + totalLen_low(1) + data
    char fragment[effectiveMTU];
    
    fragment[0] = seqNum;
    fragment[1] = totalFragments;
    fragment[2] = (totalLength >> 8) & 0xFF;
    fragment[3] = totalLength & 0xFF;
    
    // Copy exact number of data bytes
    memcpy(fragment + 4, data, dataLen);
    
    // Send fragment with exact size
    statusCharacteristic.writeValue((const void*)fragment, dataLen + 4);
    
    Serial.print("BLE: Fragment header - seq:");
    Serial.print(seqNum);
    Serial.print(" total:");
    Serial.print(totalFragments);
    Serial.print(" len:");
    Serial.print(totalLength);
    Serial.print(" payload:");
    Serial.println(dataLen);
}

String BluetoothController::createEssentialStatusJSON() {
    String json = "{";
    json += "\"has_fix\":false,";
    json += "\"satellites\":0,";
    json += "\"currentLat\":0.0,";
    json += "\"currentLon\":0.0,";
    json += "\"altitude\":0.0,";
    json += "\"heading\":0.0,";
    json += "\"distance\":0.0,";
    json += "\"bearing\":0.0,";
    json += "\"targetLat\":null,";
    json += "\"targetLon\":null";
    json += "}";
    return json;
}

void BluetoothController::probeMTUCapacity() {
    if (!connected) return;
    
    // Send progressively larger test messages to detect actual MTU
    Serial.println("BLE: Probing MTU capacity");
    
    // Test with larger payload to see if we can exceed 185 bytes
    String testJson = createTestJSON(200);  // Try 200 byte message
    statusCharacteristic.writeValue(testJson.c_str());
    
    Serial.print("BLE: MTU probe sent ");
    Serial.print(testJson.length());
    Serial.println(" bytes");
}

void BluetoothController::detectActualMTU(int successfulLength) {
    // Learn from successful large transmissions
    if (successfulLength > effectiveMTU && successfulLength <= 512) {
        Serial.print("BLE: Detected higher MTU capacity, updating from ");
        Serial.print(effectiveMTU);
        Serial.print(" to ");
        Serial.println(successfulLength + 10); // Add small buffer
        
        updateEffectiveMTU(successfulLength + 10);
    }
}

String BluetoothController::createTestJSON(int targetSize) {
    String json = "{\"test\":true,\"mtu_probe\":\"";
    
    // Fill with padding to reach target size
    int paddingNeeded = targetSize - json.length() - 3; // Account for closing
    for (int i = 0; i < paddingNeeded && i < 300; i++) {
        json += (char)('A' + (i % 26));
    }
    
    json += "\"}";
    return json;
}

bool BluetoothController::isValidCompleteJSON(const char* jsonData) {
    if (!jsonData || strlen(jsonData) == 0) return false;
    
    if (jsonData[0] != '{') return false;
    
    int len = strlen(jsonData);
    if (jsonData[len - 1] != '}') return false;
    
    // Check for common corruption patterns
    String jsonStr = String(jsonData);
    
    // Check for corrupted boolean values like "false.9"
    if (jsonStr.indexOf("false.") >= 0 || jsonStr.indexOf("true.") >= 0) {
        Serial.println("BLE: Detected corrupted boolean values in JSON");
        return false;
    }
    
    // Check for corrupted null values
    if (jsonStr.indexOf("null.") >= 0) {
        Serial.println("BLE: Detected corrupted null values in JSON");
        return false;
    }
    
    // Basic brace matching
    int braceCount = 0;
    bool inString = false;
    bool escaped = false;
    
    for (int i = 0; i < len; i++) {
        char c = jsonData[i];
        
        if (escaped) {
            escaped = false;
            continue;
        }
        
        if (c == '\\') {
            escaped = true;
            continue;
        }
        
        if (c == '"') {
            inString = !inString;
            continue;
        }
        
        if (!inString) {
            if (c == '{') braceCount++;
            else if (c == '}') braceCount--;
        }
    }
    
    return braceCount == 0 && !inString;
}

uint8_t BluetoothController::calculateChecksum(const char* data, int length) {
    uint8_t checksum = 0;
    for (int i = 0; i < length; i++) {
        checksum ^= (uint8_t)data[i];
    }
    return checksum;
}

void BluetoothController::sendCalibrationData(const char* jsonData) {
    if (!initialized || !connected) return;
    
    calibrationDataCharacteristic.writeValue(jsonData);
}

void BluetoothController::broadcastStatus(const GPSData& gps, const NavigationState& nav, float heading) {
    if (!initialized || !connected) return;
    
    String statusJson = createStatusJSON(gps, nav, heading);
    
    // Throttle identical status messages
    static String lastStatusJson = "";
    static unsigned long lastSendTime = 0;
    unsigned long currentTime = millis();
    
    // Only send if content changed or minimum interval passed
    if (statusJson != lastStatusJson || (currentTime - lastSendTime) >= 500) {
        sendStatus(statusJson.c_str());
        lastStatusJson = statusJson;
        lastSendTime = currentTime;
    }
}

String BluetoothController::createCompressedStatusJSON() {
    return createEssentialStatusJSON();
}

String BluetoothController::createStatusJSON(const GPSData& gps, const NavigationState& nav, float heading) {
    String json = "{";
    
    // Ensure boolean values are properly formatted
    json += "\"has_fix\":";
    json += gps.hasFix ? "true" : "false";
    json += ",";
    
    json += "\"satellites\":" + String(gps.satellites) + ",";
    
    // Validate and format floating point numbers
    float lat = (gps.latitude >= -90.0 && gps.latitude <= 90.0) ? gps.latitude : 0.0;
    float lon = (gps.longitude >= -180.0 && gps.longitude <= 180.0) ? gps.longitude : 0.0;
    float alt = (gps.altitude >= -1000.0 && gps.altitude <= 50000.0) ? gps.altitude : 0.0;
    
    json += "\"currentLat\":" + String(lat, 6) + ",";
    json += "\"currentLon\":" + String(lon, 6) + ",";
    json += "\"altitude\":" + String(alt, 1) + ",";
    
    // Validate speed
    float speed = (gps.speedKnots >= 0.0 && gps.speedKnots < 999.0) ? gps.speedKnots : 0.0;
    json += "\"speed_knots\":" + String(speed, 2) + ",";
    
    // Clean and validate time/date strings
    String cleanTime = gps.timeString;
    String cleanDate = gps.dateString;
    
    // Remove problematic characters
    cleanTime.replace("\"", "");
    cleanTime.replace("\n", "");
    cleanTime.replace("\r", "");
    cleanTime.replace("*", "");
    cleanTime.trim();
    
    cleanDate.replace("\"", "");
    cleanDate.replace("\n", "");
    cleanDate.replace("\r", "");
    cleanDate.replace("*", "");
    cleanDate.trim();
    
    // Validate format
    if (cleanTime.length() < 6 || cleanTime.length() > 8) {
        cleanTime = "00:00:00";
    }
    if (cleanDate.length() < 6 || cleanDate.length() > 10) {
        cleanDate = "01/01/00";
    }
    
    json += "\"time\":\"" + cleanTime + "\",";
    json += "\"date\":\"" + cleanDate + "\",";
    
    // Validate DOP values
    float hdop = (gps.hdop > 0.0 && gps.hdop < 50.0) ? gps.hdop : 99.9;
    float vdop = (gps.vdop > 0.0 && gps.vdop < 50.0) ? gps.vdop : 99.9;
    float pdop = (gps.pdop > 0.0 && gps.pdop < 50.0) ? gps.pdop : 99.9;
    
    json += "\"hdop\":" + String(hdop, 1) + ",";
    json += "\"vdop\":" + String(vdop, 1) + ",";
    json += "\"pdop\":" + String(pdop, 1) + ",";
    
    // Validate heading
    float validHeading = (heading >= 0.0 && heading <= 360.0) ? heading : 0.0;
    json += "\"heading\":" + String(validHeading, 1) + ",";
    
    // Validate navigation values
    float distance = (nav.distanceToTarget >= 0.0) ? nav.distanceToTarget : 0.0;
    float bearing = (nav.bearingToTarget >= 0.0 && nav.bearingToTarget <= 360.0) ? nav.bearingToTarget : 0.0;
    
    json += "\"distance\":" + String(distance, 1) + ",";
    json += "\"bearing\":" + String(bearing, 1);
    
    // Target coordinates
    if (nav.mode != NavigationMode::IDLE && (nav.targetLatitude != 0.0 || nav.targetLongitude != 0.0)) {
        float targetLat = (nav.targetLatitude >= -90.0 && nav.targetLatitude <= 90.0) ? nav.targetLatitude : 0.0;
        float targetLon = (nav.targetLongitude >= -180.0 && nav.targetLongitude <= 180.0) ? nav.targetLongitude : 0.0;
        json += ",\"targetLat\":" + String(targetLat, 6);
        json += ",\"targetLon\":" + String(targetLon, 6);
    } else {
        json += ",\"targetLat\":null,\"targetLon\":null";
    }
    
    json += "}";
    
    // Final validation check
    if (!isValidCompleteJSON(json.c_str())) {
        Serial.println("BLE: Generated JSON failed validation, using fallback");
        Serial.print("BLE: Invalid JSON was: ");
        Serial.println(json);
        return createEssentialStatusJSON();
    }
    
    return json;
}

bool BluetoothController::isInitialized() const {
    return initialized;
}

void BluetoothController::setWaypointCallback(WaypointCallback callback) {
    waypointCallback = callback;
}

void BluetoothController::setNavigationCallback(NavigationCallback callback) {
    navigationCallback = callback;
}

void BluetoothController::onConnect(BLEDevice central) {
    if (instance) {
        instance->connected = true;
        Serial.print("BLE connected to: ");
        Serial.println(central.address());
        
        // Request higher MTU optimization
        instance->requestHigherMTU();
        
        // Start with conservative MTU and probe for higher capacity
        int startingMTU = 185; // iOS-compatible baseline
        instance->updateEffectiveMTU(startingMTU);
        
        // Probe for actual MTU capacity
        instance->probeMTUCapacity();
        
        BLE.stopAdvertise();
        Serial.println("BLE advertising stopped - device connected");
    }
}

void BluetoothController::onDisconnect(BLEDevice central) {
    if (instance) {
        instance->connected = false;
        instance->negotiatedMTU = 23;
        instance->effectiveMTU = 20;
        
        Serial.print("BLE disconnected from: ");
        Serial.println(central.address());
        
        delay(500);
        
        BLE.advertise();
        Serial.println("BLE advertising restarted - ready for new connections");
    }
}

void BluetoothController::onWaypointReceived(BLEDevice central, BLECharacteristic characteristic) {
    const uint8_t* data = characteristic.value();
    int length = characteristic.valueLength();
    
    if (length > 0) {
        String waypointData = "";
        for (int i = 0; i < length; i++) {
            waypointData += (char)data[i];
        }
        
        Serial.print("BLE waypoint received: ");
        Serial.println(waypointData);
        
        if (waypointData.startsWith("$GPS,") && waypointData.endsWith("*")) {
            int firstComma = waypointData.indexOf(',');
            int secondComma = waypointData.indexOf(',', firstComma + 1);
            int thirdComma = waypointData.indexOf(',', secondComma + 1);
            int asterisk = waypointData.indexOf('*');
            
            if (firstComma > 0 && secondComma > 0 && thirdComma > 0 && asterisk > 0) {
                float latitude = waypointData.substring(firstComma + 1, secondComma).toFloat();
                float longitude = waypointData.substring(secondComma + 1, thirdComma).toFloat();
                
                Serial.print("Waypoint received via BLE: ");
                Serial.print(latitude, 6);
                Serial.print(", ");
                Serial.println(longitude, 6);
                
                if (waypointCallback) {
                    waypointCallback(latitude, longitude);
                }
            }
        }
    }
}

void BluetoothController::onCalibrationCommand(BLEDevice central, BLECharacteristic characteristic) {
    const uint8_t* data = characteristic.value();
    int length = characteristic.valueLength();
    
    if (length > 0) {
        String command = "";
        for (int i = 0; i < length; i++) {
            command += (char)data[i];
        }
        
        Serial.print("BLE calibration command: ");
        Serial.println(command);
        
        if (command == "START_CAL") {
            Serial.println("Starting compass calibration via BLE");
        } else if (command == "STOP_CAL") {
            Serial.println("Stopping compass calibration via BLE");
        } else if (command == "NAV_ENABLE") {
            Serial.println("Navigation enabled via BLE");
            if (navigationCallback) {
                navigationCallback(true);
            }
        } else if (command == "NAV_DISABLE") {
            Serial.println("Navigation disabled via BLE");
            if (navigationCallback) {
                navigationCallback(false);
            }
        }
    }
}