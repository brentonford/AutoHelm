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

    // FFE1: Waypoint (Write)
    _waypointChar = _service->createCharacteristic(
        BleConfig::waypointCharUuid,
        BLECharacteristic::PROPERTY_WRITE
    );
    _waypointChar->setCallbacks(this);

    // FFE2: Status (Notify)
    _statusChar = _service->createCharacteristic(
        BleConfig::statusCharUuid,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    _statusChar->addDescriptor(new BLE2902());

    // FFE3: Command (Write)
    _commandChar = _service->createCharacteristic(
        BleConfig::commandCharUuid,
        BLECharacteristic::PROPERTY_WRITE
    );
    _commandChar->setCallbacks(this);

    // FFE4: Calibration/Response (Notify)
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
    // Status broadcasting is handled by sendStatus() called from main loop
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
    // Format: $GPS,lat,lon,alt*
    if (!data.startsWith("$GPS,")) {
        sendResponse("{\"error\":\"Invalid waypoint format\"}");
        return;
    }

    int firstComma = data.indexOf(',');
    int secondComma = data.indexOf(',', firstComma + 1);
    int thirdComma = data.indexOf(',', secondComma + 1);

    if (firstComma < 0 || secondComma < 0) {
        sendResponse("{\"error\":\"Invalid waypoint format\"}");
        return;
    }

    String latStr = data.substring(firstComma + 1, secondComma);
    String lonStr;

    if (thirdComma > 0) {
        lonStr = data.substring(secondComma + 1, thirdComma);
    } else {
        int endPos = data.indexOf('*');
        if (endPos < 0)
            endPos = data.length();
        lonStr = data.substring(secondComma + 1, endPos);
    }

    _status.waypointLat = latStr.toFloat();
    _status.waypointLon = lonStr.toFloat();

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
    } else {
        sendResponse("{\"error\":\"Unknown command\"}");
    }
}

String BleManager::buildStatusJson(const GpsData& gpsData, float heading, const NavigationData& navData, const Waypoint& target) {
    String json = "{";
    json += "\"has_fix\":" + String(gpsData.hasFix ? "true" : "false") + ",";
    json += "\"satellites\":" + String(gpsData.satellites) + ",";
    json += "\"currentLat\":" + String(gpsData.latitude, 6) + ",";
    json += "\"currentLon\":" + String(gpsData.longitude, 6) + ",";
    json += "\"altitude\":" + String(gpsData.altitude, 1) + ",";
    json += "\"hdop\":" + String(gpsData.hdop, 1) + ",";
    json += "\"heading\":" + String(heading, 1) + ",";
    json += "\"distance\":" + String(navData.distanceToTarget, 1) + ",";
    json += "\"bearing\":" + String(navData.bearingToTarget, 1);

    if (target.isSet) {
        json += ",\"targetLat\":" + String(target.latitude, 6);
        json += ",\"targetLon\":" + String(target.longitude, 6);
    }

    json += "}";
    return json;
}

void BleManager::sendStatus(const GpsData& gpsData, float heading, const NavigationData& navData, const Waypoint& target) {
    if (!_status.connected)
        return;

    uint32_t now = millis();
    if ((now - _lastStatusTime) < BleConfig::statusIntervalMs)
        return;

    _lastStatusTime = now;

    String json = buildStatusJson(gpsData, heading, navData, target);
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
        _status.waypointReceived = false;
        _status.waypointLat = 0.0f;
        _status.waypointLon = 0.0f;
    }
    return wp;
}

BleCommand BleManager::consumeCommand() {
    BleCommand cmd = _status.pendingCommand;
    _status.pendingCommand = BleCommand::None;
    return cmd;
}