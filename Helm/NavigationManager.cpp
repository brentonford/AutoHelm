#include "NavigationManager.h"
#include "NavigationUtils.h"
#include "DataModels.h"
#include <Arduino.h>

NavigationManager::NavigationManager() : navigationEnabled(false), lastUpdateTime(0) {
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
    state.mode = NavigationMode::NAVIGATING;
    
    Serial.print("Navigation target set: ");
    Serial.print(latitude, 6);
    Serial.print(", ");
    Serial.println(longitude, 6);
}

void NavigationManager::update(const GPSData& gpsData, float heading) {
    if (!navigationEnabled || state.mode == NavigationMode::IDLE) {
        return;
    }
    
    if (!gpsData.hasFix) {
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
    navigationEnabled = enabled;
    
    if (!enabled) {
        state.mode = NavigationMode::IDLE;
        Serial.println("Navigation disabled");
    } else if (state.targetLatitude != 0.0 || state.targetLongitude != 0.0) {
        state.mode = NavigationMode::NAVIGATING;
        Serial.println("Navigation enabled");
    }
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

void NavigationManager::clearTarget() {
    state.mode = NavigationMode::IDLE;
    state.targetLatitude = 0.0;
    state.targetLongitude = 0.0;
    state.distanceToTarget = 0.0;
    state.bearingToTarget = 0.0;
    state.relativeAngle = 0.0;
    Serial.println("Navigation target cleared");
}