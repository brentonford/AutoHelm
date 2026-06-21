#include "SpotLockController.h"
#include "NavMath.h"
#include <math.h>

using namespace NavMath;

SpotLockController::SpotLockController(Remote& remote)
    : AutopilotMotorController(remote) {}

void SpotLockController::engage(float lat, float lon) {
    Serial.printf("[SpotLock] ENGAGE at %.6f, %.6f\n", lat, lon);
    clearGpsAborted();
    resetState();
    _lockLat  = lat;
    _lockLon  = lon;
    _active   = true;
    _state.active  = true;
    _state.lockLat = lat;
    _state.lockLon = lon;
    Serial.println("[SpotLock] Zeroing motor speed (non-blocking)...");
    beginMotorZeroing();
}

void SpotLockController::disengage() {
    if (!_active && !_disengaging) return;
    Serial.println("[SpotLock] DISENGAGE");

    if (_holdActive) releaseSteeringHold();

    _active = false;
    _state.active = false;

    if (_currentSpeed > 0 || _speedHoldActive) {
        startSpeedStep(false);
        _targetSpeed = 0;
        _disengaging = true;
    } else {
        resetState();
        _disengaging = false;
    }
}

void SpotLockController::jog(SpotLockJogDir dir) {
    if (!_active) return;

    float headingDeg;
    switch (dir) {
        case SpotLockJogDir::Forward: headingDeg =   0.0f; break;
        case SpotLockJogDir::Back:    headingDeg = 180.0f; break;
        case SpotLockJogDir::Left:    headingDeg = 270.0f; break;
        default:                      headingDeg =  90.0f; break;
    }

    float newLat, newLon;
    calcDestination(_lockLat, _lockLon, headingDeg, _settings.jogDistance, newLat, newLon);
    _lockLat = newLat;
    _lockLon = newLon;
    _kalmanDist.reset();
    _state.lockLat = _lockLat;
    _state.lockLon = _lockLon;

    Serial.printf("[SpotLock] JOG -> %.6f, %.6f\n", _lockLat, _lockLon);
}

void SpotLockController::applySettings(const SpotLockSettings& s) {
    _settings = s;
    Serial.printf("[SpotLock] Settings applied – deadZone=%.1fm activation=%.1fm\n",
                  _settings.deadZoneRadius, _settings.activationThreshold);
}

void SpotLockController::update(const GpsData& gps, float heading) {
    uint32_t now = millis();

    if (_disengaging) {
        processSpeedStep(now);
        if (_currentSpeed == 0 && !_speedHoldActive && _targetSpeed == 0) {
            _disengaging = false;
            resetState();
        }
        return;
    }

    if (!_active) return;

    if (_zeroing) {
        processMotorZeroing(now);
        return;
    }

    processSteeringHold(now);
    processSpeedStep(now);
    processDeadReckoning(now);
    runCorrectionLogic(gps, heading, now);

    _state.active         = true;
    _state.cableRotation  = _cumulativeRotation;
    _state.cableTangled   = (fabsf(_cumulativeRotation) > _settings.maxRotationBeforeUntangle);
    _state.applyingThrust = _applyingThrust;
    _state.speedLevel     = (uint8_t)max(0, (int)_currentSpeed);
}

void SpotLockController::runCorrectionLogic(const GpsData& gps, float heading, uint32_t now) {
    if (!isGpsAcceptable(gps)) {
        if (incrementGpsFailure()) {
            Serial.println("[SpotLock] GPS insufficient – disengaging");
            disengage();
        }
        return;
    }
    resetGpsFailures();

    if (!correctionIntervalElapsed(now) || _holdActive || !steeringCooldownElapsed(now)) return;
    markCorrectionTime(now);

    float rawDist = haversineDistance(gps.latitude, gps.longitude, _lockLat, _lockLon);
    float dist    = updateFilteredDistance(rawDist, now);
    float bearing = bearingTo(gps.latitude, gps.longitude, _lockLat, _lockLon);

    _state.distanceM  = dist;
    _state.bearingDeg = bearing;

    float relAngle = normalizeAngle180(bearing - heading);
    _bearingBias = 0.95f * _bearingBias + 0.05f * relAngle;
    float correctedRelAngle = relAngle - _bearingBias;
    float absAngle = fabsf(correctedRelAngle);
    float absRot   = fabsf(_cumulativeRotation);

    bool startUntangle    = absRot > _settings.maxRotationBeforeUntangle;
    bool continueUntangle = _isUntangling && (absRot > 360.0f);

    if (startUntangle || continueUntangle) {
        if (!_isUntangling) {
            _isUntangling = true;
            _state.cableTangled = true;
            Serial.printf("[SpotLock] TANGLE %.1fdeg – untangling\n", _cumulativeRotation);
        }
        SteerDir dir = (_cumulativeRotation > 0) ? SteerDir::Left : SteerDir::Right;
        startSteeringHold(dir, steeringDuration(90.0f));
    } else if (absAngle > _settings.headingTolerance) {
        clearUntangleState();
        _state.cableTangled = false;

        SteerDir dir;
        float steerAngle;
        if (resolveSteeringDirection(correctedRelAngle, absAngle, dir, steerAngle)) {
            Serial.printf("[SpotLock] Alt turn dir chosen – rot=%.1fdeg\n", _cumulativeRotation);
        }
        startSteeringHold(dir, steeringDuration(steerAngle));
    } else {
        clearUntangleState();
        _state.cableTangled = false;
    }

    if (dist > _settings.activationThreshold) {
        if (!_applyingThrust) {
            _applyingThrust = true;
            _state.applyingThrust = true;
        }
        setTargetSpeed((int8_t)proportionalSpeed(max(0.0f, dist - _settings.deadZoneRadius)));
    } else if (dist < _settings.deadZoneRadius) {
        if (_applyingThrust) {
            _applyingThrust = false;
            _state.applyingThrust = false;
            setTargetSpeed(0);
        }
        if (!_holdActive && !_isUntangling && fabsf(_cumulativeRotation) > 45.0f) {
            SteerDir dir = (_cumulativeRotation > 0) ? SteerDir::Left : SteerDir::Right;
            startSteeringHold(dir, _settings.smallSteeringDuration);
            Serial.printf("[SpotLock] Opportunistic unwind %.1fdeg\n", _cumulativeRotation);
        }
    }

    Serial.printf("[SpotLock] dist=%.2fm bear=%.1f hdg=%.1f rel=%.1f bias=%.1f spd=%d/%d\n",
                  dist, bearing, heading, relAngle, _bearingBias, _currentSpeed, _targetSpeed);
}

float SpotLockController::proportionalSpeed(float distBeyondDeadZone) const {
    if (distBeyondDeadZone <= 0.0f) return (float)_settings.minSpeed;
    float raw = distBeyondDeadZone * _settings.proportionalGain + (float)_settings.minSpeed;
    return fminf(raw, (float)_settings.maxSpeed);
}

void SpotLockController::processDeadReckoning(uint32_t now) {
    if (!_active || !_applyingThrust || _lastKalmanMs == 0) return;

    uint32_t msSinceKalman = now - _lastKalmanMs;
    if (msSinceKalman > 1200) return;

    float elapsed  = msSinceKalman / 1000.0f;
    float projDist = fmaxf(0.0f, _lastKalmanDist - speedLevelToMs[_currentSpeed] * elapsed);
    float excess   = fmaxf(0.0f, projDist - _settings.deadZoneRadius);
    setTargetSpeed((int8_t)proportionalSpeed(excess));
}

void SpotLockController::resetState() {
    resetMotorState();
    _applyingThrust = false;
    _state = SpotLockState();
    _state.lockLat = _lockLat;
    _state.lockLon = _lockLon;
}