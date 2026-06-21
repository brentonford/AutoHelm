#pragma once
#include <Arduino.h>
#include "DataModels.h"
#include "AutopilotMotorController.h"

enum class SpotLockJogDir : uint8_t { Forward, Back, Left, Right };

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

class SpotLockController : public AutopilotMotorController {
public:
    explicit SpotLockController(Remote& remote);

    void engage(float lat, float lon);
    void disengage();
    bool jog(SpotLockJogDir dir);
    void applySettings(const SpotLockSettings& s);
    void update(const GpsData& gps, float compassHeading);

    const SpotLockState& getState() const { return _state; }
    const SpotLockSettings& getSettings() const { return _settings; }
    bool isActive() const { return _active || _disengaging || _zeroing; }
    bool isZeroing() const { return _zeroing; }
    bool wasGpsAborted() const { return _gpsAborted; }
    void clearGpsAborted() { _gpsAborted = false; }

protected:
    int8_t maxSpeedLevel() const override { return (int8_t)_settings.maxSpeed; }
    bool isRampingDown() const override { return _disengaging; }
    bool allowSpeedStepDuringSteeringHold() const override { return false; }
    void onSpeedLevelChanged() override { _state.speedLevel = (uint8_t)max(0, (int)_currentSpeed); }
    const char* logTag() const override { return "SpotLock"; }

private:
    SpotLockState _state;
    bool  _active      = false;
    bool  _disengaging = false;
    float _lockLat     = 0.0f;
    float _lockLon     = 0.0f;
    bool  _applyingThrust = false;
    uint32_t _lastJogMs   = 0;

    void runCorrectionLogic(const GpsData& gps, float heading, uint32_t now);
    void processDeadReckoning(uint32_t now);
    void resetState();
    float proportionalSpeed(float distBeyondDeadZone) const;
};