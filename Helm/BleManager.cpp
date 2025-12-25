#include "BleManager.h"

BleManager::BleManager()
    : _server(nullptr)
    , _service(nullptr)
    , _sensorStatusChar(nullptr)
    , _commandChar(nullptr)
    , _calibrationChar(nullptr)
    , _lastStatusTime(0)
    , _justDisconnected(false) {
}

bool BleManager::begin() {
    BLEDevice::init(BleConfig::deviceName);

    _server = BLEDevice::createServer();
    _server->setCallbacks(this);

    _service = _server->createService(BleConfig::serviceUuid);

    _sensorStatusChar = _service->createCharacteristic(
        BleConfig::sensorStatusCharUuid,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    _sensorStatusChar->addDescriptor(new BLE2902());

    _commandChar = _service->createCharacteristic(
        BleConfig::commandCharUuid,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    _commandChar->setCallbacks(this);

    _calibrationChar = _service->createCharacteristic(
        BleConfig::calibrationCharUuid,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    _calibrationChar->addDescriptor(new BLE2902());

    _service->start();
    Serial.println("[BLE] Service started");

    BLEAdvertising* advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(BleConfig::serviceUuid);
    advertising->setScanResponse(true);
    advertising->setMinPreferred(0x06);
    advertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] Advertising as 'Helm'");
    return true;
}

void BleManager::update() {
}

void BleManager::onConnect(BLEServer* server) {
    _status.connected = true;
    _justDisconnected = false;
    Serial.println("[BLE] Client connected");
}

void BleManager::onDisconnect(BLEServer* server) {
    _status.connected = false;
    _justDisconnected = true;
    Serial.println("[BLE] Client disconnected");

    delay(500);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Advertising restarted");
}

bool BleManager::wasJustDisconnected() const {
    return _justDisconnected;
}

void BleManager::clearDisconnectFlag() {
    _justDisconnected = false;
}

void BleManager::onWrite(BLECharacteristic* characteristic) {
    
    if (!characteristic) {
        Serial.println("[BLE] ERROR: characteristic is NULL");
        return;
    }

    if (characteristic != _commandChar) {
        Serial.println("[BLE] Not command characteristic - ignoring");
        return;
    }

    // Get the raw data pointer and length
    uint8_t* pData = characteristic->getData();
    size_t len = characteristic->getValue().length();
    
    if (len == 0 || !pData) {
        Serial.println("[BLE] Empty write or null data - ignoring");
        return;
    }
    
    if (len > 127) {
        Serial.printf("[BLE] ERROR: Command too long (%d bytes)\n", len);
        return;
    }

    // Copy raw bytes to buffer
    static char cmdBuffer[128];
    memcpy(cmdBuffer, pData, len);
    cmdBuffer[len] = '\0';

    bool isAllNullBytes = true;
    for (size_t i = 0; i < len; i++) {
        if (cmdBuffer[i] != '\0') {
            isAllNullBytes = false;
            break;
        }
    }
    
    if (isAllNullBytes) {
        Serial.println("[BLE] All null bytes - ignoring");
        return;
    }

    parseCommand(cmdBuffer);
}

void BleManager::parseCommand(const char* data) {
    if (!data) {
        return;
    }
    
    size_t dataLen = strlen(data);
    if (dataLen == 0) {
        return;
    }
    
    if (dataLen > 127) {
        Serial.println("[BLE] ERROR: Invalid command length");
        return;
    }

    static char cmdBuffer[128];
    strncpy(cmdBuffer, data, 127);
    cmdBuffer[127] = '\0';
    
    char* cmd = cmdBuffer;
    while (*cmd && (*cmd == ' ' || *cmd == '\t' || *cmd == '\r' || *cmd == '\n' || *cmd == '\0')) {
        cmd++;
    }
    
    size_t len = strlen(cmd);
    if (len == 0) {
        return;
    }
    
    while (len > 0 && (cmd[len-1] == ' ' || cmd[len-1] == '\t' || cmd[len-1] == '\r' || cmd[len-1] == '\n')) {
        cmd[len-1] = '\0';
        len--;
    }
    
    if (len == 0) {
        return;
    }
    
    for (char* p = cmd; *p; p++) {
        *p = toupper(*p);
    }

    if (strcmp(cmd, "START_CAL") == 0) {
        _status.pendingCommand = BleCommand::StartCalibration;
        sendResponse("{\"ack\":\"START_CAL\"}");
    } else if (strcmp(cmd, "STOP_CAL") == 0) {
        _status.pendingCommand = BleCommand::StopCalibration;
        sendResponse("{\"ack\":\"STOP_CAL\"}");
    } else if (strncmp(cmd, "RF_", 3) == 0) {
        if (len < 4 || len > 32) {
            Serial.println("[BLE] ERROR: Invalid RF command length");
            return;
        }

        static char rfCmdBuffer[32];
        strncpy(rfCmdBuffer, cmd + 3, 31);
        rfCmdBuffer[31] = '\0';
        
        size_t rfLen = strlen(rfCmdBuffer);

        if (rfLen > 5 && strcmp(rfCmdBuffer + rfLen - 5, "_HOLD") == 0) {
            rfCmdBuffer[rfLen - 5] = '\0';
            if (strlen(rfCmdBuffer) == 0) {
                Serial.println("[BLE] ERROR: Invalid RF_HOLD command");
                return;
            }
            _status.pendingRfCommand = String(rfCmdBuffer);
            _status.isHoldCommand = true;
        } else {
            _status.pendingRfCommand = String(rfCmdBuffer);
            _status.isHoldCommand = false;
        }

        char ack[64];
        snprintf(ack, sizeof(ack), "{\"ack\":\"%s\"}", cmd);
        sendResponse(ack);
    } else {
        sendResponse("{\"error\":\"Unknown command\"}");
    }
}

String BleManager::buildSensorStatusJson(const GpsData& gpsData, float heading) {
    static char json[256];
    snprintf(json, sizeof(json),
        "{\"has_fix\":%s,\"satellites\":%d,\"currentLat\":%.6f,\"currentLon\":%.6f,\"altitude\":%.1f,\"hdop\":%.1f,\"heading\":%.1f}",
        gpsData.hasFix ? "true" : "false",
        gpsData.satellites,
        gpsData.latitude,
        gpsData.longitude,
        gpsData.altitude,
        gpsData.hdop,
        heading
    );
    return String(json);
}

void BleManager::sendSensorStatus(const GpsData& gpsData, float heading) {
    if (!_status.connected || !_sensorStatusChar)
        return;

    uint32_t now = millis();
    if ((now - _lastStatusTime) < BleConfig::statusIntervalMs)
        return;

    _lastStatusTime = now;

    static char json[256];
    snprintf(json, sizeof(json),
        "{\"has_fix\":%s,\"satellites\":%d,\"currentLat\":%.6f,\"currentLon\":%.6f,\"altitude\":%.1f,\"hdop\":%.1f,\"heading\":%.1f}",
        gpsData.hasFix ? "true" : "false",
        gpsData.satellites,
        gpsData.latitude,
        gpsData.longitude,
        gpsData.altitude,
        gpsData.hdop,
        heading
    );

    _sensorStatusChar->setValue((uint8_t*)json, strlen(json));
    _sensorStatusChar->notify();
}

void BleManager::sendCalibrationData(const String& data) {
    if (!_status.connected || !_calibrationChar)
        return;

    if (data.length() > 512) {
        Serial.println("[BLE] ERROR: Calibration data too large");
        return;
    }

    _calibrationChar->setValue((uint8_t*)data.c_str(), data.length());
    _calibrationChar->notify();
}

void BleManager::sendResponse(const String& response) {
    if (!_status.connected || !_calibrationChar)
        return;

    if (response.length() > 256) {
        Serial.println("[BLE] ERROR: Response too large");
        return;
    }

    _calibrationChar->setValue((uint8_t*)response.c_str(), response.length());
    _calibrationChar->notify();
}

void BleManager::sendResponse(const char* response) {
    if (!_status.connected || !_calibrationChar)
        return;

    size_t len = strlen(response);
    if (len > 256) {
        Serial.println("[BLE] ERROR: Response too large");
        return;
    }

    _calibrationChar->setValue((uint8_t*)response, len);
    _calibrationChar->notify();
}

bool BleManager::isConnected() const {
    return _status.connected;
}

BleCommand BleManager::consumeCommand() {
    BleCommand cmd = _status.pendingCommand;
    _status.pendingCommand = BleCommand::None;
    return cmd;
}

bool BleManager::hasRfCommandPending() const {
    return _status.pendingRfCommand.length() > 0;
}

bool BleManager::isRfHoldCommand() const {
    return _status.isHoldCommand;
}

String BleManager::consumeRfCommand() {
    String cmd = _status.pendingRfCommand;
    _status.pendingRfCommand = "";
    _status.isHoldCommand = false;
    return cmd;
}