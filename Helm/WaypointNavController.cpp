#include "WaypointNavController.h"
#include "NavMath.h"
#include <math.h>

using namespace NavMath;

WaypointNavController::WaypointNavController(Remote& remote)
    : AutopilotMotorController(remote) {}

void WaypointNavController::start(float targetLat, float targetLon, uint8_t maxSpeedLevel, bool knownZero) {
    Serial.printf("[Nav] START target=%.6f,%.6f speed=%d\n", targetLat, targetLon, maxSpeedLevel);
    clearGpsAborted();
    resetMotion();

    _navMaxSpeed      = constrain(maxSpeedLevel, (uint8_t)1, (uint8_t)10);
    _state.active     = true;
    _state.targetLat  = targetLat;
    _state.targetLon  = targetLon;
    _state.speedLevel = 0;
    _state.arriving   = false;
    _cancelling       = false;

    if (knownZero) {
        _speedKnown   = true;
        _currentSpeed = 0;
        _targetSpeed  = (int8_t)_navMaxSpeed;
        Serial.println("[Nav] Speed already at 0");
    } else {
        Serial.println("[Nav] Zeroing motor speed (non-blocking)...");
        beginMotorZeroing();
    }
}

void WaypointNavController::cancel() {
    if (!_state.active && !_cancelling) return;
    if (_cancelling) return;
    Serial.println("[Nav] CANCEL");

    if (_holdActive) releaseSteeringHold();
    if (_zeroPressActive) {
        _remote.transmitSingle(Button::Release);
        _zeroPressActive = false;
    }
    _zeroing = false;
    _state.arriving = false;

    if (_speedHoldActive && _speedHoldUp) {
        _remote.transmitSingle(Button::Release);
        _speedHoldActive = false;
    }

    if (_currentSpeed > 0 || _speedHoldActive) {
        if (!_speedHoldActive) startSpeedStep(false);
        _targetSpeed = 0;
        _cancelling = true;
        _state.active = true;
    } else {
        _endedAtKnownZero = _speedKnown;
        _cancelling = false;
        resetMotion();
    }
}

void WaypointNavController::applySettings(const SpotLockSettings& s) {
    _settings = s;
    clampActuationSettings();
    Serial.printf("[Nav] Settings applied – arrival=%.1fm\n", _settings.deadZoneRadius);
}

bool WaypointNavController::update(const GpsData& gps, float heading) {
    uint32_t now = millis();

    if (_cancelling) {
        processSpeedStep(now);
        _state.active = true;
        _state.speedLevel = (uint8_t)max(0, (int)_currentSpeed);
        if (_currentSpeed == 0 && !_speedHoldActive && _targetSpeed == 0) {
            _endedAtKnownZero = true;
            _cancelling = false;
            resetMotion();
        }
        return false;
    }

    if (!_state.active) return false;

    if (_zeroing) {
        processMotorZeroing(now);
        bool gpsLost = false;
        if (correctionIntervalElapsed(now)) {
            markCorrectionTime(now);
            if (!isGpsAcceptable(gps)) {
                if (incrementGpsFailure()) gpsLost = true;
            } else {
                resetGpsFailures();
            }
        }
        if (gpsLost) {
            Serial.println("[Nav] GPS insufficient – cancelling navigation");
            cancel();
            return false;
        }
        if (!_zeroing) {
            _targetSpeed = (int8_t)_navMaxSpeed;
        }
        _state.active = true;
        return false;
    }

    processSteeringHold(now);
    processSpeedStep(now);
    _state.speedLevel = (uint8_t)max(0, (int)_currentSpeed);

    return runCorrectionLogic(gps, heading, now);
}

bool WaypointNavController::runCorrectionLogic(const GpsData& gps, float heading, uint32_t now) {
    if (!correctionIntervalElapsed(now)) return false;
    markCorrectionTime(now);

    if (!isGpsAcceptable(gps)) {
        if (incrementGpsFailure()) {
            Serial.println("[Nav] GPS insufficient – cancelling navigation");
            cancel();
        }
        return false;
    }
    resetGpsFailures();

    if (_holdActive || _speedHoldActive || !steeringCooldownElapsed(now)) return false;

    float dist    = haversineDistance(gps.latitude, gps.longitude, _state.targetLat, _state.targetLon);
    float bearing = bearingTo(gps.latitude, gps.longitude, _state.targetLat, _state.targetLon);

    _state.distMetres = dist;
    _state.bearingDeg = bearing;
    _state.arriving = false;

    if (dist <= _settings.deadZoneRadius) {
        Serial.printf("[Nav] ARRIVED – dist=%.2fm\n", dist);
        setTargetSpeed(0);
        return true;
    }

    float relAngle = normalizeAngle180(bearing - heading);
    float absAngle = fabsf(relAngle);
    float absRot   = fabsf(_cumulativeRotation);

    bool startUntangle    = absRot > _settings.maxRotationBeforeUntangle;
    bool continueUntangle = _isUntangling && (absRot > 360.0f);

    if (startUntangle || continueUntangle) {
        if (!_isUntangling) {
            _isUntangling = true;
            Serial.printf("[Nav] TANGLE %.1fdeg – untangling\n", _cumulativeRotation);
        }
        SteerDir dir = (_cumulativeRotation > 0) ? SteerDir::Left : SteerDir::Right;
        startSteeringHold(dir, steeringDuration(90.0f));
    } else if (absAngle > _settings.headingTolerance) {
        clearUntangleState();

        SteerDir dir;
        float steerAngle;
        if (resolveSteeringDirection(relAngle, absAngle, dir, steerAngle)) {
            Serial.printf("[Nav] Alt turn dir chosen – rot=%.1fdeg\n", _cumulativeRotation);
        }
        startSteeringHold(dir, steeringDuration(steerAngle));
    } else {
        clearUntangleState();
    }

    setTargetSpeed((int8_t)_navMaxSpeed);

    Serial.printf("[Nav] dist=%.2fm bear=%.1f hdg=%.1f rel=%.1f spd=%d/%d\n",
                  dist, bearing, heading, relAngle, _currentSpeed, _targetSpeed);

    return false;
}

void WaypointNavController::resetMotion() {
    resetMotorState();
    _state = WaypointNavState();
}