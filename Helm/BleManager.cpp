#include "BleManager.h"

BleManager::BleManager()
    : _server(nullptr)
    , _service(nullptr)
    , _waypointChar(nullptr)
    , _statusChar(nullptr)
    , _commandChar(nullptr)
    , _calibrationChar(nullptr)
    , _lastStatusTime(0) {
}

bool BleManager::begin() {
    BLEDevice::init(BleConfig::deviceName);

    _server = BLEDevice::createServer();
    _server->setCallbacks(this);

    _service = _server->createService(BleConfig::serviceUuid);

    _waypointChar = _service->createCharacteristic(
        BleConfig::waypointCharUuid,
        BLECharacteristic::PROPERTY_WRITE
    );
    _waypointChar->setCallbacks(this);

    _statusChar = _service->createCharacteristic(
        BleConfig::statusCharUuid,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    _statusChar->addDescriptor(new BLE2902());

    _commandChar = _service->createCharacteristic(
        BleConfig::commandCharUuid,
        BLECharacteristic::PROPERTY_WRITE
    );
    _commandChar->setCallbacks(this);

    _calibrationChar = _service->createCharacteristic(
        BleConfig::calibrationCharUuid,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    _calibrationChar->addDescriptor(new BLE2902());

    _service->start();

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
    Serial.println("[BLE] Client connected");
}

void BleManager::onDisconnect(BLEServer* server) {
    _status.connected = false;
    Serial.println("[BLE] Client disconnected");

    delay(500);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Advertising restarted");
}

void BleManager::onWrite(BLECharacteristic* characteristic) {
    String uuid = characteristic->getUUID().toString().c_str();
    String value = characteristic->getValue().c_str();

    if (characteristic == _waypointChar) {
        Serial.printf("[BLE] Waypoint received: %s\n", value.c_str());
        parseWaypoint(value);
    } else if (characteristic == _commandChar) {
        Serial.printf("[BLE] Command received: %s\n", value.c_str());
        parseCommand(value);
    }
}

void BleManager::parseWaypoint(const String& data) {
    if (!data.startsWith("$GPS,")) {
        sendResponse("{\"error\":\"Invalid waypoint format\"}");
        return;
    }

    int fieldStart = 5;
    String fields[6];
    int fieldCount = 0;

    for (int i = 5; i < (int)data.length() && fieldCount < 6; i++) {
        char c = data.charAt(i);
        if (c == ',' || c == '*') {
            fields[fieldCount++] = data.substring(fieldStart, i);
            fieldStart = i + 1;
        }
    }

    if (fieldCount < 2) {
        sendResponse("{\"error\":\"Insufficient fields\"}");
        return;
    }

    _status.waypointLat = fields[0].toFloat();
    _status.waypointLon = fields[1].toFloat();
    _status.waypointName[0] = '\0';
    _status.waypointSpotLock = false;
    _status.waypointSpeed = 0.0f;

    if (fieldCount >= 4 && fields[3].length() > 0) {
        strncpy(_status.waypointName, fields[3].c_str(), 31);
        _status.waypointName[31] = '\0';
    }
    if (fieldCount >= 5) {
        _status.waypointSpotLock = (fields[4] == "1");
    }
    if (fieldCount >= 6) {
        _status.waypointSpeed = fields[5].toFloat();
    }

    if (_status.waypointLat == 0.0f && _status.waypointLon == 0.0f) {
        sendResponse("{\"error\":\"Invalid coordinates\"}");
        return;
    }

    _status.waypointReceived = true;
    Serial.printf("[BLE] Parsed waypoint: %.6f, %.6f\n", _status.waypointLat, _status.waypointLon);
    sendResponse("{\"ack\":\"waypoint\"}");
}

void BleManager::parseCommand(const String& data) {
    String cmd = data;
    cmd.trim();
    cmd.toUpperCase();

    if (cmd == "NAV_ENABLE") {
        _status.pendingCommand = BleCommand::NavEnable;
        sendResponse("{\"ack\":\"NAV_ENABLE\"}");
    } else if (cmd == "NAV_DISABLE") {
        _status.pendingCommand = BleCommand::NavDisable;
        sendResponse("{\"ack\":\"NAV_DISABLE\"}");
    } else if (cmd == "START_CAL") {
        _status.pendingCommand = BleCommand::StartCalibration;
        sendResponse("{\"ack\":\"START_CAL\"}");
    } else if (cmd == "STOP_CAL") {
        _status.pendingCommand = BleCommand::StopCalibration;
        sendResponse("{\"ack\":\"STOP_CAL\"}");
    } else if (cmd == "SPOT_LOCK") {
        _status.pendingCommand = BleCommand::SpotLockEngage;
        sendResponse("{\"ack\":\"SPOT_LOCK\"}");
    } else if (cmd == "SPOT_RELEASE") {
        _status.pendingCommand = BleCommand::SpotLockDisengage;
        sendResponse("{\"ack\":\"SPOT_RELEASE\"}");
    } else if (cmd == "JOG_FWD") {
        _status.pendingCommand = BleCommand::SpotLockJogForward;
        sendResponse("{\"ack\":\"JOG_FWD\"}");
    } else if (cmd == "JOG_BACK") {
        _status.pendingCommand = BleCommand::SpotLockJogBack;
        sendResponse("{\"ack\":\"JOG_BACK\"}");
    } else if (cmd == "JOG_LEFT") {
        _status.pendingCommand = BleCommand::SpotLockJogLeft;
        sendResponse("{\"ack\":\"JOG_LEFT\"}");
    } else if (cmd == "JOG_RIGHT") {
        _status.pendingCommand = BleCommand::SpotLockJogRight;
        sendResponse("{\"ack\":\"JOG_RIGHT\"}");
    } else if (cmd == "PATH_START") {
        _status.pendingCommand = BleCommand::PathStart;
        sendResponse("{\"ack\":\"PATH_START\"}");
    } else if (cmd == "PATH_STOP") {
        _status.pendingCommand = BleCommand::PathStop;
        sendResponse("{\"ack\":\"PATH_STOP\"}");
    } else if (cmd == "MANUAL_MODE") {
        _status.pendingCommand = BleCommand::ManualMode;
        sendResponse("{\"ack\":\"MANUAL_MODE\"}");
    } else if (cmd.startsWith("SPEED:")) {
        float speed = cmd.substring(6).toFloat();
        if (speed >= 0 && speed <= 15.0f) {
            _status.pendingSpeed = speed;
            _status.hasPendingSpeed = true;
            sendResponse("{\"ack\":\"SPEED\",\"value\":" + String(speed) + "}");
        } else {
            sendResponse("{\"error\":\"Invalid speed\"}");
        }
    } else if (cmd.startsWith("RF_")) {
        String rfCmd = cmd.substring(3);

        if (rfCmd.endsWith("_HOLD")) {
            rfCmd = rfCmd.substring(0, rfCmd.length() - 5);
            _status.pendingRfCommand = rfCmd;
            _status.isHoldCommand = true;
        } else {
            _status.pendingRfCommand = rfCmd;
            _status.isHoldCommand = false;
        }

        sendResponse("{\"ack\":\"" + cmd + "\"}");
    } else {
        sendResponse("{\"error\":\"Unknown command\"}");
    }
}

String BleManager::buildStatusJson(const GpsData& gpsData, float heading, const NavigationData& navData,
                                    const Waypoint& target, NavigationState navState, const SpeedState& speedState) {
    String json = "{";
    json += "\"has_fix\":" + String(gpsData.hasFix ? "true" : "false") + ",";
    json += "\"satellites\":" + String(gpsData.satellites) + ",";
    json += "\"currentLat\":" + String(gpsData.latitude, 6) + ",";
    json += "\"currentLon\":" + String(gpsData.longitude, 6) + ",";
    json += "\"altitude\":" + String(gpsData.altitude, 1) + ",";
    json += "\"hdop\":" + String(gpsData.hdop, 1) + ",";
    json += "\"heading\":" + String(heading, 1) + ",";
    json += "\"distance\":" + String(navData.distanceToTarget, 1) + ",";
    json += "\"bearing\":" + String(navData.bearingToTarget, 1) + ",";
    json += "\"relative\":" + String(navData.relativeAngle, 1) + ",";

    if (target.isSet) {
        json += "\"targetLat\":" + String(target.latitude, 6) + ",";
        json += "\"targetLon\":" + String(target.longitude, 6) + ",";
        json += "\"hasTarget\":true,";
    } else {
        json += "\"hasTarget\":false,";
    }

    const char* stateStr = "idle";
    switch (navState) {
        case NavigationState::Idle: stateStr = "idle"; break;
        case NavigationState::Navigating: stateStr = "navigating"; break;
        case NavigationState::PathFollowing: stateStr = "path"; break;
        case NavigationState::SpotLock: stateStr = "spotlock"; break;
        case NavigationState::Arrived: stateStr = "arrived"; break;
        case NavigationState::Manual: stateStr = "manual"; break;
    }
    json += "\"navState\":\"" + String(stateStr) + "\",";

    json += "\"speedLevel\":" + String(speedState.currentLevel) + ",";
    json += "\"targetSpeed\":" + String(speedState.targetLevel) + ",";
    json += "\"speedKmh\":" + String(speedState.currentLevel * 0.36f, 1);

    json += "}";
    return json;
}

void BleManager::sendStatus(const GpsData& gpsData, float heading, const NavigationData& navData,
                             const Waypoint& target, NavigationState navState, const SpeedState& speedState) {
    if (!_status.connected)
        return;

    uint32_t now = millis();
    if ((now - _lastStatusTime) < BleConfig::statusIntervalMs)
        return;

    _lastStatusTime = now;

    String json = buildStatusJson(gpsData, heading, navData, target, navState, speedState);
    _statusChar->setValue(json.c_str());
    _statusChar->notify();
}

void BleManager::sendCalibrationData(const String& data) {
    if (!_status.connected)
        return;

    _calibrationChar->setValue(data.c_str());
    _calibrationChar->notify();
}

void BleManager::sendResponse(const String& response) {
    if (!_status.connected)
        return;

    _calibrationChar->setValue(response.c_str());
    _calibrationChar->notify();
}

bool BleManager::isConnected() const {
    return _status.connected;
}

bool BleManager::hasWaypointPending() const {
    return _status.waypointReceived;
}

Waypoint BleManager::consumeWaypoint() {
    Waypoint wp;
    if (_status.waypointReceived) {
        wp.set(_status.waypointLat, _status.waypointLon);
        if (_status.waypointName[0] != '\0') {
            strncpy(wp.name, _status.waypointName, 31);
            wp.name[31] = '\0';
        }
        wp.spotLockEnabled = _status.waypointSpotLock;
        wp.approachSpeed = _status.waypointSpeed;
        _status.waypointReceived = false;
        _status.waypointLat = 0.0f;
        _status.waypointLon = 0.0f;
        _status.waypointName[0] = '\0';
        _status.waypointSpotLock = false;
        _status.waypointSpeed = 0.0f;
    }
    return wp;
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

bool BleManager::hasPendingSpeed() const {
    return _status.hasPendingSpeed;
}

float BleManager::consumePendingSpeed() {
    float speed = _status.pendingSpeed;
    _status.pendingSpeed = 0.0f;
    _status.hasPendingSpeed = false;
    return speed;
}