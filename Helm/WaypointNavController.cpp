#include "WaypointNavController.h"
#include "NavMath.h"
#include <math.h>

using namespace NavMath;

WaypointNavController::WaypointNavController(Remote& remote)
    : AutopilotMotorController(remote) {}

void WaypointNavController::start(float targetLat, float targetLon, uint8_t maxSpeedLevel) {
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

    Serial.println("[Nav] Zeroing motor speed (non-blocking)...");
    beginMotorZeroing();
}

void WaypointNavController::cancel() {
    if (!_state.active && !_cancelling) return;
    Serial.println("[Nav] CANCEL");

    if (_holdActive) releaseSteeringHold();

    _state.active   = false;
    _state.arriving = false;

    if (_currentSpeed > 0 || _speedHoldActive) {
        startSpeedStep(false);
        _targetSpeed = 0;
        _cancelling  = true;
    } else {
        _cancelling = false;
        resetMotion();
    }
}

void WaypointNavController::applySettings(const SpotLockSettings& s) {
    _settings = s;
    Serial.printf("[Nav] Settings applied – deadZone=%.1fm rampStart=%.1fm\n",
                  _settings.deadZoneRadius,
                  _settings.deadZoneRadius + NAV_RAMP_ZONE_M);
}

bool WaypointNavController::update(const GpsData& gps, float heading) {
    uint32_t now = millis();

    if (_cancelling) {
        processSpeedStep(now);
        if (_currentSpeed == 0 && !_speedHoldActive && _targetSpeed == 0) {
            _cancelling = false;
            resetMotion();
        }
        return false;
    }

    if (!_state.active) return false;

    if (_zeroing) {
        processMotorZeroing(now);
        return false;
    }

    processSteeringHold(now);
    processSpeedStep(now);
    processDeadReckoning(now);
    _state.speedLevel = (uint8_t)max(0, (int)_currentSpeed);

    return runCorrectionLogic(gps, heading, now);
}

bool WaypointNavController::runCorrectionLogic(const GpsData& gps, float heading, uint32_t now) {
    if (!isGpsAcceptable(gps)) {
        if (incrementGpsFailure()) {
            Serial.println("[Nav] GPS insufficient – cancelling navigation");
            cancel();
        }
        return false;
    }
    resetGpsFailures();

    if (!correctionIntervalElapsed(now) || _holdActive || !steeringCooldownElapsed(now)) return false;
    markCorrectionTime(now);

    float rawDist = haversineDistance(gps.latitude, gps.longitude, _state.targetLat, _state.targetLon);
    float dist    = updateFilteredDistance(rawDist, now);
    float bearing = bearingTo(gps.latitude, gps.longitude, _state.targetLat, _state.targetLon);

    _state.distMetres = dist;
    _state.bearingDeg = bearing;

    if (dist <= _settings.deadZoneRadius) {
        _state.arriving = false;
        Serial.printf("[Nav] ARRIVED – dist=%.2fm\n", dist);
        return true;
    }

    _state.arriving = (dist <= (_settings.deadZoneRadius + NAV_RAMP_ZONE_M));

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
            Serial.printf("[Nav] TANGLE %.1fdeg – untangling\n", _cumulativeRotation);
        }
        SteerDir dir = (_cumulativeRotation > 0) ? SteerDir::Left : SteerDir::Right;
        startSteeringHold(dir, steeringDuration(90.0f));
    } else if (absAngle > _settings.headingTolerance) {
        clearUntangleState();

        SteerDir dir;
        float steerAngle;
        if (resolveSteeringDirection(correctedRelAngle, absAngle, dir, steerAngle)) {
            Serial.printf("[Nav] Alt turn dir chosen – rot=%.1fdeg\n", _cumulativeRotation);
        }
        startSteeringHold(dir, steeringDuration(steerAngle));
    } else {
        clearUntangleState();
    }

    setTargetSpeed(targetSpeedForDist(dist));

    Serial.printf("[Nav] dist=%.2fm bear=%.1f hdg=%.1f rel=%.1f bias=%.1f spd=%d/%d arriving=%s\n",
                  dist, bearing, heading, relAngle, _bearingBias,
                  _currentSpeed, _targetSpeed,
                  _state.arriving ? "YES" : "NO");

    return false;
}

int8_t WaypointNavController::targetSpeedForDist(float dist) const {
    float rampStart = _settings.deadZoneRadius + NAV_RAMP_ZONE_M;
    if (dist >= rampStart) return (int8_t)_navMaxSpeed;

    float t = (dist - _settings.deadZoneRadius) / NAV_RAMP_ZONE_M;
    t = sqrtf(max(0.0f, t));
    float spd = _settings.minSpeed + t * ((float)_navMaxSpeed - _settings.minSpeed);
    return (int8_t)max((int)_settings.minSpeed, (int)roundf(spd));
}

void WaypointNavController::processDeadReckoning(uint32_t now) {
    if (!_state.active || _lastKalmanMs == 0) return;

    uint32_t msSinceKalman = now - _lastKalmanMs;
    if (msSinceKalman > 1200) return;

    float elapsed  = msSinceKalman / 1000.0f;
    float projDist = fmaxf(0.0f, _lastKalmanDist - speedLevelToMs[_currentSpeed] * elapsed);
    setTargetSpeed(targetSpeedForDist(projDist));
}

void WaypointNavController::resetMotion() {
    resetMotorState();
    _state = WaypointNavState();
}