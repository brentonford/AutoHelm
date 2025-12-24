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
    String uuid = characteristic->getUUID().toString().c_str();
    String value = characteristic->getValue().c_str();

    if (characteristic == _commandChar) {
        Serial.printf("[BLE] Command received: %s\n", value.c_str());
        parseCommand(value);
    }
}

void BleManager::parseCommand(const String& data) {
    String cmd = data;
    cmd.trim();
    cmd.toUpperCase();

    if (cmd == "START_CAL") {
        _status.pendingCommand = BleCommand::StartCalibration;
        sendResponse("{\"ack\":\"START_CAL\"}");
    } else if (cmd == "STOP_CAL") {
        _status.pendingCommand = BleCommand::StopCalibration;
        sendResponse("{\"ack\":\"STOP_CAL\"}");
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

String BleManager::buildSensorStatusJson(const GpsData& gpsData, float heading) {
    String json = "{";
    json += "\"has_fix\":" + String(gpsData.hasFix ? "true" : "false") + ",";
    json += "\"satellites\":" + String(gpsData.satellites) + ",";
    json += "\"currentLat\":" + String(gpsData.latitude, 6) + ",";
    json += "\"currentLon\":" + String(gpsData.longitude, 6) + ",";
    json += "\"altitude\":" + String(gpsData.altitude, 1) + ",";
    json += "\"hdop\":" + String(gpsData.hdop, 1) + ",";
    json += "\"heading\":" + String(heading, 1);
    json += "}";
    return json;
}

void BleManager::sendSensorStatus(const GpsData& gpsData, float heading) {
    if (!_status.connected)
        return;

    uint32_t now = millis();
    if ((now - _lastStatusTime) < BleConfig::statusIntervalMs)
        return;

    _lastStatusTime = now;

    String json = buildSensorStatusJson(gpsData, heading);
    _sensorStatusChar->setValue(json.c_str());
    _sensorStatusChar->notify();
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