#include "NavigationManager.h"

constexpr float NavigationManager::speedTable[11];

NavigationManager::NavigationManager()
    : _state(NavigationState::Idle)
    , _enabled(false)
    , _lastCorrectionTime(0)
    , _disableReason(nullptr)
    , _activePath(nullptr)
    , _currentWaypointIndex(0)
    , _spotLockActive(false)
    , _lastSpotLockCorrection(0)
    , _lastSpeedChangeTime(0)
    , _accelerationStartTime(0)
    , _isAccelerating(false)
    , _isDecelerating(false)
    , _sampleIndex(0)
    , _lastMotorCommand(HeadingCorrection::None)
    , _lastCommandTime(0)
    , _noResponseCount(0)
    , _motorResponding(true)
    , _lastSpeed(0.0f)
    , _lastSpeedDirection(0)
    , _lastSpeedCommandTime(0)
    , _speedNoResponseCount(0)
    , _lastSteeringCmd(MotorCommand::None)
    , _lastSpeedCmd(MotorCommand::None)
    , _lastCmdTimestamp(0) {
}

void NavigationManager::setTarget(float latitude, float longitude) {
    _target.set(latitude, longitude);
    Serial.printf("[Nav] Target set: %.6f, %.6f\n", latitude, longitude);
}

void NavigationManager::clearTarget() {
    _target.clear();
    _state = NavigationState::Idle;
    _enabled = false;
    _lastCorrectionTime = 0;
    _disableReason = nullptr;
    _isAccelerating = false;
    _isDecelerating = false;
    Serial.println("[Nav] Target cleared");
}

bool NavigationManager::canEnableNavigation(const GpsData& gpsData) const {
    if (!_target.isSet)
        return false;
    if (!gpsData.hasFix)
        return false;
    if (gpsData.satellites < NavigationConfig::minSatellites)
        return false;
    if (gpsData.hdop >= NavigationConfig::maxDop)
        return false;
    return true;
}

void NavigationManager::disableWithReason(const char* reason) {
    _enabled = false;
    _state = NavigationState::Idle;
    _disableReason = reason;
    _isAccelerating = false;
    _isDecelerating = false;
    Serial.printf("[Nav] DISABLED: %s\n", reason);
}

void NavigationManager::emergencyStop() {
    Serial.println("[Nav] EMERGENCY STOP - Initiating rapid deceleration");
    _enabled = false;
    _state = NavigationState::Idle;
    _disableReason = "Emergency stop";
    _speedState.targetLevel = 0;
    _isAccelerating = false;
    _isDecelerating = true;
    _lastSpeedChangeTime = 0;  // Force immediate speed change
}

void NavigationManager::checkSafetyConditions(const GpsData& gpsData) {
    if (!_enabled)
        return;

    if (!gpsData.hasFix) {
        disableWithReason("GPS fix lost");
        return;
    }

    if (gpsData.satellites < NavigationConfig::minSatellites) {
        disableWithReason("Insufficient satellites");
        return;
    }

    if (gpsData.hdop >= NavigationConfig::maxDop) {
        disableWithReason("GPS accuracy degraded (high DOP)");
        return;
    }
}

const char* NavigationManager::getDisableReason() const {
    return _disableReason;
}

void NavigationManager::setEnabled(bool enabled) {
    if (enabled && !_target.isSet) {
        Serial.println("[Nav] Cannot enable: no target set");
        _disableReason = "No target set";
        return;
    }

    _enabled = enabled;
    _disableReason = nullptr;

    if (_enabled) {
        _state = NavigationState::Navigating;
        _lastCorrectionTime = 0;
        _accelerationStartTime = millis();
        _isAccelerating = true;
        _isDecelerating = false;
        _lastSpeedChangeTime = millis();  // Start acceleration timer
        resetMotorDetection();
        Serial.println("[Nav] Navigation ENABLED - Beginning gradual acceleration");
    } else {
        _state = NavigationState::Idle;
        _isAccelerating = false;
        _isDecelerating = false;
        resetMotorDetection();
        Serial.println("[Nav] Navigation DISABLED");
    }
}

void NavigationManager::resetMotorDetection() {
    _noResponseCount = 0;
    _motorResponding = true;
    _lastMotorCommand = HeadingCorrection::None;
    _lastCommandTime = 0;
    _sampleIndex = 0;
    _speedNoResponseCount = 0;
    _lastSpeedDirection = 0;
    _lastSpeedCommandTime = 0;
}

void NavigationManager::update(const GpsData& gpsData, float heading) {
    if (!_enabled)
        return;

    updateMotorDetection(gpsData, heading);

    switch (_state) {
        case NavigationState::PathFollowing:
            updatePathNavigation(gpsData, heading);
            break;

        case NavigationState::SpotLock:
            updateSpotLock(gpsData, heading);
            break;

        case NavigationState::Navigating:
            if (!_target.isSet)
                return;
            if (!gpsData.hasFix) {
                disableWithReason("GPS fix lost");
                return;
            }
            calculateNavigation(gpsData, heading);
            if (checkArrival()) {
                _state = NavigationState::Arrived;
                _enabled = false;
                _speedState.targetLevel = 0;
                _isDecelerating = true;
                _disableReason = "Arrived at destination";
                Serial.println("[Nav] ARRIVED at destination!");
            }
            break;

        case NavigationState::Manual:
        case NavigationState::Idle:
        case NavigationState::Arrived:
            break;
    }
}

void NavigationManager::calculateNavigation(const GpsData& gpsData, float heading) {
    _navData.distanceToTarget = NavigationUtils::calculateDistance(
        gpsData.latitude, gpsData.longitude,
        _target.latitude, _target.longitude
    );

    _navData.bearingToTarget = NavigationUtils::calculateBearing(
        gpsData.latitude, gpsData.longitude,
        _target.latitude, _target.longitude
    );

    _navData.relativeAngle = NavigationUtils::calculateRelativeAngle(
        heading, _navData.bearingToTarget
    );
}

bool NavigationManager::checkArrival() const {
    return _navData.distanceToTarget <= NavigationConfig::arrivalThresholdM;
}

bool NavigationManager::isCorrectionIntervalElapsed() const {
    if (_lastCorrectionTime == 0)
        return true;
    return (millis() - _lastCorrectionTime) >= NavigationConfig::correctionIntervalMs;
}

bool NavigationManager::needsCorrection() const {
    if (!_enabled)
        return false;
    if (_state == NavigationState::Idle || _state == NavigationState::Manual)
        return false;

    float absAngle = fabsf(_navData.relativeAngle);
    return absAngle > NavigationConfig::headingToleranceDeg;
}

HeadingCorrection NavigationManager::getRequiredCorrection() {
    if (!_enabled)
        return HeadingCorrection::None;

    if (_state != NavigationState::Navigating &&
        _state != NavigationState::PathFollowing &&
        _state != NavigationState::SpotLock) {
        return HeadingCorrection::None;
    }

    if (!isCorrectionIntervalElapsed())
        return HeadingCorrection::None;

    float absAngle = fabsf(_navData.relativeAngle);
    if (absAngle <= NavigationConfig::headingToleranceDeg) {
        _lastSteeringCmd = MotorCommand::None;
        return HeadingCorrection::None;
    }

    _lastCorrectionTime = millis();
    _lastCmdTimestamp = millis();

    HeadingCorrection correction;
    if (_navData.relativeAngle > 0) {
        correction = HeadingCorrection::Right;
        _lastSteeringCmd = MotorCommand::Right;
        Serial.printf("[Nav] Correction: RIGHT (%+.1f deg)\n", _navData.relativeAngle);
    } else {
        correction = HeadingCorrection::Left;
        _lastSteeringCmd = MotorCommand::Left;
        Serial.printf("[Nav] Correction: LEFT (%+.1f deg)\n", _navData.relativeAngle);
    }

    recordMotorCommand(correction);
    return correction;
}

bool NavigationManager::isEnabled() const {
    return _enabled;
}

bool NavigationManager::hasTarget() const {
    return _target.isSet;
}

bool NavigationManager::hasArrived() const {
    return _state == NavigationState::Arrived;
}

NavigationState NavigationManager::getState() const {
    return _state;
}

NavigationData NavigationManager::getNavigationData() const {
    return _navData;
}

Waypoint NavigationManager::getTarget() const {
    return _target;
}

// Path Navigation

void NavigationManager::setPath(Path* path) {
    _activePath = path;
    _currentWaypointIndex = 0;

    if (path && path->waypointCount > 0) {
        Waypoint* first = path->getCurrentWaypoint(0);
        if (first) {
            _target = *first;
        }
    }
}

void NavigationManager::startPath() {
    if (!_activePath || _activePath->waypointCount == 0) {
        _disableReason = "No path set";
        return;
    }

    _currentWaypointIndex = 0;
    _state = NavigationState::PathFollowing;
    _enabled = true;
    _lastCorrectionTime = 0;
    _accelerationStartTime = millis();
    _isAccelerating = true;
    _lastSpeedChangeTime = millis();

    Waypoint* wp = _activePath->getCurrentWaypoint(0);
    if (wp) {
        _target = *wp;
    }

    Serial.printf("[Nav] Path started: %s (%d waypoints)\n",
        _activePath->name, _activePath->waypointCount);
}

void NavigationManager::stopPath() {
    _state = NavigationState::Idle;
    _enabled = false;
    _activePath = nullptr;
    _speedState.targetLevel = 0;
    _isDecelerating = true;
    Serial.println("[Nav] Path stopped");
}

void NavigationManager::advanceToNextWaypoint() {
    if (!_activePath)
        return;

    _currentWaypointIndex++;

    if (_currentWaypointIndex >= _activePath->waypointCount) {
        if (_activePath->loop) {
            _currentWaypointIndex = 0;
            Serial.println("[Nav] Path looping to start");
        } else {
            _state = NavigationState::Arrived;
            _enabled = false;
            _speedState.targetLevel = 0;
            _isDecelerating = true;
            Serial.println("[Nav] Path complete!");
            return;
        }
    }

    Waypoint* wp = _activePath->getCurrentWaypoint(_currentWaypointIndex);
    if (!wp)
        return;

    _target = *wp;
    Serial.printf("[Nav] Advancing to waypoint %d: %s\n",
        _currentWaypointIndex, wp->name);

    if (wp->spotLockEnabled) {
        engageSpotLock(wp->latitude, wp->longitude);
    }
}

void NavigationManager::updatePathNavigation(const GpsData& gpsData, float heading) {
    if (!_activePath || _state != NavigationState::PathFollowing)
        return;

    calculateNavigation(gpsData, heading);

    Waypoint* wp = _activePath->getCurrentWaypoint(_currentWaypointIndex);
    float arrivalRadius = wp ? wp->arrivalRadius : NavigationConfig::arrivalThresholdM;

    if (_navData.distanceToTarget <= arrivalRadius) {
        Serial.printf("[Nav] Arrived at waypoint %d\n", _currentWaypointIndex);
        advanceToNextWaypoint();
    }
}

uint8_t NavigationManager::getCurrentWaypointIndex() const {
    return _currentWaypointIndex;
}

Path* NavigationManager::getActivePath() const {
    return _activePath;
}

// Spot Lock

void NavigationManager::engageSpotLock() {
    if (_target.isSet) {
        engageSpotLock(_target.latitude, _target.longitude);
    }
}

void NavigationManager::engageSpotLock(float lat, float lon) {
    _spotLockTarget.set(lat, lon, "SpotLock");
    _spotLockActive = true;
    _state = NavigationState::SpotLock;
    _enabled = true;
    _lastSpotLockCorrection = 0;

    Serial.printf("[Nav] Spot Lock engaged: %.6f, %.6f\n", lat, lon);
}

void NavigationManager::disengageSpotLock() {
    _spotLockActive = false;
    _state = NavigationState::Idle;
    _enabled = false;
    _speedState.targetLevel = 0;
    _isDecelerating = true;
    Serial.println("[Nav] Spot Lock disengaged");
}

bool NavigationManager::isSpotLockActive() const {
    return _spotLockActive && _state == NavigationState::SpotLock;
}

void NavigationManager::jogSpotLock(float currentHeading, int8_t direction) {
    if (!_spotLockActive)
        return;

    float jogHeading = currentHeading;
    switch (direction) {
        case 2:  // Forward
            break;
        case 0:  // Back
            jogHeading += 180.0f;
            break;
        case -1: // Left
            jogHeading -= 90.0f;
            break;
        case 1:  // Right
            jogHeading += 90.0f;
            break;
    }

    jogHeading = NavigationUtils::normalizeHeading(jogHeading);

    float jogHeadingRad = jogHeading * DEG_TO_RAD;
    constexpr float metersPerDegLat = 111320.0f;
    
    _spotLockTarget.latitude += (jogDistanceM / metersPerDegLat) * cosf(jogHeadingRad);
    _spotLockTarget.longitude += (jogDistanceM / (metersPerDegLat *
        cosf(_spotLockTarget.latitude * DEG_TO_RAD))) * sinf(jogHeadingRad);

    Serial.printf("[Nav] Spot Lock jogged to: %.6f, %.6f\n",
        _spotLockTarget.latitude, _spotLockTarget.longitude);
}

float NavigationManager::getSpotLockDistance() const {
    return _navData.distanceToTarget;
}

void NavigationManager::updateSpotLock(const GpsData& gpsData, float heading) {
    if (!_spotLockActive)
        return;

    _navData.distanceToTarget = NavigationUtils::calculateDistance(
        gpsData.latitude, gpsData.longitude,
        _spotLockTarget.latitude, _spotLockTarget.longitude
    );

    _navData.bearingToTarget = NavigationUtils::calculateBearing(
        gpsData.latitude, gpsData.longitude,
        _spotLockTarget.latitude, _spotLockTarget.longitude
    );

    _navData.relativeAngle = NavigationUtils::calculateRelativeAngle(
        heading, _navData.bearingToTarget
    );

    if (_navData.distanceToTarget < spotLockHoldRadius)
        return;

    uint32_t now = millis();
    if (now - _lastSpotLockCorrection < NavigationConfig::correctionIntervalMs)
        return;

    _lastSpotLockCorrection = now;
}

// Speed Control - Gradual Acceleration

void NavigationManager::setTargetSpeed(float speedMs) {
    uint8_t bestLevel = 0;
    float bestDiff = fabsf(speedTable[0] - speedMs);

    for (uint8_t i = 1; i <= 10; i++) {
        float diff = fabsf(speedTable[i] - speedMs);
        if (diff < bestDiff) {
            bestDiff = diff;
            bestLevel = i;
        }
    }

    _speedState.targetLevel = bestLevel;
    
    if (bestLevel > _speedState.currentLevel) {
        _isAccelerating = true;
        _isDecelerating = false;
    } else if (bestLevel < _speedState.currentLevel) {
        _isAccelerating = false;
        _isDecelerating = true;
    }
    
    Serial.printf("[Nav] Target speed: %.1f m/s (level %d)\n", speedMs, bestLevel);
}

void NavigationManager::setTargetSpeedKmh(float speedKmh) {
    constexpr float kmhToMs = 3.6f;
    setTargetSpeed(speedKmh / kmhToMs);
}

void NavigationManager::setSpeedLevel(uint8_t level) {
    constexpr uint8_t maxLevel = 10;
    _speedState.targetLevel = min(level, maxLevel);
    
    if (_speedState.targetLevel > _speedState.currentLevel) {
        _isAccelerating = true;
        _isDecelerating = false;
    } else if (_speedState.targetLevel < _speedState.currentLevel) {
        _isAccelerating = false;
        _isDecelerating = true;
    }
}

int8_t NavigationManager::getSpeedAdjustment() {
    int8_t diff = static_cast<int8_t>(_speedState.targetLevel) - 
                  static_cast<int8_t>(_speedState.currentLevel);

    if (diff == 0) {
        _isAccelerating = false;
        _isDecelerating = false;
        return 0;
    }

    uint32_t now = millis();
    uint32_t requiredInterval;
    
    // Determine interval based on acceleration/deceleration state
    if (diff > 0) {
        // Accelerating - use slower intervals
        _isAccelerating = true;
        _isDecelerating = false;
        
        // Initial delay before first speed increase
        if (_speedState.currentLevel == 0) {
            uint32_t timeSinceStart = now - _accelerationStartTime;
            if (timeSinceStart < initialAccelDelayMs) {
                return 0;  // Wait before starting
            }
        }
        requiredInterval = accelIntervalMs;
    } else {
        // Decelerating
        _isAccelerating = false;
        _isDecelerating = true;
        
        // Use faster decel for emergency stop
        if (_disableReason != nullptr && strcmp(_disableReason, "Emergency stop") == 0) {
            requiredInterval = emergencyDecelMs;
        } else {
            requiredInterval = decelIntervalMs;
        }
    }

    if (now - _lastSpeedChangeTime < requiredInterval)
        return 0;

    _lastSpeedChangeTime = now;
    _lastCmdTimestamp = now;

    if (diff > 0) {
        _speedState.currentLevel++;
        _lastSpeedCmd = MotorCommand::SpeedUp;
        recordSpeedCommand(1);
        Serial.printf("[Nav] Speed UP: %d -> %d (target: %d)\n", 
            _speedState.currentLevel - 1, _speedState.currentLevel, _speedState.targetLevel);
        return 1;
    }

    _speedState.currentLevel--;
    _lastSpeedCmd = MotorCommand::SpeedDown;
    recordSpeedCommand(-1);
    Serial.printf("[Nav] Speed DOWN: %d -> %d (target: %d)\n", 
        _speedState.currentLevel + 1, _speedState.currentLevel, _speedState.targetLevel);
    return -1;
}

SpeedState NavigationManager::getSpeedState() const {
    return _speedState;
}

bool NavigationManager::isAccelerating() const {
    return _isAccelerating;
}

bool NavigationManager::isDecelerating() const {
    return _isDecelerating;
}

// Motor Response Detection

void NavigationManager::recordMotorCommand(HeadingCorrection cmd) {
    _lastMotorCommand = cmd;
    _lastCommandTime = millis();
}

void NavigationManager::recordSpeedCommand(int8_t direction) {
    _lastSpeedDirection = direction;
    _lastSpeedCommandTime = millis();
}

void NavigationManager::updateMotorDetection(const GpsData& gpsData, float heading) {
    // Calculate speed from GPS position changes
    float currentSpeed = 0.0f;
    if (_sampleIndex > 0) {
        uint8_t prevIdx = (_sampleIndex - 1 + sampleHistorySize) % sampleHistorySize;
        MotorSample& prev = _sampleHistory[prevIdx];
        
        if (prev.timestamp > 0) {
            float dist = NavigationUtils::calculateDistance(
                prev.lat, prev.lon, gpsData.latitude, gpsData.longitude);
            float timeDiff = (millis() - prev.timestamp) / 1000.0f;
            if (timeDiff > 0) {
                currentSpeed = dist / timeDiff;
            }
        }
    }
    
    _sampleHistory[_sampleIndex] = {
        gpsData.latitude, gpsData.longitude, heading, currentSpeed, millis()
    };
    _sampleIndex = (_sampleIndex + 1) % sampleHistorySize;

    // Check steering response
    constexpr uint32_t minResponseTimeMs = 500;
    uint32_t timeSinceCommand = millis() - _lastCommandTime;
    
    if (timeSinceCommand >= minResponseTimeMs && _lastMotorCommand != HeadingCorrection::None) {
        uint8_t oldestIdx = _sampleIndex;
        uint8_t newestIdx = (_sampleIndex - 1 + sampleHistorySize) % sampleHistorySize;

        MotorSample& oldest = _sampleHistory[oldestIdx];
        MotorSample& newest = _sampleHistory[newestIdx];

        if (newest.timestamp > oldest.timestamp && oldest.timestamp > 0) {
            float headingChange = newest.heading - oldest.heading;
            while (headingChange > 180.0f)
                headingChange -= 360.0f;
            while (headingChange < -180.0f)
                headingChange += 360.0f;

            constexpr float responseThreshold = 2.0f;
            bool responding = false;

            switch (_lastMotorCommand) {
                case HeadingCorrection::Left:
                    responding = (headingChange < -responseThreshold);
                    break;
                case HeadingCorrection::Right:
                    responding = (headingChange > responseThreshold);
                    break;
                case HeadingCorrection::None:
                    responding = true;
                    break;
            }

            constexpr uint32_t noResponseTimeoutMs = 2000;
            constexpr uint8_t maxNoResponseCount = 3;

            if (responding) {
                _noResponseCount = 0;
                _motorResponding = true;
            } else if (timeSinceCommand > noResponseTimeoutMs) {
                _noResponseCount++;
                if (_noResponseCount > maxNoResponseCount) {
                    _motorResponding = false;
                    Serial.println("[Nav] WARNING: Motor not responding to steering!");
                }
            }
        }
    }

    // Check speed response
    uint32_t timeSinceSpeedCmd = millis() - _lastSpeedCommandTime;
    if (timeSinceSpeedCmd >= 1000 && _lastSpeedDirection != 0) {
        // Compare speed over time
        if (_sampleIndex >= 2) {
            float speedChange = currentSpeed - _lastSpeed;
            bool speedResponding = false;
            
            if (_lastSpeedDirection > 0) {
                // Expected speed increase
                speedResponding = (speedChange > 0.05f);  // At least 0.05 m/s increase
            } else {
                // Expected speed decrease
                speedResponding = (speedChange < -0.05f);
            }
            
            if (speedResponding) {
                _speedNoResponseCount = 0;
            } else if (timeSinceSpeedCmd > 3000) {
                _speedNoResponseCount++;
                if (_speedNoResponseCount > 3) {
                    Serial.println("[Nav] WARNING: Motor not responding to speed changes!");
                }
            }
        }
    }
    
    _lastSpeed = currentSpeed;
}

bool NavigationManager::isMotorResponding() const {
    return _motorResponding;
}

// Command logging for app display

MotorCommand NavigationManager::getLastSteeringCommand() const {
    return _lastSteeringCmd;
}

MotorCommand NavigationManager::getLastSpeedCommand() const {
    return _lastSpeedCmd;
}

uint32_t NavigationManager::getLastCommandTime() const {
    return _lastCmdTimestamp;
}

bool NavigationManager::hasCommandPending() const {
    return (_lastSteeringCmd != MotorCommand::None) || (_lastSpeedCmd != MotorCommand::None);
}