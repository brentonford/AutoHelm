#pragma once

#include <Arduino.h>
#include "DataModels.h"
#include "NavigationUtils.h"

enum class MotorCommand : uint8_t {
    None,
    Left,
    Right,
    SpeedUp,
    SpeedDown,
    MotorStop
};

struct CommandLog {
    MotorCommand command;
    uint32_t timestamp;
    bool executed;
};

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
    void emergencyStop();

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

    // Speed control - gradual acceleration
    void setTargetSpeed(float speedMs);
    void setTargetSpeedKmh(float speedKmh);
    void setSpeedLevel(uint8_t level);
    int8_t getSpeedAdjustment();
    SpeedState getSpeedState() const;
    bool isAccelerating() const;
    bool isDecelerating() const;

    // GPS speed tracking
    float getCurrentSpeedMs() const;
    float getCurrentSpeedKmh() const;

    // Motor response detection
    void recordMotorCommand(HeadingCorrection cmd);
    void recordSpeedCommand(int8_t direction);
    bool isMotorResponding() const;
    void updateMotorDetection(const GpsData& gpsData, float heading);

    // Command logging for app display
    MotorCommand getLastSteeringCommand() const;
    MotorCommand getLastSpeedCommand() const;
    uint32_t getLastCommandTime() const;
    bool hasCommandPending() const;

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

    // Speed control - gradual acceleration
    SpeedState _speedState;
    uint32_t _lastSpeedChangeTime;
    uint32_t _accelerationStartTime;
    bool _isAccelerating;
    bool _isDecelerating;
    
    // Gradual speed change intervals (ms between each speed step)
    static constexpr uint32_t initialAccelDelayMs = 2000;   // Wait before first speed increase
    static constexpr uint32_t accelIntervalMs = 1500;       // Time between speed steps when accelerating
    static constexpr uint32_t decelIntervalMs = 800;        // Time between speed steps when decelerating
    static constexpr uint32_t emergencyDecelMs = 200;       // Fast decel for emergency stop
    
    static constexpr float speedTable[11] = {
        0.0f, 0.3f, 0.5f, 0.7f, 1.0f, 1.3f, 1.6f, 1.9f, 2.2f, 2.5f, 2.8f
    };

    // GPS speed tracking
    uint32_t _lastSpeedCalcTime;
    double _lastSpeedCalcLat;
    double _lastSpeedCalcLon;
    float _currentSpeedMs;
    static constexpr uint32_t speedCalcIntervalMs = 1000;
    void updateGpsSpeed(const GpsData& gpsData);

    // Motor response detection
    struct MotorSample {
        float lat;
        float lon;
        float heading;
        float speed;
        uint32_t timestamp;
    };
    static constexpr uint8_t sampleHistorySize = 10;
    MotorSample _sampleHistory[sampleHistorySize];
    uint8_t _sampleIndex;
    HeadingCorrection _lastMotorCommand;
    uint32_t _lastCommandTime;
    uint8_t _noResponseCount;
    bool _motorResponding;
    float _lastSpeed;
    
    // Speed response detection
    int8_t _lastSpeedDirection;
    uint32_t _lastSpeedCommandTime;
    uint8_t _speedNoResponseCount;

    // Command logging
    MotorCommand _lastSteeringCmd;
    MotorCommand _lastSpeedCmd;
    uint32_t _lastCmdTimestamp;
};