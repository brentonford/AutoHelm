#pragma once
#include <Arduino.h>
#include "DataModels.h"
#include "NavMath.h"
#include "Remote.h"

// -------------------------------------------------------
// WaypointNavState – published via BLE sensor status JSON
// -------------------------------------------------------
struct WaypointNavState {
    bool    active      = false;
    float   targetLat   = 0.0f;
    float   targetLon   = 0.0f;
    float   distMetres  = 0.0f;
    float   bearingDeg  = 0.0f;
    uint8_t speedLevel  = 0;
    bool    arriving    = false;    // true when inside the ramp-down zone
};

// -------------------------------------------------------
// WaypointNavController – autonomous navigation to a coordinate
//
// Control flow:
//   start()  → zeroes motor, activates algorithm
//   update() → call every loop; returns true when arrival detected
//              caller should then cancel() and engage SpotLock at target
//   cancel() → graceful motor ramp-down (mirrors SpotLock disengage logic)
// -------------------------------------------------------
class WaypointNavController {
public:
    explicit WaypointNavController(Remote& remote);

    void start(float targetLat, float targetLon, uint8_t maxSpeedLevel);
    void cancel();
    void applySettings(const SpotLockSettings& s);

    // Returns true on arrival (dist <= deadZoneRadius).
    // Caller must immediately call cancel() then spotLock.engage() at targetLat/Lon.
    bool update(const GpsData& gps, float compassHeading);

    const WaypointNavState& getState() const { return _state; }
    bool isActive() const { return _state.active || _cancelling; }

private:
    Remote&           _remote;
    SpotLockSettings  _settings;
    WaypointNavState  _state;

    uint8_t  _navMaxSpeed         = 5;
    bool     _cancelling          = false;  // graceful stop after cancel()

    // --- Steering hold (non-blocking, mirrors SpotLockController) ---
    enum class SteerDir : uint8_t { None, Left, Right };
    SteerDir _holdDir             = SteerDir::None;
    bool     _holdActive          = false;
    uint32_t _holdStart           = 0;
    uint16_t _holdDuration        = 0;
    uint32_t _holdRetransmit      = 0;
    uint32_t _holdReleaseTime     = 0;

    // --- Speed control (non-blocking) ---
    int8_t   _currentSpeed        = 0;
    int8_t   _targetSpeed         = 0;
    bool     _speedHoldActive     = false;
    bool     _speedHoldUp         = true;
    uint32_t _speedHoldStart      = 0;
    uint32_t _speedHoldRetransmit = 0;
    uint32_t _lastSpeedStepTime   = 0;
    uint32_t _lastResyncMs        = 0;  // last time a zero-assert re-sync pulse was sent

    // --- Correction timing ---
    uint32_t _lastCorrectionTime  = 0;

    // --- Cable tangle ---
    float    _cumulativeRotation  = 0.0f;
    bool     _isUntangling        = false;

    // --- GPS quality ---
    uint8_t  _consecutiveGpsFail  = 0;

    // --- Kalman filter for GPS distance noise reduction ---
    KalmanFilter1D _kalmanDist;

    // --- Dead reckoning & disturbance bias ---
    float    _lastKalmanDist  = 0.0f;
    uint32_t _lastKalmanMs    = 0;
    float    _bearingBias     = 0.0f;

    void processSteeringHold(uint32_t now);
    void processSpeedStep(uint32_t now);
    void processDeadReckoning(uint32_t now);

    // Returns true if arrival detected
    bool runCorrectionLogic(const GpsData& gps, float heading, uint32_t now);

    void startSteeringHold(SteerDir dir, uint16_t durationMs);
    void releaseSteeringHold();
    void startSpeedStep(bool goUp);
    void setTargetSpeed(int8_t target);
    void resetMotion();

    bool     isGpsAcceptable(const GpsData& gps) const;
    uint16_t steeringDuration(float absAngle) const;
    int8_t   targetSpeedForDist(float distMetres) const;

    // Math helpers — see NavMath.h
};
