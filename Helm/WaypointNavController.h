#pragma once
#include <Arduino.h>
#include "DataModels.h"
#include "AutopilotMotorController.h"

struct WaypointNavState {
    bool    active      = false;
    float   targetLat   = 0.0f;
    float   targetLon   = 0.0f;
    float   distMetres  = 0.0f;
    float   bearingDeg  = 0.0f;
    uint8_t speedLevel  = 0;
    bool    arriving    = false;
};

class WaypointNavController : public AutopilotMotorController {
public:
    explicit WaypointNavController(Remote& remote);

    void start(float targetLat, float targetLon, uint8_t maxSpeedLevel, bool knownZero);
    void cancel();
    void applySettings(const SpotLockSettings& s);
    bool update(const GpsData& gps, float compassHeading);

    const WaypointNavState& getState() const { return _state; }
    const SpotLockSettings& getSettings() const { return _settings; }
    bool isActive() const { return _state.active || _cancelling || _zeroing; }
    bool isZeroing() const { return _zeroing; }
    bool isCancelling() const { return _cancelling; }
    bool wasGpsAborted() const { return _gpsAborted; }
    void clearGpsAborted() { _gpsAborted = false; }

protected:
    int8_t maxSpeedLevel() const override { return (int8_t)_navMaxSpeed; }
    bool isRampingDown() const override { return _cancelling; }
    bool enforceMinSpeed() const override { return false; }
    bool allowSpeedStepDuringSteeringHold() const override { return _cancelling; }
    void onSpeedLevelChanged() override { _state.speedLevel = (uint8_t)max(0, (int)_currentSpeed); }
    const char* logTag() const override { return "Nav"; }

private:
    WaypointNavState _state;
    uint8_t _navMaxSpeed = 5;
    bool    _cancelling  = false;

    bool runCorrectionLogic(const GpsData& gps, float heading, uint32_t now);
    void resetMotion();
};