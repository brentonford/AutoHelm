#include "AutopilotMotorController.h"
#include <math.h>

namespace {
constexpr uint32_t HOLD_RETRANSMIT_MS      = 68;
constexpr uint32_t SPEED_HOLD_DURATION_MS  = 1000;
constexpr uint32_t STEERING_RELEASE_DELAY = 200;
constexpr float    SAFE_ROTATION_LEVEL     = 360.0f;
constexpr uint32_t RAMP_DOWN_DELAY_MS      = 500;
constexpr uint32_t RESYNC_INTERVAL_MS      = 5000;
constexpr uint8_t  MOTOR_ZERO_STEPS        = 10;
constexpr uint32_t MOTOR_ZERO_STEP_MS      = 100;
}  // namespace

AutopilotMotorController::AutopilotMotorController(Remote& remote)
    : _remote(remote) {}

void AutopilotMotorController::beginMotorZeroing() {
    _zeroing            = true;
    _zeroStepsRemaining = MOTOR_ZERO_STEPS;
    _lastZeroStepMs     = 0;
}

void AutopilotMotorController::processMotorZeroing(uint32_t now) {
    if (!_zeroing) return;

    if (_zeroStepsRemaining == 0) {
        _zeroing = false;
        Serial.printf("[%s] Motor zeroed\n", logTag());
        return;
    }

    if (_lastZeroStepMs == 0 || (now - _lastZeroStepMs) >= MOTOR_ZERO_STEP_MS) {
        _remote.transmitSingle(Button::Down);
        _zeroStepsRemaining--;
        _lastZeroStepMs = now;
    }
}

void AutopilotMotorController::processSteeringHold(uint32_t now) {
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

void AutopilotMotorController::startSteeringHold(SteerDir dir, uint16_t durationMs) {
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

void AutopilotMotorController::releaseSteeringHold() {
    if (!_holdActive) return;
    _remote.transmitSingle(Button::Release);
    _holdActive = false;
    _holdDir    = SteerDir::None;
}

void AutopilotMotorController::processSpeedStep(uint32_t now) {
    if (_holdActive && !allowSpeedStepDuringSteeringHold()) return;

    if (_speedHoldActive) {
        if ((now - _speedHoldStart) >= SPEED_HOLD_DURATION_MS) {
            _remote.transmitSingle(Button::Release);
            _speedHoldActive = false;
            if (_speedHoldUp) {
                _currentSpeed = min((int8_t)(_currentSpeed + 1), maxSpeedLevel());
            } else {
                _currentSpeed = max((int8_t)(_currentSpeed - 1), (int8_t)0);
            }
            onSpeedLevelChanged();
            _lastSpeedStepTime = now;
        } else if ((now - _speedHoldRetransmit) >= HOLD_RETRANSMIT_MS) {
            _remote.transmitSingle(_speedHoldUp ? Button::Up : Button::Down);
            _speedHoldRetransmit = now;
        }
        return;
    }

    if (_currentSpeed == 0 && _targetSpeed == 0 && !isRampingDown()) {
        if (_lastResyncMs == 0) {
            _lastResyncMs = now;
        } else if ((now - _lastResyncMs) >= RESYNC_INTERVAL_MS) {
            _remote.transmitSingle(Button::Down);
            _lastResyncMs = now;
        }
        return;
    }
    _lastResyncMs = 0;

    if (_currentSpeed == _targetSpeed) return;

    uint32_t stepDelay = (_targetSpeed > _currentSpeed)
        ? (uint32_t)_settings.speedChangeDelayMs
        : RAMP_DOWN_DELAY_MS;
    if ((now - _lastSpeedStepTime) < stepDelay) return;

    startSpeedStep(_targetSpeed > _currentSpeed);
}

void AutopilotMotorController::startSpeedStep(bool goUp) {
    _remote.transmitSingle(goUp ? Button::Up : Button::Down);
    _speedHoldActive     = true;
    _speedHoldUp         = goUp;
    _speedHoldStart      = millis();
    _speedHoldRetransmit = millis();
}

void AutopilotMotorController::setTargetSpeed(int8_t target) {
    int8_t clamped = max((int8_t)0, min(target, maxSpeedLevel()));
    if (clamped != 0 && clamped < (int8_t)_settings.minSpeed) {
        clamped = (int8_t)_settings.minSpeed;
    }
    _targetSpeed = clamped;
}

void AutopilotMotorController::resetMotorState() {
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
    _lastResyncMs        = 0;

    _lastCorrectionTime = 0;
    _cumulativeRotation   = 0.0f;
    _isUntangling         = false;

    _bearingBias    = 0.0f;
    _lastKalmanDist = 0.0f;
    _lastKalmanMs   = 0;
    _kalmanDist.reset();

    _zeroing            = false;
    _zeroStepsRemaining = 0;
    _lastZeroStepMs     = 0;

    resetGpsFailures();
}

bool AutopilotMotorController::isGpsAcceptable(const GpsData& gps) const {
    if (!gps.hasFix) return false;
    if (gps.satellites < _settings.minSatellites) return false;
    const bool hdopValid = (gps.hdop < 99.0f);
    if (hdopValid && gps.hdop >= _settings.maxHDOP) return false;
    uint32_t age = millis() - gps.timestamp;
    if (gps.timestamp > 0 && age > 2000) return false;
    return true;
}

bool AutopilotMotorController::incrementGpsFailure() {
    _consecutiveGpsFail++;
    Serial.printf("[%s] GPS quality fail %d/%d\n",
                  logTag(), _consecutiveGpsFail, _settings.maxConsecutiveGpsFail);
    if (_consecutiveGpsFail >= _settings.maxConsecutiveGpsFail) {
        _gpsAborted = true;
        return true;
    }
    return false;
}

void AutopilotMotorController::resetGpsFailures() {
    _consecutiveGpsFail = 0;
}

uint16_t AutopilotMotorController::steeringDuration(float absAngle) const {
    if (absAngle >= _settings.largeAngleThreshold) return _settings.largeSteeringDuration;
    if (absAngle >= _settings.smallAngleThreshold) return _settings.mediumSteeringDuration;
    return _settings.smallSteeringDuration;
}

float AutopilotMotorController::updateFilteredDistance(float rawDist, uint32_t now) {
    float dist = _kalmanDist.update(rawDist);
    _lastKalmanDist = dist;
    _lastKalmanMs   = now;
    return dist;
}

bool AutopilotMotorController::steeringCooldownElapsed(uint32_t now) const {
    return !(_holdReleaseTime > 0 && (now - _holdReleaseTime) < STEERING_RELEASE_DELAY);
}

bool AutopilotMotorController::correctionIntervalElapsed(uint32_t now) {
    return (now - _lastCorrectionTime) >= (uint32_t)_settings.correctionIntervalMs;
}

void AutopilotMotorController::markCorrectionTime(uint32_t now) {
    _lastCorrectionTime = now;
}

bool AutopilotMotorController::resolveSteeringDirection(float correctedRelAngle, float absAngle,
                                                          SteerDir& outDir, float& outAngle) const {
    float altAngle = 360.0f - absAngle;
    bool useAltDir = (fabsf(_cumulativeRotation) > 180.0f)
                  && (altAngle <= (float)_settings.largeAngleThreshold * 2.0f)
                  && (altAngle <= absAngle * 2.5f);

    outDir = useAltDir
        ? ((correctedRelAngle > 0) ? SteerDir::Left : SteerDir::Right)
        : ((correctedRelAngle > 0) ? SteerDir::Right : SteerDir::Left);
    outAngle = useAltDir ? altAngle : absAngle;
    return useAltDir;
}

void AutopilotMotorController::handleUntangleSteering(float absRot, uint32_t now) {
    (void)now;
    bool startUntangle    = absRot > _settings.maxRotationBeforeUntangle;
    bool continueUntangle = _isUntangling && (absRot > SAFE_ROTATION_LEVEL);

    if (startUntangle || continueUntangle) {
        if (!_isUntangling) {
            _isUntangling = true;
            Serial.printf("[%s] TANGLE %.1fdeg – untangling\n", logTag(), _cumulativeRotation);
        }
        SteerDir dir = (_cumulativeRotation > 0) ? SteerDir::Left : SteerDir::Right;
        startSteeringHold(dir, steeringDuration(90.0f));
    }
}

void AutopilotMotorController::clearUntangleState() {
    if (_isUntangling) {
        _isUntangling       = false;
        _cumulativeRotation = 0.0f;
        Serial.printf("[%s] UNTANGLED\n", logTag());
    }
}