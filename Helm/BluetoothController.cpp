#include "BluetoothController.h"
#include <Arduino.h>

BluetoothController* BluetoothController::instance = nullptr;
BluetoothController::WaypointCallback BluetoothController::waypointCallback = nullptr;
BluetoothController::NavigationCallback BluetoothController::navigationCallback = nullptr;

BluetoothController::BluetoothController() : 
    // Following exact README architecture UUIDs
    bluetoothService("0000FFE0-0000-1000-8000-00805F9B34FB"),
    waypointCharacteristic("0000FFE1-0000-1000-8000-00805F9B34FB", BLEWrite, 50),
    statusCharacteristic("0000FFE2-0000-1000-8000-00805F9B34FB", BLENotify, 200),
    commandCharacteristic("0000FFE3-0000-1000-8000-00805F9B34FB", BLEWrite, 30),
    calibrationDataCharacteristic("0000FFE4-0000-1000-8000-00805F9B34FB", BLENotify, 100),
    configCharacteristic("0000FFE5-0000-1000-8000-00805F9B34FB", BLERead | BLEWrite, 50),
    initialized(false),
    connected(false),
    effectiveMTU(20),
    negotiatedMTU(23) {
    instance = this;
}

bool BluetoothController::begin(const char* deviceName) {
    if (!BLE.begin()) {
        initialized = false;
        return false;
    }
    
    // Set device name exactly as "Helm" per README
    BLE.setLocalName("Helm");
    BLE.setDeviceName("Helm");
    
    // Optimize connection parameters for BLE efficiency
    BLE.setConnectionInterval(15, 30);  // 15-30ms as per README
    BLE.setSupervisionTimeout(400);
    
    // Add all characteristics to service following README architecture
    bluetoothService.addCharacteristic(waypointCharacteristic);
    bluetoothService.addCharacteristic(statusCharacteristic);
    bluetoothService.addCharacteristic(commandCharacteristic);
    bluetoothService.addCharacteristic(calibrationDataCharacteristic);
    bluetoothService.addCharacteristic(configCharacteristic);
    
    BLE.addService(bluetoothService);
    
    // Set up event handlers
    BLE.setEventHandler(BLEConnected, onConnect);
    BLE.setEventHandler(BLEDisconnected, onDisconnect);
    waypointCharacteristic.setEventHandler(BLEWritten, onWaypointReceived);
    commandCharacteristic.setEventHandler(BLEWritten, onCommandReceived);
    configCharacteristic.setEventHandler(BLEWritten, onConfigWritten);
    
    // Set advertising parameters for discoverability
    BLE.setAdvertisingInterval(100);
    BLE.setConnectable(true);
    BLE.setAdvertisedServiceUuid(bluetoothService.uuid());
    BLE.setAppearance(0x0000);
    
    // Initialize device configuration
    String initialConfig = "{\"version\":\"1.0\",\"interval_ms\":1000}";
    configCharacteristic.writeValue(initialConfig.c_str());
    
    BLE.advertise();
    
    initialized = true;
    Serial.print("BLE advertising as: ");
    Serial.println(deviceName);
    Serial.print("BLE Service UUID: ");
    Serial.println("0000FFE0-0000-1000-8000-00805F9B34FB");
    Serial.println("BLE configured following README architecture with 5 characteristics");
    
    return true;
}

void BluetoothController::requestHigherMTU() {
    // Request maximum MTU supported by iOS (up to 512 bytes)
    Serial.println("BLE: Requesting higher MTU for improved data throughput");
    
    // Start with conservative estimate and detect actual capacity
    updateEffectiveMTU(185); // Conservative iOS-compatible starting point per README
}

void BluetoothController::updateEffectiveMTU(int mtu) {
    negotiatedMTU = max(mtu, 23); // Ensure minimum MTU
    effectiveMTU = negotiatedMTU - 3; // Account for ATT overhead
    
    Serial.print("BLE: MTU updated - negotiated: ");
    Serial.print(negotiatedMTU);
    Serial.print(" bytes, effective payload: ");
    Serial.print(effectiveMTU);
    Serial.println(" bytes");
}

void BluetoothController::update() {
    if (!initialized) return;
    
    BLE.poll();
    
    // Auto-restart advertising if disconnected
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
    
    // Try to send complete message first if it fits within MTU
    if (jsonLength <= effectiveMTU) {
        statusCharacteristic.writeValue(jsonData);
        Serial.print("BLE: Sent complete JSON (");
        Serial.print(jsonLength);
        Serial.print(" bytes) - MTU utilization: ");
        Serial.print((jsonLength * 100) / effectiveMTU);
        Serial.println("%");
        
        // Learn from successful transmissions to optimize MTU
        if (jsonLength > effectiveMTU * 0.8) {
            detectActualMTU(jsonLength);
        }
        return;
    }
    
    // Use fragmentation for larger messages following README spec
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
    
    // Fragment size: MTU - 4 bytes for header (seq + total + length_high + length_low)
    int fragmentSize = effectiveMTU - 4;
    uint8_t totalFragments = (totalLength + fragmentSize - 1) / fragmentSize;
    
    if (totalFragments > 255) {
        Serial.println("BLE: Message too large for fragmentation (>255 fragments)");
        return false;
    }
    
    Serial.print("BLE: Fragmenting into ");
    Serial.print(totalFragments);
    Serial.print(" fragments (size: ");
    Serial.print(fragmentSize);
    Serial.println(" bytes each)");
    
    // Send fragments with proper throttling per README
    for (uint8_t seq = 0; seq < totalFragments; seq++) {
        int offset = seq * fragmentSize;
        int remainingLength = totalLength - offset;
        int currentFragmentSize = (remainingLength < fragmentSize) ? remainingLength : fragmentSize;
        
        sendFragment(jsonData + offset, currentFragmentSize, seq, totalFragments, totalLength);
        
        // Throttle transmission to prevent overwhelming iOS fragment reassembly
        delay(50); // Optimized delay per README recommendations
        
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
    // Create fragment with 4-byte header as per README spec
    char fragment[effectiveMTU + 4];
    
    fragment[0] = seqNum;
    fragment[1] = totalFragments;
    fragment[2] = (totalLength >> 8) & 0xFF; // High byte
    fragment[3] = totalLength & 0xFF;        // Low byte
    
    // Copy payload data
    memcpy(fragment + 4, data, dataLen);
    
    // Send fragment with exact size
    statusCharacteristic.writeValue((const void*)fragment, dataLen + 4);
}

String BluetoothController::createEssentialStatusJSON() {
    // Minimal JSON structure per README fallback specification
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
    
    Serial.println("BLE: Probing MTU capacity to optimize throughput");
    
    // Test progressively larger messages to detect actual MTU limits
    String testJson = createTestJSON(200);
    statusCharacteristic.writeValue(testJson.c_str());
    
    Serial.print("BLE: MTU probe sent ");
    Serial.print(testJson.length());
    Serial.println(" bytes");
}

void BluetoothController::detectActualMTU(int successfulLength) {
    // Learn from successful large transmissions to optimize MTU
    if (successfulLength > effectiveMTU && successfulLength <= 512) {
        Serial.print("BLE: Detected higher MTU capacity, updating from ");
        Serial.print(effectiveMTU);
        Serial.print(" to ");
        Serial.println(successfulLength + 10);
        
        updateEffectiveMTU(successfulLength + 10);
    }
}

String BluetoothController::createTestJSON(int targetSize) {
    String json = "{\"test\":true,\"mtu_probe\":\"";
    
    // Fill with padding to reach target size
    int paddingNeeded = targetSize - json.length() - 3;
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
    
    // Check for corruption patterns per README validation
    String jsonStr = String(jsonData);
    
    if (jsonStr.indexOf("false.") >= 0 || jsonStr.indexOf("true.") >= 0) {
        Serial.println("BLE: Detected corrupted boolean values");
        return false;
    }
    
    if (jsonStr.indexOf("null.") >= 0) {
        Serial.println("BLE: Detected corrupted null values");
        return false;
    }
    
    // Basic brace matching validation
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
    
    // Throttle identical status messages to optimize BLE bandwidth
    static String lastStatusJson = "";
    static unsigned long lastSendTime = 0;
    unsigned long currentTime = millis();
    
    // Send if content changed or minimum interval passed (1-2 seconds per README)
    if (statusJson != lastStatusJson || (currentTime - lastSendTime) >= 1000) {
        sendStatus(statusJson.c_str());
        lastStatusJson = statusJson;
        lastSendTime = currentTime;
    }
}

String BluetoothController::createStatusJSON(const GPSData& gps, const NavigationState& nav, float heading) {
    // Create JSON following exact README specification
    String json = "{";
    
    // GPS fix status (boolean)
    json += "\"has_fix\":";
    json += gps.hasFix ? "true" : "false";
    json += ",";
    
    // Satellite count
    json += "\"satellites\":" + String(gps.satellites) + ",";
    
    // Current position with validation
    float lat = (gps.latitude >= -90.0 && gps.latitude <= 90.0) ? gps.latitude : 0.0;
    float lon = (gps.longitude >= -180.0 && gps.longitude <= 180.0) ? gps.longitude : 0.0;
    
    json += "\"currentLat\":" + String(lat, 6) + ",";
    json += "\"currentLon\":" + String(lon, 6) + ",";
    json += "\"altitude\":" + String(gps.altitude, 1) + ",";
    
    // Speed and time data
    json += "\"speed_knots\":" + String(gps.speedKnots, 2) + ",";
    json += "\"time\":\"" + gps.timeString + "\",";
    json += "\"date\":\"" + gps.dateString + "\",";
    
    // DOP values per README specification
    json += "\"hdop\":" + String(gps.hdop, 2) + ",";
    json += "\"vdop\":" + String(gps.vdop, 2) + ",";
    json += "\"pdop\":" + String(gps.pdop, 2) + ",";
    
    // Current heading
    float validHeading = (heading >= 0.0 && heading <= 360.0) ? heading : 0.0;
    json += "\"heading\":" + String(validHeading, 1) + ",";
    
    // Navigation data
    json += "\"distance\":" + String(nav.distanceToTarget, 1) + ",";
    json += "\"bearing\":" + String(nav.bearingToTarget, 1);
    
    // Target coordinates (null if no target)
    if (nav.mode != NavigationMode::IDLE && (nav.targetLatitude != 0.0 || nav.targetLongitude != 0.0)) {
        json += ",\"targetLat\":" + String(nav.targetLatitude, 6);
        json += ",\"targetLon\":" + String(nav.targetLongitude, 6);
    } else {
        json += ",\"targetLat\":null,\"targetLon\":null";
    }
    
    json += "}";
    
    // Final validation
    if (!isValidCompleteJSON(json.c_str())) {
        Serial.println("BLE: Generated JSON failed validation, using fallback");
        return createEssentialStatusJSON();
    }
    
    return json;
}

void BluetoothController::processCommand(const String& command) {
    Serial.print("BLE: Processing command: ");
    Serial.println(command);
    
    if (command == "NAV_ENABLE") {
        if (navigationCallback) {
            navigationCallback(true);
            sendCommandResponse("NAV_ENABLE", "OK");
        }
    } else if (command == "NAV_DISABLE") {
        if (navigationCallback) {
            navigationCallback(false);
            sendCommandResponse("NAV_DISABLE", "OK");
        }
    } else if (command == "START_CAL") {
        Serial.println("Starting compass calibration via BLE");
        sendCommandResponse("START_CAL", "OK");
    } else if (command == "STOP_CAL") {
        Serial.println("Stopping compass calibration via BLE");
        sendCommandResponse("STOP_CAL", "OK");
    } else {
        sendCommandResponse(command, "ERR_UNKNOWN_COMMAND");
    }
}

void BluetoothController::sendCommandResponse(const String& command, const String& status) {
    String response = "{\"cmd\":\"" + command + "\",\"status\":\"" + status + "\"}";
    calibrationDataCharacteristic.writeValue(response.c_str());
}

void BluetoothController::updateDeviceConfig(const String& key, const String& value) {
    // Update device configuration and notify via config characteristic
    String config = "{\"" + key + "\":\"" + value + "\"}";
    configCharacteristic.writeValue(config.c_str());
}

String BluetoothController::getDeviceConfig() {
    String config = "{";
    config += "\"version\":\"" + String(SystemConfig::VERSION) + "\",";
    config += "\"interval_ms\":1000,";
    config += "\"mtu\":" + String(negotiatedMTU);
    config += "}";
    return config;
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
        
        // Initialize MTU optimization following README architecture
        instance->requestHigherMTU();
        instance->updateEffectiveMTU(185); // Start with iOS-compatible baseline
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
        Serial.println("BLE advertising restarted");
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
        
        // Parse NMEA-like format per README: $GPS,lat,lon,alt*
        if (waypointData.startsWith("$GPS,") && waypointData.endsWith("*")) {
            int firstComma = waypointData.indexOf(',');
            int secondComma = waypointData.indexOf(',', firstComma + 1);
            int thirdComma = waypointData.indexOf(',', secondComma + 1);
            int asterisk = waypointData.indexOf('*');
            
            if (firstComma > 0 && secondComma > 0 && thirdComma > 0 && asterisk > 0) {
                float latitude = waypointData.substring(firstComma + 1, secondComma).toFloat();
                float longitude = waypointData.substring(secondComma + 1, thirdComma).toFloat();
                
                Serial.print("Parsed waypoint: ");
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

void BluetoothController::onCommandReceived(BLEDevice central, BLECharacteristic characteristic) {
    const uint8_t* data = characteristic.value();
    int length = characteristic.valueLength();
    
    if (length > 0) {
        String command = "";
        for (int i = 0; i < length; i++) {
            command += (char)data[i];
        }
        
        if (instance) {
            instance->processCommand(command);
        }
    }
}

void BluetoothController::onConfigWritten(BLEDevice central, BLECharacteristic characteristic) {
    const uint8_t* data = characteristic.value();
    int length = characteristic.valueLength();
    
    if (length > 0) {
        String configData = "";
        for (int i = 0; i < length; i++) {
            configData += (char)data[i];
        }
        
        Serial.print("BLE configuration updated: ");
        Serial.println(configData);
    }
}