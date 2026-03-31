#include "WaypointNavController.h"
#include "NavMath.h"
#include <math.h>

using namespace NavMath;

static constexpr float    EARTH_RADIUS_M         = 6371000.0f;
static constexpr uint32_t HOLD_RETRANSMIT_MS     = 68;
static constexpr uint32_t SPEED_HOLD_DURATION_MS = 1000;
static constexpr uint32_t STEERING_RELEASE_DELAY = 200;
static constexpr float    SAFE_ROTATION_LEVEL    = 360.0f;
static constexpr float    NAV_RAMP_ZONE_M        = 8.0f;  // start slowing within this distance of deadZone
static constexpr uint32_t RAMP_DOWN_DELAY_MS     = 500;   // faster decel: don't wait full speedChangeDelay when stepping down
static constexpr uint32_t RESYNC_INTERVAL_MS     = 5000;  // re-assert zero every 5 s while stationary to correct speed-state drift

WaypointNavController::WaypointNavController(Remote& remote)
    : _remote(remote) {}

// ============================================================
// start()
// ============================================================
void WaypointNavController::start(float targetLat, float targetLon, uint8_t maxSpeedLevel) {
    Serial.printf("[Nav] START target=%.6f,%.6f speed=%d\n", targetLat, targetLon, maxSpeedLevel);
    resetMotion();

    _navMaxSpeed        = constrain(maxSpeedLevel, (uint8_t)1, (uint8_t)10);
    _state.active       = true;
    _state.targetLat    = targetLat;
    _state.targetLon    = targetLon;
    _state.speedLevel   = 0;
    _state.arriving     = false;
    _cancelling         = false;

    // Zero motor speed: 10 x single Down packets, 100 ms apart
    Serial.println("[Nav] Zeroing motor speed...");
    for (uint8_t i = 0; i < 10; i++) {
        _remote.transmitSingle(Button::Down);
        delay(100);
    }
    Serial.println("[Nav] Motor zeroed, navigation active");
}

// ============================================================
// cancel()
// ============================================================
void WaypointNavController::cancel() {
    if (!_state.active && !_cancelling) return;
    Serial.println("[Nav] CANCEL");

    if (_holdActive) releaseSteeringHold();

    _state.active   = false;
    _state.arriving = false;

    if (_currentSpeed > 0 || _speedHoldActive) {
        startSpeedStep(false);
        _targetSpeed  = 0;
        _cancelling   = true;
    } else {
        _cancelling = false;
        resetMotion();
    }
}

// ============================================================
// applySettings()
// ============================================================
void WaypointNavController::applySettings(const SpotLockSettings& s) {
    _settings = s;
    Serial.printf("[Nav] Settings applied – deadZone=%.1fm rampStart=%.1fm\n",
                  _settings.deadZoneRadius,
                  _settings.deadZoneRadius + NAV_RAMP_ZONE_M);
}

// ============================================================
// update() – call every loop iteration
// ============================================================
bool WaypointNavController::update(const GpsData& gps, float heading) {
    uint32_t now = millis();

    // Graceful stop after cancel()
    if (_cancelling) {
        processSpeedStep(now);
        if (_currentSpeed == 0 && !_speedHoldActive && _targetSpeed == 0) {
            _cancelling = false;
            resetMotion();
        }
        return false;
    }

    if (!_state.active) return false;

    processSteeringHold(now);
    processSpeedStep(now);
    processDeadReckoning(now);

    _state.speedLevel = (uint8_t)max(0, (int)_currentSpeed);

    return runCorrectionLogic(gps, heading, now);
}

// ============================================================
// Steering hold – non-blocking, 68 ms retransmit
// ============================================================
void WaypointNavController::processSteeringHold(uint32_t now) {
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

void WaypointNavController::startSteeringHold(SteerDir dir, uint16_t durationMs) {
    Button btn = (dir == SteerDir::Left) ? Button::Left : Button::Right;
    _remote.transmitSingle(btn);

    _holdDir        = dir;
    _holdActive     = true;
    _holdStart      = millis();
    _holdDuration   = durationMs;
    _holdRetransmit = millis();

    float rotAmt = (float)durationMs * _settings.rotationPerMs;
    if (dir == SteerDir::Right) _cumulativeRotation += rotAmt;
    else                        _cumulativeRotation -= rotAmt;
}

void WaypointNavController::releaseSteeringHold() {
    if (!_holdActive) return;
    _remote.transmitSingle(Button::Release);
    _holdActive = false;
    _holdDir    = SteerDir::None;
}

// ============================================================
// Speed stepping – non-blocking, 1 s hold per step
// ============================================================
void WaypointNavController::processSpeedStep(uint32_t now) {
    if (_holdActive && !_cancelling) return;

    if (_speedHoldActive) {
        if ((now - _speedHoldStart) >= SPEED_HOLD_DURATION_MS) {
            _remote.transmitSingle(Button::Release);
            _speedHoldActive = false;
            if (_speedHoldUp) _currentSpeed = min((int8_t)(_currentSpeed + 1), (int8_t)_settings.maxSpeed);
            else              _currentSpeed = max((int8_t)(_currentSpeed - 1), (int8_t)0);
            _state.speedLevel  = (uint8_t)max(0, (int)_currentSpeed);
            _lastSpeedStepTime = now;
        } else {
            if ((now - _speedHoldRetransmit) >= HOLD_RETRANSMIT_MS) {
                _remote.transmitSingle(_speedHoldUp ? Button::Up : Button::Down);
                _speedHoldRetransmit = now;
            }
        }
        return;
    }

    // Periodic zero-assert: while motor is believed stopped, send a Down pulse every
    // RESYNC_INTERVAL_MS to correct any speed-state drift from missed RF packets.
    if (_currentSpeed == 0 && _targetSpeed == 0 && !_cancelling) {
        if (_lastResyncMs == 0) {
            _lastResyncMs = now;  // arm timer on first stationary cycle
        } else if ((now - _lastResyncMs) >= RESYNC_INTERVAL_MS) {
            _remote.transmitSingle(Button::Down);
            _lastResyncMs = now;
        }
        return;
    }
    _lastResyncMs = 0;  // reset timer whenever motor is commanded to move

    if (_currentSpeed == _targetSpeed) return;

    // Asymmetric ramp delays: decelerate quickly (500 ms), accelerate at the
    // configured rate (speedChangeDelayMs, default 2000 ms).
    uint32_t stepDelay = (_targetSpeed > _currentSpeed)
        ? (uint32_t)_settings.speedChangeDelayMs
        : RAMP_DOWN_DELAY_MS;
    if ((now - _lastSpeedStepTime) < stepDelay) return;

    startSpeedStep(_targetSpeed > _currentSpeed);
}

void WaypointNavController::startSpeedStep(bool goUp) {
    Button btn = goUp ? Button::Up : Button::Down;
    _remote.transmitSingle(btn);
    _speedHoldActive     = true;
    _speedHoldUp         = goUp;
    _speedHoldStart      = millis();
    _speedHoldRetransmit = millis();
}

void WaypointNavController::setTargetSpeed(int8_t target) {
    int8_t clamped = max((int8_t)0, min(target, (int8_t)_navMaxSpeed));
    if (clamped != 0 && clamped < (int8_t)_settings.minSpeed) clamped = (int8_t)_settings.minSpeed;
    _targetSpeed = clamped;
}

// ============================================================
// Core correction logic
// ============================================================
bool WaypointNavController::runCorrectionLogic(const GpsData& gps, float heading, uint32_t now) {
    if (!isGpsAcceptable(gps)) {
        _consecutiveGpsFail++;
        Serial.printf("[Nav] GPS quality fail %d/%d\n",
                      _consecutiveGpsFail, _settings.maxConsecutiveGpsFail);
        if (_consecutiveGpsFail >= _settings.maxConsecutiveGpsFail) {
            Serial.println("[Nav] GPS insufficient – cancelling navigation");
            cancel();
        }
        return false;
    }
    _consecutiveGpsFail = 0;

    if ((now - _lastCorrectionTime) < (uint32_t)_settings.correctionIntervalMs) return false;
    if (_holdActive) return false;
    if (_holdReleaseTime > 0 && (now - _holdReleaseTime) < STEERING_RELEASE_DELAY) return false;

    _lastCorrectionTime = now;

    // Kalman-filtered distance reduces GPS noise without the lag of a sliding mean.
    // Bearing is computed from raw GPS — directional noise is acceptable for bang-bang steering.
    float rawDist = haversineDistance(gps.latitude, gps.longitude, _state.targetLat, _state.targetLon);
    float dist    = _kalmanDist.update(rawDist);
    _lastKalmanDist = dist;
    _lastKalmanMs   = now;
    float bearing = bearingTo(gps.latitude, gps.longitude, _state.targetLat, _state.targetLon);

    _state.distMetres = dist;
    _state.bearingDeg = bearing;

    // Arrival check
    if (dist <= _settings.deadZoneRadius) {
        _state.arriving = false;
        Serial.printf("[Nav] ARRIVED – dist=%.2fm\n", dist);
        return true;
    }

    _state.arriving = (dist <= (_settings.deadZoneRadius + NAV_RAMP_ZONE_M));

    // Heading correction
    float relAngle = normalizeAngle180(bearing - heading);

    // Slow EMA of bearing error: adapts to persistent wind/current offset over ~20 corrections
    _bearingBias = 0.95f * _bearingBias + 0.05f * relAngle;
    float correctedRelAngle = relAngle - _bearingBias;
    float absAngle = fabsf(correctedRelAngle);

    // Cable tangle check (prevents indefinite circular motion)
    float absRot           = fabsf(_cumulativeRotation);
    bool  startUntangle    = absRot > _settings.maxRotationBeforeUntangle;
    bool  continueUntangle = _isUntangling && (absRot > SAFE_ROTATION_LEVEL);

    if (startUntangle || continueUntangle) {
        if (!_isUntangling) {
            _isUntangling = true;
            Serial.printf("[Nav] TANGLE %.1fdeg – untangling\n", _cumulativeRotation);
        }
        SteerDir dir = (_cumulativeRotation > 0) ? SteerDir::Left : SteerDir::Right;
        startSteeringHold(dir, steeringDuration(90.0f));

    } else if (absAngle > _settings.headingTolerance) {
        if (_isUntangling) {
            _isUntangling = false;
            _cumulativeRotation = 0.0f;  // re-zero after untangle completes
            Serial.printf("[Nav] UNTANGLED\n");
        }

        // Bidirectional turn bias: if cable is significantly wound, consider going the other
        // way if it reaches the target without adding too much distance.
        float altAngle = 360.0f - absAngle;
        bool useAltDir = (fabsf(_cumulativeRotation) > 180.0f)
                      && (altAngle <= (float)_settings.largeAngleThreshold * 2.0f)
                      && (altAngle <= absAngle * 2.5f);

        SteerDir dir = useAltDir
            ? ((correctedRelAngle > 0) ? SteerDir::Left  : SteerDir::Right)
            : ((correctedRelAngle > 0) ? SteerDir::Right : SteerDir::Left);
        float steerAngle = useAltDir ? altAngle : absAngle;

        if (useAltDir) Serial.printf("[Nav] Alt turn dir chosen – rot=%.1fdeg\n", _cumulativeRotation);
        startSteeringHold(dir, steeringDuration(steerAngle));

    } else {
        if (_isUntangling) {
            _isUntangling = false;
            _cumulativeRotation = 0.0f;  // re-zero after untangle completes
        }
    }

    // Speed – cruise or ramp
    setTargetSpeed(targetSpeedForDist(dist));

    Serial.printf("[Nav] dist=%.2fm bear=%.1f hdg=%.1f rel=%.1f bias=%.1f spd=%d/%d arriving=%s\n",
                  dist, bearing, heading, relAngle, _bearingBias,
                  _currentSpeed, _targetSpeed,
                  _state.arriving ? "YES" : "NO");

    return false;
}

// ============================================================
// Target speed for distance
// Three zones:
//   dist > deadZone + RAMP_ZONE → full cruise speed
//   deadZone < dist <= deadZone + RAMP_ZONE → linear ramp to minSpeed
//   dist <= deadZone → 0 (arrival, handled by caller)
// ============================================================
int8_t WaypointNavController::targetSpeedForDist(float dist) const {
    float rampStart = _settings.deadZoneRadius + NAV_RAMP_ZONE_M;
    if (dist >= rampStart) return (int8_t)_navMaxSpeed;

    float t = (dist - _settings.deadZoneRadius) / NAV_RAMP_ZONE_M;  // 0..1
    t = sqrtf(max(0.0f, t));  // sqrt: gentler near arrival, steeper at ramp entry
    float spd = _settings.minSpeed + t * ((float)_navMaxSpeed - _settings.minSpeed);
    return (int8_t)max((int)_settings.minSpeed, (int)roundf(spd));
}

// ============================================================
// GPS quality (identical to SpotLockController)
// ============================================================
bool WaypointNavController::isGpsAcceptable(const GpsData& gps) const {
    if (!gps.hasFix)                                 return false;
    if (gps.satellites < _settings.minSatellites)    return false;
    const bool hdopValid = (gps.hdop < 99.0f);  // values >= 99.0 are the NMEA "unknown" sentinel
    if (hdopValid && gps.hdop >= _settings.maxHDOP) return false;
    uint32_t age = millis() - gps.timestamp;
    if (gps.timestamp > 0 && age > 2000)             return false;
    return true;
}

// ============================================================
// Steering duration (same thresholds as SpotLock)
// ============================================================
uint16_t WaypointNavController::steeringDuration(float absAngle) const {
    if (absAngle >= _settings.largeAngleThreshold) return _settings.largeSteeringDuration;
    if (absAngle >= _settings.smallAngleThreshold) return _settings.mediumSteeringDuration;
    return _settings.smallSteeringDuration;
}

// ============================================================
// Dead reckoning – projects distance forward between GPS updates
// ============================================================
void WaypointNavController::processDeadReckoning(uint32_t now) {
    if (!_state.active || _lastKalmanMs == 0) return;

    uint32_t msSinceKalman = now - _lastKalmanMs;
    if (msSinceKalman > 1200) return;  // GPS too stale for reliable projection

    float elapsed  = msSinceKalman / 1000.0f;
    float projDist = fmaxf(0.0f, _lastKalmanDist - speedLevelToMs[_currentSpeed] * elapsed);

    setTargetSpeed(targetSpeedForDist(projDist));
}

// ============================================================
// resetMotion() – clear all motion state
// ============================================================
void WaypointNavController::resetMotion() {
    _holdDir             = SteerDir::None;
    _holdActive          = false;
    _holdStart           = 0;
    _holdDuration        = 0;
    _holdRetransmit      = 0;
    _holdReleaseTime     = 0;

    _currentSpeed        = 0;
    _targetSpeed         = 0;
    _speedHoldActive     = false;
    _speedHoldUp         = true;
    _speedHoldStart      = 0;
    _speedHoldRetransmit = 0;
    _lastSpeedStepTime   = 0;

    _lastCorrectionTime  = 0;
    _lastResyncMs        = 0;
    _cumulativeRotation  = 0.0f;
    _isUntangling        = false;
    _consecutiveGpsFail  = 0;

    _bearingBias    = 0.0f;
    _lastKalmanDist = 0.0f;
    _lastKalmanMs   = 0;

    _kalmanDist.reset();

    _state               = WaypointNavState();
}

// Math helpers are provided by NavMath.h (NavMath:: namespace, pulled in via `using namespace NavMath`)
