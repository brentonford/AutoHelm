#pragma once
#include <Arduino.h>
#include "DataModels.h"
#include "NavMath.h"
#include "Remote.h"

// -------------------------------------------------------
// Jog direction (matches iOS SpotLockController.JogDirection)
// -------------------------------------------------------
enum class SpotLockJogDir : uint8_t { Forward, Back, Left, Right };

// -------------------------------------------------------
// SpotLockState – published via BLE sensor status JSON
// -------------------------------------------------------
struct SpotLockState {
    bool    active          = false;
    float   lockLat         = 0.0f;
    float   lockLon         = 0.0f;
    float   distanceM       = 0.0f;
    float   bearingDeg      = 0.0f;
    uint8_t speedLevel      = 0;
    float   cableRotation   = 0.0f;
    bool    cableTangled    = false;
    bool    applyingThrust  = false;
};

// -------------------------------------------------------
// SpotLockController – device-side autonomous position hold
// -------------------------------------------------------
class SpotLockController {
public:
    explicit SpotLockController(Remote& remote);

    void engage(float lat, float lon);
    void disengage();
    void jog(SpotLockJogDir dir);
    void applySettings(const SpotLockSettings& s);

    // Call every main-loop iteration
    void update(const GpsData& gps, float compassHeading);

    const SpotLockState& getState() const { return _state; }
    bool isActive() const { return _active || _disengaging; }

private:
    Remote&          _remote;
    SpotLockSettings _settings;
    SpotLockState    _state;

    bool  _active      = false;
    bool  _disengaging = false;
    float _lockLat     = 0.0f;
    float _lockLon     = 0.0f;

    // --- Steering hold (non-blocking) ---
    enum class SteerDir : uint8_t { None, Left, Right };
    SteerDir _holdDir         = SteerDir::None;
    bool     _holdActive      = false;
    uint32_t _holdStart       = 0;
    uint16_t _holdDuration    = 0;
    uint32_t _holdRetransmit  = 0;
    uint32_t _holdReleaseTime = 0;

    // --- Speed control (non-blocking) ---
    int8_t   _currentSpeed       = 0;
    int8_t   _targetSpeed        = 0;
    bool     _speedHoldActive    = false;
    bool     _speedHoldUp        = true;
    uint32_t _speedHoldStart     = 0;
    uint32_t _speedHoldRetransmit= 0;
    uint32_t _lastSpeedStepTime  = 0;
    uint32_t _lastResyncMs       = 0;  // last time a zero-assert re-sync pulse was sent
    bool     _applyingThrust     = false;

    // --- Correction timing ---
    uint32_t _lastCorrectionTime = 0;

    // --- Cable tangle ---
    float _cumulativeRotation = 0.0f;
    bool  _isUntangling       = false;

    // --- GPS quality ---
    uint8_t _consecutiveGpsFail = 0;

    // --- Kalman filter for GPS distance noise reduction ---
    KalmanFilter1D _kalmanDist;

    void processSteeringHold(uint32_t now);
    void processSpeedStep(uint32_t now);
    void runCorrectionLogic(const GpsData& gps, float heading, uint32_t now);

    void startSteeringHold(SteerDir dir, uint16_t durationMs);
    void releaseSteeringHold();
    void startSpeedStep(bool goUp);

    void setTargetSpeed(int8_t target);
    void resetState();

    bool     isGpsAcceptable(const GpsData& gps) const;
    uint16_t steeringDuration(float absAngle) const;
    float    proportionalSpeed(float distBeyondDeadZone) const;

    // Math helpers — see NavMath.h
};
