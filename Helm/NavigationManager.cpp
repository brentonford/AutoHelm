#include "NavigationManager.h"
#include "NavigationUtils.h"
#include "DataModels.h"
#include <Arduino.h>

NavigationManager::NavigationManager() : navigationEnabled(false), lastUpdateTime(0), lastGpsFix(false) {
    state.mode = NavigationMode::IDLE;
    state.targetLatitude = 0.0;
    state.targetLongitude = 0.0;
    state.distanceToTarget = 0.0;
    state.bearingToTarget = 0.0;
    state.relativeAngle = 0.0;
}

void NavigationManager::setTarget(float latitude, float longitude) {
    state.targetLatitude = latitude;
    state.targetLongitude = longitude;
    
    // Only set to navigating if navigation is enabled
    if (navigationEnabled) {
        state.mode = NavigationMode::NAVIGATING;
    }
    
    Serial.print("Navigation target set: ");
    Serial.print(latitude, 6);
    Serial.print(", ");
    Serial.println(longitude, 6);
}

void NavigationManager::update(const GPSData& gpsData, float heading) {
    // Enhanced safety logic with DOP validation
    bool validGpsFix = gpsData.hasFix && isGpsAccuracyValid(gpsData);
    
    // Auto-disable on GPS fix loss
    if (lastGpsFix && !validGpsFix && navigationEnabled) {
        Serial.println("GPS fix lost or accuracy degraded - auto-disabling navigation for safety");
        setNavigationEnabled(false);
        return;
    }
    
    lastGpsFix = validGpsFix;
    
    // Only proceed with navigation calculations if enabled and we have valid GPS
    if (!navigationEnabled || state.mode == NavigationMode::IDLE || !validGpsFix) {
        return;
    }
    
    lastUpdateTime = millis();
    
    // Calculate distance and bearing to target
    state.distanceToTarget = NavigationUtils::calculateDistance(
        gpsData.latitude, gpsData.longitude,
        state.targetLatitude, state.targetLongitude
    );
    
    state.bearingToTarget = NavigationUtils::calculateBearing(
        gpsData.latitude, gpsData.longitude,
        state.targetLatitude, state.targetLongitude
    );
    
    // Calculate relative angle for navigation arrow
    state.relativeAngle = NavigationUtils::calculateRelativeAngle(heading, state.bearingToTarget);
    
    // Check if arrived at destination
    if (state.distanceToTarget <= SystemConfig::MIN_DISTANCE_METERS) {
        if (state.mode != NavigationMode::ARRIVED) {
            state.mode = NavigationMode::ARRIVED;
            Serial.println("Destination reached!");
        }
    } else {
        state.mode = NavigationMode::NAVIGATING;
    }
}

void NavigationManager::setNavigationEnabled(bool enabled) {
    bool previousState = navigationEnabled;
    navigationEnabled = enabled;
    
    if (!enabled) {
        state.mode = NavigationMode::IDLE;
        Serial.println("Navigation disabled");
    } else if (hasValidTarget()) {
        state.mode = NavigationMode::NAVIGATING;
        Serial.println("Navigation enabled");
    } else {
        Serial.println("Navigation enabled but no valid target set");
    }
    
    // Log state change for debugging
    if (previousState != enabled) {
        Serial.print("Navigation state changed: ");
        Serial.print(previousState ? "ENABLED" : "DISABLED");
        Serial.print(" -> ");
        Serial.println(enabled ? "ENABLED" : "DISABLED");
    }
}

bool NavigationManager::isGpsAccuracyValid(const GPSData& gpsData) const {
    // Enhanced DOP validation per requirements
    return gpsData.hasFix && 
           gpsData.satellites >= 4 && 
           (gpsData.hdop < 5.0 || gpsData.hdop == 99.9); // 99.9 is default/invalid, so allow it
}

bool NavigationManager::canNavigate(const GPSData& gpsData) const {
    return hasValidTarget() && 
           isGpsAccuracyValid(gpsData) &&
           navigationEnabled;
}

NavigationState NavigationManager::getState() const {
    return state;
}

bool NavigationManager::hasArrived() const {
    return state.mode == NavigationMode::ARRIVED;
}

bool NavigationManager::isNavigationEnabled() const {
    return navigationEnabled;
}

bool NavigationManager::hasValidTarget() const {
    return state.targetLatitude != 0.0 || state.targetLongitude != 0.0;
}

void NavigationManager::clearTarget() {
    state.mode = NavigationMode::IDLE;
    state.targetLatitude = 0.0;
    state.targetLongitude = 0.0;
    state.distanceToTarget = 0.0;
    state.bearingToTarget = 0.0;
    state.relativeAngle = 0.0;
    navigationEnabled = false; // Auto-disable when clearing target
    Serial.println("Navigation target cleared and navigation disabled");
}

String NavigationManager::getNavigationStatus() const {
    if (!navigationEnabled) {
        return "DISABLED";
    }
    
    switch (state.mode) {
        case NavigationMode::IDLE:
            return "IDLE";
        case NavigationMode::NAVIGATING:
            return "ACTIVE";
        case NavigationMode::ARRIVED:
            return "ARRIVED";
        default:
            return "UNKNOWN";
    }
}

bool NavigationManager::shouldCorrectHeading(const GPSData& gpsData, float currentHeading) const {
    if (!canNavigate(gpsData)) {
        return false;
    }
    
    // Check if relative angle is significant enough to warrant correction
    float absRelativeAngle = abs(state.relativeAngle);
    
    // Only correct if we're off by more than the tolerance and not too close to destination
    return absRelativeAngle > SystemConfig::HEADING_TOLERANCE && 
           state.distanceToTarget > SystemConfig::MIN_DISTANCE_METERS;
}

float NavigationManager::getHeadingCorrection() const {
    if (state.mode != NavigationMode::NAVIGATING) {
        return 0.0;
    }
    
    // Return the relative angle for heading correction
    // Positive = turn right, Negative = turn left
    return state.relativeAngle;
}