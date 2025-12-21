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
    , _sampleIndex(0)
    , _lastMotorCommand(HeadingCorrection::None)
    , _lastCommandTime(0)
    , _noResponseCount(0)
    , _motorResponding(true) {
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
    Serial.printf("[Nav] DISABLED: %s\n", reason);
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
        
        // Reset motor response detection
        _noResponseCount = 0;
        _motorResponding = true;
        _lastMotorCommand = HeadingCorrection::None;
        _lastCommandTime = 0;
        _sampleIndex = 0;
        
        Serial.println("[Nav] Navigation ENABLED");
    } else {
        _state = NavigationState::Idle;
        
        // Reset motor response detection on disable
        _noResponseCount = 0;
        _motorResponding = true;
        _lastMotorCommand = HeadingCorrection::None;
        
        Serial.println("[Nav] Navigation DISABLED");
    }
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
                _disableReason = "Arrived at destination";
                Serial.println("[Nav] ARRIVED at destination!");
            }
            break;

        case NavigationState::Manual:
            break;

        default:
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

bool NavigationManager::checkArrival() {
    return _navData.distanceToTarget <= NavigationConfig::arrivalThresholdM;
}

bool NavigationManager::isCorrectionIntervalElapsed() const {
    if (_lastCorrectionTime == 0)
        return true;
    return (millis() - _lastCorrectionTime) >= NavigationConfig::correctionIntervalMs;
}

bool NavigationManager::needsCorrection() const {
    if (!_enabled || _state == NavigationState::Idle || _state == NavigationState::Manual)
        return false;

    float absAngle = fabs(_navData.relativeAngle);
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

    float absAngle = fabs(_navData.relativeAngle);
    if (absAngle <= NavigationConfig::headingToleranceDeg)
        return HeadingCorrection::None;

    _lastCorrectionTime = millis();

    HeadingCorrection correction;
    if (_navData.relativeAngle > 0) {
        correction = HeadingCorrection::Right;
        Serial.printf("[Nav] Correction: RIGHT (%+.1f°)\n", _navData.relativeAngle);
    } else {
        correction = HeadingCorrection::Left;
        Serial.printf("[Nav] Correction: LEFT (%+.1f°)\n", _navData.relativeAngle);
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
            Serial.println("[Nav] Path complete!");
            return;
        }
    }

    Waypoint* wp = _activePath->getCurrentWaypoint(_currentWaypointIndex);
    if (wp) {
        _target = *wp;
        Serial.printf("[Nav] Advancing to waypoint %d: %s\n",
            _currentWaypointIndex, wp->name);

        if (wp->spotLockEnabled) {
            engageSpotLock(wp->latitude, wp->longitude);
        }
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
        case 2:  break;
        case 0:  jogHeading += 180.0f; break;
        case -1: jogHeading -= 90.0f; break;
        case 1:  jogHeading += 90.0f; break;
    }

    jogHeading = NavigationUtils::normalizeHeading(jogHeading);

    float jogHeadingRad = jogHeading * DEG_TO_RAD;
    _spotLockTarget.latitude += (jogDistanceM / 111320.0f) * cos(jogHeadingRad);
    _spotLockTarget.longitude += (jogDistanceM / (111320.0f *
        cos(_spotLockTarget.latitude * DEG_TO_RAD))) * sin(jogHeadingRad);

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

    if (_navData.distanceToTarget < spotLockHoldRadius) {
        return;
    }

    uint32_t now = millis();
    if (now - _lastSpotLockCorrection < NavigationConfig::correctionIntervalMs) {
        return;
    }
    _lastSpotLockCorrection = now;
}

// Speed Control

void NavigationManager::setTargetSpeed(float speedMs) {
    uint8_t bestLevel = 0;
    float bestDiff = fabs(speedTable[0] - speedMs);

    for (uint8_t i = 1; i <= 10; i++) {
        float diff = fabs(speedTable[i] - speedMs);
        if (diff < bestDiff) {
            bestDiff = diff;
            bestLevel = i;
        }
    }

    _speedState.targetLevel = bestLevel;
    Serial.printf("[Nav] Target speed: %.1f m/s (level %d)\n", speedMs, bestLevel);
}

void NavigationManager::setTargetSpeedKmh(float speedKmh) {
    setTargetSpeed(speedKmh / 3.6f);
}

void NavigationManager::setSpeedLevel(uint8_t level) {
    _speedState.targetLevel = min(level, (uint8_t)10);
}

int8_t NavigationManager::getSpeedAdjustment() {
    int8_t diff = (int8_t)_speedState.targetLevel - (int8_t)_speedState.currentLevel;

    if (diff == 0)
        return 0;

    uint32_t now = millis();
    if (now - _lastSpeedChangeTime < 500)
        return 0;

    _lastSpeedChangeTime = now;

    if (diff > 0) {
        _speedState.currentLevel++;
        return 1;
    }

    _speedState.currentLevel--;
    return -1;
}

SpeedState NavigationManager::getSpeedState() const {
    return _speedState;
}

// Motor Response Detection

void NavigationManager::recordMotorCommand(HeadingCorrection cmd) {
    _lastMotorCommand = cmd;
    _lastCommandTime = millis();
}

void NavigationManager::updateMotorDetection(const GpsData& gpsData, float heading) {
    _sampleHistory[_sampleIndex] = {
        gpsData.latitude, gpsData.longitude, heading, millis()
    };
    _sampleIndex = (_sampleIndex + 1) % sampleHistorySize;

    uint32_t timeSinceCommand = millis() - _lastCommandTime;
    if (timeSinceCommand < 500 || _lastMotorCommand == HeadingCorrection::None) {
        return;
    }

    uint8_t oldestIdx = _sampleIndex;
    uint8_t newestIdx = (_sampleIndex - 1 + sampleHistorySize) % sampleHistorySize;

    MotorSample& oldest = _sampleHistory[oldestIdx];
    MotorSample& newest = _sampleHistory[newestIdx];

    if (newest.timestamp <= oldest.timestamp)
        return;

    float headingChange = newest.heading - oldest.heading;
    while (headingChange > 180)
        headingChange -= 360;
    while (headingChange < -180)
        headingChange += 360;

    bool responding = false;
    float threshold = 2.0f;

    switch (_lastMotorCommand) {
        case HeadingCorrection::Left:
            responding = (headingChange < -threshold);
            break;
        case HeadingCorrection::Right:
            responding = (headingChange > threshold);
            break;
        default:
            responding = true;
            break;
    }

    if (responding) {
        _noResponseCount = 0;
        _motorResponding = true;
    } else if (timeSinceCommand > 2000) {
        _noResponseCount++;
        if (_noResponseCount > 3) {
            _motorResponding = false;
            Serial.println("[Nav] WARNING: Motor not responding!");
        }
    }
}

bool NavigationManager::isMotorResponding() const {
    return _motorResponding;
}