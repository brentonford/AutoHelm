#include "SpotLockController.h"
#include <math.h>

static constexpr float    EARTH_RADIUS_M          = 6371000.0f;
static constexpr uint32_t HOLD_RETRANSMIT_MS      = 68;
static constexpr uint32_t SPEED_HOLD_DURATION_MS  = 1000;
static constexpr uint32_t STEERING_RELEASE_DELAY  = 200;
static constexpr float    SAFE_ROTATION_LEVEL     = 360.0f;

SpotLockController::SpotLockController(Remote& remote)
    : _remote(remote) {}

// ============================================================
// engage()
// ============================================================
void SpotLockController::engage(float lat, float lon) {
    Serial.printf("[SpotLock] ENGAGE at %.6f, %.6f\n", lat, lon);
    resetState();
    _lockLat  = lat;
    _lockLon  = lon;
    _active   = true;
    _state.active  = true;
    _state.lockLat = lat;
    _state.lockLon = lon;

    // Zero motor speed: 10 x single Down packets, 100 ms apart
    Serial.println("[SpotLock] Zeroing motor speed...");
    for (uint8_t i = 0; i < 10; i++) {
        _remote.transmitSingle(Button::Down);
        delay(100);
    }
    Serial.println("[SpotLock] Motor zeroed, algorithm active");
}

// ============================================================
// disengage()
// ============================================================
void SpotLockController::disengage() {
    if (!_active && !_disengaging) return;
    Serial.println("[SpotLock] DISENGAGE");

    if (_holdActive) releaseSteeringHold();

    _active = false;
    _state.active = false;

    if (_currentSpeed > 0 || _speedHoldActive) {
        // Kick off first Down step immediately then let speed logic finish
        startSpeedStep(false); // goUp = false
        _targetSpeed  = 0;
        _disengaging  = true;
    } else {
        resetState();
        _disengaging = false;
    }
}

// ============================================================
// jog()
// ============================================================
void SpotLockController::jog(SpotLockJogDir dir) {
    if (!_active) return;

    float headingDeg;
    switch (dir) {
        case SpotLockJogDir::Forward: headingDeg =   0.0f; break;
        case SpotLockJogDir::Back:    headingDeg = 180.0f; break;
        case SpotLockJogDir::Left:    headingDeg = 270.0f; break;
        default:                      headingDeg =  90.0f; break; // Right
    }

    float newLat, newLon;
    calcDestination(_lockLat, _lockLon, headingDeg, _settings.jogDistance, newLat, newLon);
    _lockLat = newLat;
    _lockLon = newLon;
    _histCount = 0;
    _histHead  = 0;
    _state.lockLat = _lockLat;
    _state.lockLon = _lockLon;

    Serial.printf("[SpotLock] JOG -> %.6f, %.6f\n", _lockLat, _lockLon);
}

// ============================================================
// applySettings()
// ============================================================
void SpotLockController::applySettings(const SpotLockSettings& s) {
    _settings = s;
    if (_settings.filterWindowSize > MAX_HIST) _settings.filterWindowSize = MAX_HIST;
    Serial.printf("[SpotLock] Settings applied – deadZone=%.1fm activation=%.1fm\n",
                  _settings.deadZoneRadius, _settings.activationThreshold);
}

// ============================================================
// update() – call every loop iteration
// ============================================================
void SpotLockController::update(const GpsData& gps, float heading) {
    uint32_t now = millis();

    // Graceful disengage: ramp speed to 0 before fully stopping
    if (_disengaging) {
        processSpeedStep(now);
        if (_currentSpeed == 0 && !_speedHoldActive && _targetSpeed == 0) {
            _disengaging = false;
            resetState();
        }
        return;
    }

    if (!_active) return;

    processSteeringHold(now);
    processSpeedStep(now);
    runCorrectionLogic(gps, heading, now);

    // Update telemetry
    _state.active        = true;
    _state.cableRotation = _cumulativeRotation;
    _state.cableTangled  = (fabsf(_cumulativeRotation) > _settings.maxRotationBeforeUntangle);
    _state.applyingThrust= _applyingThrust;
    _state.speedLevel    = (uint8_t)max(0, (int)_currentSpeed);
}

// ============================================================
// Steering hold – non-blocking, 68 ms retransmit
// ============================================================
void SpotLockController::processSteeringHold(uint32_t now) {
    if (!_holdActive) return;

    if ((now - _holdStart) >= _holdDuration) {
        releaseSteeringHold();
        _holdReleaseTime = now;
        return;
    }

    if ((now - _holdRetransmit) >= HOLD_RETRANSMIT_MS) {
        Button btn = (_holdDir == SteerDir::Left) ? Button::Left : Button::Right;
        _remote.transmitSingle(btn);
        _holdRetransmit = now;
    }
}

void SpotLockController::startSteeringHold(SteerDir dir, uint16_t durationMs) {
    Button btn = (dir == SteerDir::Left) ? Button::Left : Button::Right;
    _remote.transmitSingle(btn);

    _holdDir      = dir;
    _holdActive   = true;
    _holdStart    = millis();
    _holdDuration = durationMs;
    _holdRetransmit = millis();

    float rotAmt = (float)durationMs * _settings.rotationPerMs;
    if (dir == SteerDir::Right) _cumulativeRotation += rotAmt;
    else                        _cumulativeRotation -= rotAmt;
}

void SpotLockController::releaseSteeringHold() {
    if (!_holdActive) return;
    _remote.transmitSingle(Button::Release);
    _holdActive = false;
    _holdDir    = SteerDir::None;
}

// ============================================================
// Speed stepping – non-blocking, 1 s hold per step
// ============================================================
void SpotLockController::processSpeedStep(uint32_t now) {
    if (_holdActive) return; // Don't step speed while steering

    if (_speedHoldActive) {
        if ((now - _speedHoldStart) >= SPEED_HOLD_DURATION_MS) {
            _remote.transmitSingle(Button::Release);
            _speedHoldActive = false;
            if (_speedHoldUp) _currentSpeed = min((int8_t)(_currentSpeed + 1), (int8_t)_settings.maxSpeed);
            else              _currentSpeed = max((int8_t)(_currentSpeed - 1), (int8_t)0);
            _state.speedLevel = (uint8_t)max(0, (int)_currentSpeed);
            _lastSpeedStepTime = now;
        } else {
            if ((now - _speedHoldRetransmit) >= HOLD_RETRANSMIT_MS) {
                _remote.transmitSingle(_speedHoldUp ? Button::Up : Button::Down);
                _speedHoldRetransmit = now;
            }
        }
        return;
    }

    if (_currentSpeed == _targetSpeed) return;
    if ((now - _lastSpeedStepTime) < (uint32_t)_settings.speedChangeDelayMs) return;

    startSpeedStep(_targetSpeed > _currentSpeed);
}

void SpotLockController::startSpeedStep(bool goUp) {
    Button btn = goUp ? Button::Up : Button::Down;
    _remote.transmitSingle(btn);
    _speedHoldActive     = true;
    _speedHoldUp         = goUp;
    _speedHoldStart      = millis();
    _speedHoldRetransmit = millis();
}

void SpotLockController::setTargetSpeed(int8_t target) {
    int8_t clamped = max((int8_t)0, min(target, (int8_t)_settings.maxSpeed));
    if (clamped != 0 && clamped < (int8_t)_settings.minSpeed) clamped = (int8_t)_settings.minSpeed;
    _targetSpeed = clamped;
}

// ============================================================
// Core correction logic
// ============================================================
void SpotLockController::runCorrectionLogic(const GpsData& gps, float heading, uint32_t now) {
    if (!isGpsAcceptable(gps)) {
        _consecutiveGpsFail++;
        Serial.printf("[SpotLock] GPS quality fail %d/%d\n",
                      _consecutiveGpsFail, _settings.maxConsecutiveGpsFail);
        if (_consecutiveGpsFail >= _settings.maxConsecutiveGpsFail) {
            Serial.println("[SpotLock] GPS insufficient – disengaging");
            disengage();
        }
        return;
    }
    _consecutiveGpsFail = 0;

    if ((now - _lastCorrectionTime) < (uint32_t)_settings.correctionIntervalMs) return;
    if (_holdActive) return;
    if (_holdReleaseTime > 0 && (now - _holdReleaseTime) < STEERING_RELEASE_DELAY) return;

    _lastCorrectionTime = now;

    addToHistory(gps.latitude, gps.longitude);
    float filtLat, filtLon;
    getFilteredPos(filtLat, filtLon);

    float dist    = haversineDistance(filtLat, filtLon, _lockLat, _lockLon);
    float bearing = bearingTo(filtLat, filtLon, _lockLat, _lockLon);

    _state.distanceM  = dist;
    _state.bearingDeg = bearing;

    float relAngle = normalizeAngle180(bearing - heading);
    float absAngle = fabsf(relAngle);

    // Cable tangle check
    float absRot           = fabsf(_cumulativeRotation);
    bool  startUntangle    = absRot > _settings.maxRotationBeforeUntangle;
    bool  continueUntangle = _isUntangling && (absRot > SAFE_ROTATION_LEVEL);

    if (startUntangle || continueUntangle) {
        if (!_isUntangling) {
            _isUntangling       = true;
            _state.cableTangled = true;
            Serial.printf("[SpotLock] TANGLE %.1fdeg – untangling\n", _cumulativeRotation);
        }
        SteerDir dir = (_cumulativeRotation > 0) ? SteerDir::Left : SteerDir::Right;
        startSteeringHold(dir, steeringDuration(90.0f));

    } else if (absAngle > _settings.headingTolerance) {
        if (_isUntangling) {
            _isUntangling       = false;
            _state.cableTangled = false;
            Serial.printf("[SpotLock] UNTANGLED %.1fdeg\n", _cumulativeRotation);
        }
        SteerDir dir = (relAngle > 0) ? SteerDir::Right : SteerDir::Left;
        startSteeringHold(dir, steeringDuration(absAngle));

    } else {
        if (_isUntangling) {
            _isUntangling       = false;
            _state.cableTangled = false;
        }
    }

    // Thrust control
    if (dist > _settings.activationThreshold) {
        if (!_applyingThrust) { _applyingThrust = true; _state.applyingThrust = true; }
        setTargetSpeed((int8_t)proportionalSpeed(max(0.0f, dist - _settings.deadZoneRadius)));
    } else if (dist < _settings.deadZoneRadius) {
        if (_applyingThrust) { _applyingThrust = false; _state.applyingThrust = false; setTargetSpeed(0); }
    }

    Serial.printf("[SpotLock] dist=%.2fm bear=%.1f hdg=%.1f rel=%.1f spd=%d/%d\n",
                  dist, bearing, heading, relAngle, _currentSpeed, _targetSpeed);
}

// ============================================================
// GPS quality
// ============================================================
bool SpotLockController::isGpsAcceptable(const GpsData& gps) const {
    if (!gps.hasFix)                                 return false;
    if (gps.satellites < _settings.minSatellites)    return false;
    if (gps.hdop < 98.0f && gps.hdop >= _settings.maxHDOP) return false;
    uint32_t age = millis() - gps.timestamp;
    if (gps.timestamp > 0 && age > 2000)             return false;
    return true;
}

// ============================================================
// Position history (circular buffer)
// ============================================================
void SpotLockController::addToHistory(float lat, float lon) {
    uint8_t win = min(_settings.filterWindowSize, (uint8_t)MAX_HIST);
    _histLat[_histHead] = lat;
    _histLon[_histHead] = lon;
    _histHead = (_histHead + 1) % win;
    if (_histCount < win) _histCount++;
}

void SpotLockController::getFilteredPos(float& lat, float& lon) const {
    if (_histCount < 3) {
        // Return last sample
        uint8_t win  = min(_settings.filterWindowSize, (uint8_t)MAX_HIST);
        uint8_t last = (_histHead == 0) ? (win - 1) : (_histHead - 1);
        lat = _histLat[last];
        lon = _histLon[last];
        return;
    }
    float sumLat = 0.0f, sumLon = 0.0f;
    for (uint8_t i = 0; i < _histCount; i++) {
        sumLat += _histLat[i];
        sumLon += _histLon[i];
    }
    lat = sumLat / _histCount;
    lon = sumLon / _histCount;
}

// ============================================================
// Steering duration (mirrors Swift calculateSteeringDuration)
// ============================================================
uint16_t SpotLockController::steeringDuration(float absAngle) const {
    if (absAngle >= _settings.largeAngleThreshold)  return _settings.largeSteeringDuration;
    if (absAngle >= _settings.smallAngleThreshold)  return _settings.mediumSteeringDuration;
    return _settings.smallSteeringDuration;
}

// ============================================================
// Proportional speed (mirrors Swift calculateProportionalSpeed)
// ============================================================
float SpotLockController::proportionalSpeed(float distBeyondDeadZone) const {
    if (distBeyondDeadZone <= 0.0f) return (float)_settings.minSpeed;
    float raw = distBeyondDeadZone * _settings.proportionalGain + (float)_settings.minSpeed;
    return fminf(raw, (float)_settings.maxSpeed);
}

// ============================================================
// resetState()
// ============================================================
void SpotLockController::resetState() {
    _holdDir          = SteerDir::None;
    _holdActive       = false;
    _holdStart        = 0;
    _holdDuration     = 0;
    _holdRetransmit   = 0;
    _holdReleaseTime  = 0;

    _currentSpeed        = 0;
    _targetSpeed         = 0;
    _speedHoldActive     = false;
    _speedHoldUp         = true;
    _speedHoldStart      = 0;
    _speedHoldRetransmit = 0;
    _lastSpeedStepTime   = 0;
    _applyingThrust      = false;

    _lastCorrectionTime = 0;
    _cumulativeRotation = 0.0f;
    _isUntangling       = false;

    _consecutiveGpsFail = 0;
    _histHead           = 0;
    _histCount          = 0;

    _state            = SpotLockState();
    _state.lockLat    = _lockLat;
    _state.lockLon    = _lockLon;
}

// ============================================================
// Math helpers
// ============================================================
float SpotLockController::haversineDistance(float lat1Deg, float lon1Deg,
                                             float lat2Deg, float lon2Deg) {
    float lat1 = lat1Deg * (float)DEG_TO_RAD;
    float lat2 = lat2Deg * (float)DEG_TO_RAD;
    float dLat = (lat2Deg - lat1Deg) * (float)DEG_TO_RAD;
    float dLon = (lon2Deg - lon1Deg) * (float)DEG_TO_RAD;
    float a = sinf(dLat * 0.5f) * sinf(dLat * 0.5f) +
              cosf(lat1) * cosf(lat2) * sinf(dLon * 0.5f) * sinf(dLon * 0.5f);
    return EARTH_RADIUS_M * 2.0f * atan2f(sqrtf(a), sqrtf(1.0f - a));
}

float SpotLockController::bearingTo(float lat1Deg, float lon1Deg,
                                     float lat2Deg, float lon2Deg) {
    float lat1 = lat1Deg * (float)DEG_TO_RAD;
    float lat2 = lat2Deg * (float)DEG_TO_RAD;
    float dLon = (lon2Deg - lon1Deg) * (float)DEG_TO_RAD;
    float y = sinf(dLon) * cosf(lat2);
    float x = cosf(lat1) * sinf(lat2) - sinf(lat1) * cosf(lat2) * cosf(dLon);
    return fmodf(atan2f(y, x) * (float)RAD_TO_DEG + 360.0f, 360.0f);
}

float SpotLockController::normalizeAngle180(float angle) {
    while (angle >  180.0f) angle -= 360.0f;
    while (angle < -180.0f) angle += 360.0f;
    return angle;
}

void SpotLockController::calcDestination(float lat, float lon, float headingDeg, float distM,
                                          float& outLat, float& outLon) {
    float rad  = headingDeg * (float)DEG_TO_RAD;
    float mpdl = 111320.0f;
    outLat = lat + (distM / mpdl) * cosf(rad);
    outLon = lon + (distM / (mpdl * cosf(lat * (float)DEG_TO_RAD))) * sinf(rad);
}
