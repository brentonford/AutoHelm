#pragma once

#include <Arduino.h>
#include "DataModels.h"
#include "NavigationUtils.h"

class NavigationManager {
public:
    NavigationManager();

    // Target management
    void setTarget(float latitude, float longitude);
    void clearTarget();
    
    // Navigation control
    void update(const GpsData& gpsData, float heading);
    void setEnabled(bool enabled);
    bool isEnabled() const;
    bool hasTarget() const;
    bool hasArrived() const;
    NavigationState getState() const;
    NavigationData getNavigationData() const;
    Waypoint getTarget() const;
    
    // Correction
    HeadingCorrection getRequiredCorrection();
    bool needsCorrection() const;
    
    // Safety
    bool canEnableNavigation(const GpsData& gpsData) const;
    void checkSafetyConditions(const GpsData& gpsData);
    const char* getDisableReason() const;

    // Path navigation
    void setPath(Path* path);
    void startPath();
    void stopPath();
    uint8_t getCurrentWaypointIndex() const;
    Path* getActivePath() const;

    // Spot lock
    void engageSpotLock();
    void engageSpotLock(float lat, float lon);
    void disengageSpotLock();
    bool isSpotLockActive() const;
    void jogSpotLock(float heading, int8_t direction);
    float getSpotLockDistance() const;

    // Speed control
    void setTargetSpeed(float speedMs);
    void setTargetSpeedKmh(float speedKmh);
    void setSpeedLevel(uint8_t level);
    int8_t getSpeedAdjustment();
    SpeedState getSpeedState() const;

    // Motor response detection
    void recordMotorCommand(HeadingCorrection cmd);
    bool isMotorResponding() const;
    void updateMotorDetection(const GpsData& gpsData, float heading);

private:
    Waypoint _target;
    NavigationState _state;
    NavigationData _navData;
    bool _enabled;
    uint32_t _lastCorrectionTime;
    const char* _disableReason;

    void calculateNavigation(const GpsData& gpsData, float heading);
    bool checkArrival() const;
    bool isCorrectionIntervalElapsed() const;
    void disableWithReason(const char* reason);
    void resetMotorDetection();

    // Path navigation
    Path* _activePath;
    uint8_t _currentWaypointIndex;
    void advanceToNextWaypoint();
    void updatePathNavigation(const GpsData& gpsData, float heading);

    // Spot lock
    Waypoint _spotLockTarget;
    bool _spotLockActive;
    uint32_t _lastSpotLockCorrection;
    static constexpr float spotLockHoldRadius = 3.0f;
    static constexpr float spotLockCorrectionRadius = 5.0f;
    static constexpr float jogDistanceM = 1.5f;
    void updateSpotLock(const GpsData& gpsData, float heading);

    // Speed control
    SpeedState _speedState;
    uint32_t _lastSpeedChangeTime;
    static constexpr float speedTable[11] = {
        0.0f, 0.3f, 0.5f, 0.7f, 1.0f, 1.3f, 1.6f, 1.9f, 2.2f, 2.5f, 2.8f
    };

    // Motor response detection
    struct MotorSample {
        float lat;
        float lon;
        float heading;
        uint32_t timestamp;
    };
    static constexpr uint8_t sampleHistorySize = 10;
    MotorSample _sampleHistory[sampleHistorySize];
    uint8_t _sampleIndex;
    HeadingCorrection _lastMotorCommand;
    uint32_t _lastCommandTime;
    uint8_t _noResponseCount;
    bool _motorResponding;
};