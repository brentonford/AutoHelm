#include "NavigationManager.h"

NavigationManager::NavigationManager()
    : _state(NavigationState::Idle)
    , _enabled(false)
    , _lastCorrectionTime(0) {
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
    Serial.println("[Nav] Target cleared");
}

void NavigationManager::setEnabled(bool enabled) {
    if (enabled && !_target.isSet) {
        Serial.println("[Nav] Cannot enable: no target set");
        return;
    }

    _enabled = enabled;
    
    if (_enabled) {
        _state = NavigationState::Navigating;
        _lastCorrectionTime = 0;
        Serial.println("[Nav] Navigation ENABLED");
    } else {
        _state = NavigationState::Idle;
        Serial.println("[Nav] Navigation DISABLED");
    }
}

void NavigationManager::update(const GpsData& gpsData, float heading) {
    if (!_enabled || !_target.isSet)
        return;

    if (!gpsData.hasFix) {
        _state = NavigationState::Idle;
        return;
    }

    calculateNavigation(gpsData, heading);

    if (checkArrival()) {
        _state = NavigationState::Arrived;
        _enabled = false;
        Serial.println("[Nav] ARRIVED at destination!");
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
    if (!_enabled || _state != NavigationState::Navigating)
        return false;

    float absAngle = fabs(_navData.relativeAngle);
    return absAngle > NavigationConfig::headingToleranceDeg;
}

HeadingCorrection NavigationManager::getRequiredCorrection() {
    if (!_enabled || _state != NavigationState::Navigating)
        return HeadingCorrection::None;

    if (!isCorrectionIntervalElapsed())
        return HeadingCorrection::None;

    float absAngle = fabs(_navData.relativeAngle);
    if (absAngle <= NavigationConfig::headingToleranceDeg)
        return HeadingCorrection::None;

    _lastCorrectionTime = millis();

    // Positive relative angle = target is to the right
    // Negative relative angle = target is to the left
    if (_navData.relativeAngle > 0) {
        Serial.printf("[Nav] Correction: RIGHT (relative angle: %+.1f°)\n", _navData.relativeAngle);
        return HeadingCorrection::Right;
    }

    Serial.printf("[Nav] Correction: LEFT (relative angle: %+.1f°)\n", _navData.relativeAngle);
    return HeadingCorrection::Left;
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