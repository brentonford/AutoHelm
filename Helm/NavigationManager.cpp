#include "NavigationManager.h"

NavigationManager::NavigationManager(DeviceRFController* controller) : rfController(controller) {
}

void NavigationManager::setTarget(float latitude, float longitude) {
    state.targetLatitude = latitude;
    state.targetLongitude = longitude;
    state.hasReachedDestination = false;
    Serial.print("New target set: ");
    Serial.print(latitude, 6);
    Serial.print(", ");
    Serial.println(longitude, 6);
}

void NavigationManager::setNavigationEnabled(bool enabled) {
    state.navigationEnabled = enabled;
    if (!enabled) {
        state.isNavigating = false;
    }
}

void NavigationManager::update(const GPSData& gpsData, float heading) {
    if (!gpsData.hasFix || !state.navigationEnabled) {
        state.isNavigating = false;
        return;
    }
    
    state.currentDistance = NavigationUtils::calculateDistance(
        gpsData.latitude, gpsData.longitude, 
        state.targetLatitude, state.targetLongitude
    );
    
    state.currentBearing = NavigationUtils::calculateBearing(
        gpsData.latitude, gpsData.longitude, 
        state.targetLatitude, state.targetLongitude
    );
    
    if (state.currentDistance <= SystemConfig::MIN_DISTANCE_METERS) {
        if (!state.hasReachedDestination) {
            Serial.println("Destination reached!");
        }
        state.isNavigating = false;
        state.hasReachedDestination = true;
        return;
    }
    
    state.hasReachedDestination = false;
    state.isNavigating = true;
    
    float relativeAngle = NavigationUtils::calculateRelativeAngle(state.currentBearing, heading);
    
    if (shouldCorrectHeading(relativeAngle)) {
        adjustHeading(relativeAngle);
    }
}

NavigationState NavigationManager::getState() const {
    return state;
}

bool NavigationManager::hasReachedDestination() const {
    return state.hasReachedDestination;
}

void NavigationManager::adjustHeading(float relativeAngle) {
    unsigned long currentTime = millis();
    if (currentTime - state.lastCorrectionTime < SystemConfig::MIN_CORRECTION_INTERVAL) {
        return;
    }
    
    if (abs(relativeAngle) > SystemConfig::HEADING_TOLERANCE) {
        if (relativeAngle > 0) {
            Serial.print("Turning RIGHT (off by ");
            Serial.print(relativeAngle);
            Serial.println(" degrees)");
            rfController->transmitRight(5);
        } else {
            Serial.print("Turning LEFT (off by ");
            Serial.print(abs(relativeAngle));
            Serial.println(" degrees)");
            rfController->transmitLeft(5);
        }
        
        state.lastCorrectionTime = currentTime;
    } else {
        Serial.println("On course!");
    }
}

bool NavigationManager::shouldCorrectHeading(float relativeAngle) {
    return abs(relativeAngle) > SystemConfig::HEADING_TOLERANCE;
}