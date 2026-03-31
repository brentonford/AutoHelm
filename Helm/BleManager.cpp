#include "BleManager.h"

BleManager::BleManager()
    : _server(nullptr)
    , _service(nullptr)
    , _sensorStatusChar(nullptr)
    , _commandChar(nullptr)
    , _calibrationChar(nullptr)
    , _responseChar(nullptr)
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

    // Dedicated response characteristic for command acknowledgments
    _responseChar = _service->createCharacteristic(
        BleConfig::responseCharUuid,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    _responseChar->addDescriptor(new BLE2902());

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
    } else if (strncmp(cmd, "CAL_VALUES:", 11) == 0) {
        float offsetX, offsetY, offsetZ, scaleX, scaleY, scaleZ, headingOffset = 0.0f;
        int parsed = sscanf(cmd + 11, "%f,%f,%f,%f,%f,%f,%f", 
                   &offsetX, &offsetY, &offsetZ, &scaleX, &scaleY, &scaleZ, &headingOffset);
        
        if (parsed >= 6) {  // headingOffset is optional (for backward compatibility)
            _status.pendingCalibration.offsetX = offsetX;
            _status.pendingCalibration.offsetY = offsetY;
            _status.pendingCalibration.offsetZ = offsetZ;
            _status.pendingCalibration.scaleX = scaleX;
            _status.pendingCalibration.scaleY = scaleY;
            _status.pendingCalibration.scaleZ = scaleZ;
            _status.pendingCalibration.headingOffset = (parsed == 7) ? headingOffset : 0.0f;
            _status.hasCalibrationPending = true;
            Serial.printf("[BLE] Calibration values received: Offsets(%.2f,%.2f,%.2f) Scales(%.4f,%.4f,%.4f) HeadingOffset(%.1f)\n",
                offsetX, offsetY, offsetZ, scaleX, scaleY, scaleZ, _status.pendingCalibration.headingOffset);
            sendResponse("{\"ack\":\"CAL_VALUES\"}");
        } else {
            Serial.println("[BLE] ERROR: Failed to parse calibration values");
            sendResponse("{\"error\":\"Invalid CAL_VALUES format\"}");
        }
    } else if (strcmp(cmd, "SPOTLOCK_DISENGAGE") == 0) {
        _status.pendingSlCommand = SpotLockCommand::Disengage;
        sendResponse("{\"ack\":\"SPOTLOCK_DISENGAGE\"}");

    } else if (strncmp(cmd, "SPOTLOCK_ENGAGE:", 16) == 0) {
        float lat = 0.0f, lon = 0.0f;
        if (sscanf(cmd + 16, "%f,%f", &lat, &lon) == 2) {
            _status.slEngageLat      = lat;
            _status.slEngageLon      = lon;
            _status.pendingSlCommand = SpotLockCommand::Engage;
            sendResponse("{\"ack\":\"SPOTLOCK_ENGAGE\"}");
        } else {
            sendResponse("{\"error\":\"Invalid SPOTLOCK_ENGAGE format\"}");
        }

    } else if (strncmp(cmd, "SPOTLOCK_JOG:", 13) == 0) {
        const char* dirStr = cmd + 13;
        if      (strcmp(dirStr, "FORWARD") == 0) _status.slJogDir = SpotLockJogDir::Forward;
        else if (strcmp(dirStr, "BACK")    == 0) _status.slJogDir = SpotLockJogDir::Back;
        else if (strcmp(dirStr, "LEFT")    == 0) _status.slJogDir = SpotLockJogDir::Left;
        else                                      _status.slJogDir = SpotLockJogDir::Right;
        _status.pendingSlCommand = SpotLockCommand::Jog;

    } else if (strncmp(cmd, "SPOTLOCK_SETTINGS:", 18) == 0) {
        // CSV: deadZone,activation,jog,minSpd,maxSpd,gain,spdDelayS,hdgTol,corrIntervalS,
        //      smallAng,largeAng,smallDur,medDur,largeDur,maxRot,rotPerMs,minSat,maxHDOP,maxFail,filterWin
        SpotLockSettings s;
        float spdDelaySec = 2.0f, corrIntervalSec = 1.0f;
        int minSpd = 3, maxSpd = 10, smallDur = 200, medDur = 600, largeDur = 1000;
        int minSat = 4, maxFail = 5, filterWin = 5;
        int parsed = sscanf(cmd + 18,
            "%f,%f,%f,%d,%d,%f,%f,%f,%f,%f,%f,%d,%d,%d,%f,%f,%d,%f,%d,%d",
            &s.deadZoneRadius, &s.activationThreshold, &s.jogDistance,
            &minSpd, &maxSpd, &s.proportionalGain,
            &spdDelaySec, &s.headingTolerance, &corrIntervalSec,
            &s.smallAngleThreshold, &s.largeAngleThreshold,
            &smallDur, &medDur, &largeDur,
            &s.maxRotationBeforeUntangle, &s.rotationPerMs,
            &minSat, &s.maxHDOP, &maxFail, &filterWin);

        if (parsed == 20) {
            s.minSpeed             = (uint8_t)minSpd;
            s.maxSpeed             = (uint8_t)maxSpd;
            s.speedChangeDelayMs   = spdDelaySec * 1000.0f;
            s.correctionIntervalMs = corrIntervalSec * 1000.0f;
            s.smallSteeringDuration= (uint16_t)smallDur;
            s.mediumSteeringDuration=(uint16_t)medDur;
            s.largeSteeringDuration= (uint16_t)largeDur;
            s.minSatellites        = (uint8_t)minSat;
            s.maxConsecutiveGpsFail= (uint8_t)maxFail;
            s.filterWindowSize     = (uint8_t)filterWin;
            _status.slPendingSettings  = s;
            _status.hasSlSettingsPending = true;
            sendResponse("{\"ack\":\"SPOTLOCK_SETTINGS\"}");
        } else {
            Serial.printf("[BLE] SPOTLOCK_SETTINGS parse failed – got %d/20 fields\n", parsed);
            sendResponse("{\"error\":\"Invalid SPOTLOCK_SETTINGS format\"}");
        }

    } else if (strncmp(cmd, "NAV_START:", 10) == 0) {
        float lat = 0.0f, lon = 0.0f;
        int   spd = 5;
        if (sscanf(cmd + 10, "%f,%f,%d", &lat, &lon, &spd) == 3) {
            _status.navTargetLat    = lat;
            _status.navTargetLon    = lon;
            _status.navTargetSpeed  = (uint8_t)constrain(spd, 1, 10);
            _status.pendingNavCommand = NavCommand::Start;
            Serial.printf("[BLE] NAV_START target=%.6f,%.6f speed=%d\n", lat, lon, spd);
            sendResponse("{\"ack\":\"NAV_START\"}");
        } else {
            sendResponse("{\"error\":\"Invalid NAV_START format\"}");
        }

    } else if (strcmp(cmd, "NAV_CANCEL") == 0) {
        _status.pendingNavCommand = NavCommand::Cancel;
        sendResponse("{\"ack\":\"NAV_CANCEL\"}");

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

String BleManager::buildSensorStatusJson(const GpsData& gpsData, float heading,
                                          const SpotLockState& sl,
                                          const WaypointNavState& nav) {
    static char json[BleConfig::jsonBufferSize];

    // Base fields
    int n = snprintf(json, sizeof(json),
        "{\"has_fix\":%s,\"satellites\":%d,\"currentLat\":%.6f,\"currentLon\":%.6f"
        ",\"altitude\":%.1f,\"hdop\":%.1f,\"heading\":%.1f",
        gpsData.hasFix ? "true" : "false",
        gpsData.satellites,
        gpsData.latitude, gpsData.longitude,
        gpsData.altitude, gpsData.hdop, heading
    );

    // SpotLock telemetry
    if (sl.active) {
        n += snprintf(json + n, sizeof(json) - n,
            ",\"sl_active\":true,\"sl_lat\":%.6f,\"sl_lon\":%.6f"
            ",\"sl_dist\":%.2f,\"sl_bearing\":%.1f,\"sl_speed\":%d"
            ",\"sl_rotation\":%.1f,\"sl_tangled\":%s,\"sl_thrust\":%s",
            sl.lockLat, sl.lockLon,
            sl.distanceM, sl.bearingDeg, sl.speedLevel,
            sl.cableRotation,
            sl.cableTangled   ? "true" : "false",
            sl.applyingThrust ? "true" : "false"
        );
    } else {
        n += snprintf(json + n, sizeof(json) - n, ",\"sl_active\":false");
    }

    // Navigation telemetry
    if (nav.active) {
        n += snprintf(json + n, sizeof(json) - n,
            ",\"nav_active\":true,\"nav_lat\":%.6f,\"nav_lon\":%.6f"
            ",\"nav_dist\":%.2f,\"nav_bearing\":%.1f,\"nav_speed\":%d,\"nav_arriving\":%s",
            nav.targetLat, nav.targetLon,
            nav.distMetres, nav.bearingDeg, nav.speedLevel,
            nav.arriving ? "true" : "false"
        );
    } else {
        n += snprintf(json + n, sizeof(json) - n, ",\"nav_active\":false");
    }

    snprintf(json + n, sizeof(json) - n, "}");

    if (n < 0 || static_cast<size_t>(n) >= sizeof(json) - 2) {
        Serial.println("[BLE] WARNING: JSON buffer truncated in buildSensorStatusJson");
    }
    return String(json);
}

void BleManager::sendSensorStatus(const GpsData& gpsData, float heading,
                                   const SpotLockState& slState,
                                   const WaypointNavState& navState) {
    if (!_status.connected || !_sensorStatusChar)
        return;

    uint32_t now = millis();
    if ((now - _lastStatusTime) < BleConfig::statusIntervalMs)
        return;

    _lastStatusTime = now;

    String json = buildSensorStatusJson(gpsData, heading, slState, navState);
    if (json.length() == 0 || json.length() >= BleConfig::jsonBufferSize) {
        Serial.println("[BLE] WARNING: JSON invalid in sendSensorStatus");
        return;
    }

    _sensorStatusChar->setValue((uint8_t*)json.c_str(), json.length());
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
    if (!_status.connected || !_responseChar)
        return;

    if (response.length() > BleConfig::jsonBufferSize) {
        Serial.println("[BLE] ERROR: Response too large");
        return;
    }

    _responseChar->setValue((uint8_t*)response.c_str(), response.length());
    _responseChar->notify();
}

void BleManager::sendResponse(const char* response) {
    if (!_status.connected || !_responseChar)
        return;

    size_t len = strlen(response);
    if (len > BleConfig::jsonBufferSize) {
        Serial.println("[BLE] ERROR: Response too large");
        return;
    }

    _responseChar->setValue((uint8_t*)response, len);
    _responseChar->notify();
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

bool BleManager::hasCalibrationPending() const {
    return _status.hasCalibrationPending;
}

CompassCalibration BleManager::consumeCalibration() {
    _status.hasCalibrationPending = false;
    return _status.pendingCalibration;
}

bool BleManager::hasSpotLockCommandPending() const {
    return _status.pendingSlCommand != SpotLockCommand::None;
}

SpotLockCommand BleManager::consumeSpotLockCommand() {
    SpotLockCommand cmd = _status.pendingSlCommand;
    _status.pendingSlCommand = SpotLockCommand::None;
    return cmd;
}

float BleManager::getSlEngageLat() const  { return _status.slEngageLat; }
float BleManager::getSlEngageLon() const  { return _status.slEngageLon; }
SpotLockJogDir BleManager::getSlJogDir() const { return _status.slJogDir; }

bool BleManager::hasSlSettingsPending() const {
    return _status.hasSlSettingsPending;
}

SpotLockSettings BleManager::consumeSlSettings() {
    _status.hasSlSettingsPending = false;
    return _status.slPendingSettings;
}

bool BleManager::hasNavCommandPending() const {
    return _status.pendingNavCommand != NavCommand::None;
}

NavCommand BleManager::consumeNavCommand() {
    NavCommand cmd = _status.pendingNavCommand;
    _status.pendingNavCommand = NavCommand::None;
    return cmd;
}

float   BleManager::getNavTargetLat()   const { return _status.navTargetLat; }
float   BleManager::getNavTargetLon()   const { return _status.navTargetLon; }
uint8_t BleManager::getNavTargetSpeed() const { return _status.navTargetSpeed; }