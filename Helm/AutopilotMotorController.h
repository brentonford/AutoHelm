#pragma once

#include <Arduino.h>
#include "DataModels.h"
#include "NavMath.h"
#include "Remote.h"

// Shared non-blocking motor control and GPS quality checks
// used by SpotLockController and WaypointNavController.
class AutopilotMotorController {
public:
    enum class SteerDir : uint8_t { None, Left, Right };

    bool takeKnownZero();

protected:
    explicit AutopilotMotorController(Remote& remote);

    Remote&          _remote;
    SpotLockSettings _settings;

    bool     _zeroing             = false;
    bool     _zeroPressActive     = false;
    uint8_t  _zeroStepsRemaining  = 0;
    uint32_t _lastZeroStepMs      = 0;
    uint32_t _zeroPressStart      = 0;
    uint32_t _zeroPressRetransmit = 0;
    bool     _speedKnown          = false;
    bool     _endedAtKnownZero    = false;

    SteerDir _holdDir             = SteerDir::None;
    bool     _holdActive          = false;
    uint32_t _holdStart           = 0;
    uint16_t _holdDuration        = 0;
    uint32_t _holdRetransmit      = 0;
    uint32_t _holdReleaseTime     = 0;

    int8_t   _currentSpeed        = 0;
    int8_t   _targetSpeed         = 0;
    bool     _speedHoldActive     = false;
    bool     _speedHoldUp         = true;
    uint32_t _speedHoldStart      = 0;
    uint32_t _speedHoldRetransmit = 0;
    uint32_t _lastSpeedStepTime   = 0;
    uint32_t _lastResyncMs        = 0;

    uint32_t _lastCorrectionTime  = 0;
    float    _cumulativeRotation  = 0.0f;
    bool     _isUntangling        = false;

    uint8_t  _consecutiveGpsFail  = 0;
    bool     _gpsAborted          = false;

    virtual int8_t maxSpeedLevel() const = 0;
    virtual bool isRampingDown() const = 0;
    virtual bool allowSpeedStepDuringSteeringHold() const = 0;
    virtual void onSpeedLevelChanged() = 0;
    virtual const char* logTag() const = 0;
    virtual bool enforceMinSpeed() const { return true; }

    void beginMotorZeroing();
    void processMotorZeroing(uint32_t now);
    void abortRadioPress();
    void clampActuationSettings();
    void processSteeringHold(uint32_t now);
    void processSpeedStep(uint32_t now);
    void startSteeringHold(SteerDir dir, uint16_t durationMs);
    void releaseSteeringHold();
    void startSpeedStep(bool goUp);
    void setTargetSpeed(int8_t target);
    void resetMotorState();

    bool isGpsAcceptable(const GpsData& gps) const;
    bool incrementGpsFailure();
    void resetGpsFailures();
    uint16_t steeringDuration(float absAngle) const;

    bool steeringCooldownElapsed(uint32_t now) const;
    bool correctionIntervalElapsed(uint32_t now);
    void markCorrectionTime(uint32_t now);

    bool resolveSteeringDirection(float correctedRelAngle, float absAngle,
                                  SteerDir& outDir, float& outAngle) const;
    void handleUntangleSteering(float absRot, uint32_t now);
    void clearUntangleState();

    int8_t currentSpeedLevel() const { return _currentSpeed; }
};