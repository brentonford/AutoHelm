#pragma once

#include <Arduino.h>
#include "DataModels.h"
#include "GpsManager.h"
#include "BleManager.h"
#include "SpotLockController.h"
#include "WaypointNavController.h"

// Central coordinator for autonomous modes. Ensures only one motor controller
// drives RF at a time and sequences transitions (e.g. nav arrival -> Spot Lock).
class HelmModeManager {
public:
    HelmModeManager(GpsManager& gps, BleManager& ble,
                    SpotLockController& spotLock, WaypointNavController& waypointNav);

    void requestNavStart(float lat, float lon, uint8_t speed);
    void requestNavCancel();
    void requestSpotLockEngage(float lat, float lon);
    void requestSpotLockDisengage();
    bool requestSpotLockJog(SpotLockJogDir dir);

    void applyNavSettings(const SpotLockSettings& settings);
    void applySpotLockSettings(const SpotLockSettings& settings);

    // Call every main-loop iteration with fresh sensor data.
    void update(const GpsData& gps, float heading);

    void setCompassReady(bool ready) { _compassReady = ready; }

    bool allowsManualRf() const;
    bool isAutonomousActive() const;
    HelmState getHelmState() const;

private:
    enum class Mode : uint8_t {
        Idle,
        SpotLock,
        SpotLockDisengaging,
        Nav,
        NavCancelling,
        NavHandoff,
        Fault
    };

    bool _compassReady = false;

    GpsManager&             _gps;
    BleManager&             _ble;
    SpotLockController&     _spotLock;
    WaypointNavController&  _waypointNav;

    Mode   _mode = Mode::Idle;
    float  _handoffLat = 0.0f;
    float  _handoffLon = 0.0f;
    bool   _pendingNavStart = false;
    float  _pendingNavLat = 0.0f;
    float  _pendingNavLon = 0.0f;
    uint8_t _pendingNavSpeed = 5;
    bool   _pendingSpotLockEngage = false;
    float  _pendingSlLat = 0.0f;
    float  _pendingSlLon = 0.0f;

    bool validateNavPreconditions(float targetLat, float targetLon, const char*& errorCode) const;
    bool validateSpotLockPreconditions(float lockLat, float lockLon, const char*& errorCode) const;
    void sendAutonomyError(const char* errorCode);
    void clearFault();
    void enterFault(const char* reason);
    void beginNavHandoff(float lat, float lon);
    void tryStartPendingNav();
    void tryEngagePendingSpotLock();
    void finishNavHandoff();
    void handleControllerStopped(bool gpsAborted);
};