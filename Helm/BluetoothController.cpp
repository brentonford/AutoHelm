#include "BluetoothController.h"
#include <Arduino.h>

BluetoothController* BluetoothController::instance = nullptr;

BluetoothController::BluetoothController() : 
    bluetoothService("19B10000-E8F2-537E-4F6C-D104768A1214"),
    waypointCharacteristic("19B10001-E8F2-537E-4F6C-D104768A1214", BLEWrite, 32),
    statusCharacteristic("19B10002-E8F2-537E-4F6C-D104768A1214", BLENotify, 512),
    calibrationCommandCharacteristic("19B10003-E8F2-537E-4F6C-D104768A1214", BLEWrite, 32),
    calibrationDataCharacteristic("19B10004-E8F2-537E-4F6C-D104768A1214", BLENotify, 128),
    initialized(false),
    connected(false) {
    instance = this;
}

bool BluetoothController::begin(const char* deviceName) {
    // Will fail if BLE hardware is not available
    if (!BLE.begin()) {
        initialized = false;
        return false;
    }
    
    // Set device name and local name for Apple device compatibility
    BLE.setLocalName(deviceName);
    BLE.setDeviceName(deviceName);
    
    // Set connection parameters optimized for iOS/macOS
    BLE.setConnectionInterval(6, 24);  // 7.5ms - 30ms for responsive connection
    BLE.setSupervisionTimeout(400);    // 4 second timeout
    // Slave latency optimization not available in ArduinoBLE
    
    // Add characteristics to service
    bluetoothService.addCharacteristic(waypointCharacteristic);
    bluetoothService.addCharacteristic(statusCharacteristic);
    bluetoothService.addCharacteristic(calibrationCommandCharacteristic);
    bluetoothService.addCharacteristic(calibrationDataCharacteristic);
    
    // Add service to BLE
    BLE.addService(bluetoothService);
    
    // Set event handlers
    BLE.setEventHandler(BLEConnected, onConnect);
    BLE.setEventHandler(BLEDisconnected, onDisconnect);
    waypointCharacteristic.setEventHandler(BLEWritten, onWaypointReceived);
    calibrationCommandCharacteristic.setEventHandler(BLEWritten, onCalibrationCommand);
    
    // Configure advertising parameters for optimal Apple device discovery
    BLE.setAdvertisingInterval(100);   // 62.5ms intervals - Apple recommended range
    BLE.setConnectable(true);
    
    // Set proper advertising data for Apple devices
    BLE.setAdvertisedServiceUuid(bluetoothService.uuid());
    BLE.setAppearance(0x0000);  // Generic device appearance
    
    // Start advertising with proper flags
    BLE.advertise();
    
    initialized = true;
    Serial.print("BLE advertising as: ");
    Serial.println(deviceName);
    Serial.print("BLE Service UUID: ");
    Serial.println("19B10000-E8F2-537E-4F6C-D104768A1214");
    Serial.println("BLE optimized for iOS/macOS device discovery");
    Serial.println("Device should appear in Bluetooth settings and apps");
    
    return true;
}

void BluetoothController::update() {
    if (!initialized) return;
    
    // Poll BLE events
    BLE.poll();
    
    // Handle advertising restart with proper timing
    static unsigned long lastAdvertiseCheck = 0;
    unsigned long currentTime = millis();
    
    if (!connected && (currentTime - lastAdvertiseCheck > 5000)) {
        lastAdvertiseCheck = currentTime;
        
        // Stop current advertising before restarting
        BLE.stopAdvertise();
        delay(100);
        
        // Restart advertising with fresh parameters
        BLE.advertise();
        Serial.println("BLE: Refreshed advertising for device discovery");
    }
}

bool BluetoothController::isConnected() const {
    return connected;
}

void BluetoothController::sendStatus(const char* jsonData) {
    if (!initialized || !connected) return;
    
    // Send status data via notify characteristic
    statusCharacteristic.writeValue(jsonData);
}

void BluetoothController::sendCalibrationData(const char* jsonData) {
    if (!initialized || !connected) return;
    
    // Send calibration data via notify characteristic
    calibrationDataCharacteristic.writeValue(jsonData);
}

bool BluetoothController::isInitialized() const {
    return initialized;
}

void BluetoothController::onConnect(BLEDevice central) {
    if (instance) {
        instance->connected = true;
        Serial.print("BLE connected to: ");
        Serial.println(central.address());
        
        // Stop advertising when connected to save power
        BLE.stopAdvertise();
        Serial.println("BLE advertising stopped - device connected");
    }
}

void BluetoothController::onDisconnect(BLEDevice central) {
    if (instance) {
        instance->connected = false;
        Serial.print("BLE disconnected from: ");
        Serial.println(central.address());
        
        // Wait before restarting advertising to ensure clean disconnect
        delay(500);
        
        // Restart advertising immediately after disconnect
        BLE.advertise();
        Serial.println("BLE advertising restarted - ready for new connections");
    }
}

void BluetoothController::onWaypointReceived(BLEDevice central, BLECharacteristic characteristic) {
    // Read waypoint data from characteristic
    const uint8_t* data = characteristic.value();
    int length = characteristic.valueLength();
    
    if (length > 0) {
        String waypointData = "";
        for (int i = 0; i < length; i++) {
            waypointData += (char)data[i];
        }
        
        Serial.print("BLE waypoint received: ");
        Serial.println(waypointData);
        
        // Parse waypoint format: $GPS,latitude,longitude,altitude*
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
            }
        }
    }
}

void BluetoothController::onCalibrationCommand(BLEDevice central, BLECharacteristic characteristic) {
    // Read calibration command from characteristic
    const uint8_t* data = characteristic.value();
    int length = characteristic.valueLength();
    
    if (length > 0) {
        String command = "";
        for (int i = 0; i < length; i++) {
            command += (char)data[i];
        }
        
        Serial.print("BLE calibration command: ");
        Serial.println(command);
        
        // Handle calibration commands
        if (command == "START_CAL") {
            Serial.println("Starting compass calibration via BLE");
        } else if (command == "STOP_CAL") {
            Serial.println("Stopping compass calibration via BLE");
        } else if (command == "NAV_ENABLE") {
            Serial.println("Navigation enabled via BLE");
        } else if (command == "NAV_DISABLE") {
            Serial.println("Navigation disabled via BLE");
        }
    }
}