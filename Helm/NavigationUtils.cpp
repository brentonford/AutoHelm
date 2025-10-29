#include "NavigationUtils.h"
#include <Arduino.h>

float NavigationUtils::calculateDistance(float lat1, float lon1, float lat2, float lon2) {
    // Convert coordinates to radians
    float lat1Rad = lat1 * DEG_TO_RAD;
    float lon1Rad = lon1 * DEG_TO_RAD;
    float lat2Rad = lat2 * DEG_TO_RAD;
    float lon2Rad = lon2 * DEG_TO_RAD;
    
    // Haversine formula
    float deltaLat = lat2Rad - lat1Rad;
    float deltaLon = lon2Rad - lon1Rad;
    
    float a = sin(deltaLat / 2.0f) * sin(deltaLat / 2.0f) +
              cos(lat1Rad) * cos(lat2Rad) *
              sin(deltaLon / 2.0f) * sin(deltaLon / 2.0f);
    
    float c = 2.0f * atan2(sqrt(a), sqrt(1.0f - a));
    
    return EARTH_RADIUS_METERS * c;
}

float NavigationUtils::calculateBearing(float lat1, float lon1, float lat2, float lon2) {
    // Convert coordinates to radians
    float lat1Rad = lat1 * DEG_TO_RAD;
    float lon1Rad = lon1 * DEG_TO_RAD;
    float lat2Rad = lat2 * DEG_TO_RAD;
    float lon2Rad = lon2 * DEG_TO_RAD;
    
    float deltaLon = lon2Rad - lon1Rad;
    
    // Calculate bearing using atan2 for correct quadrant handling
    float y = sin(deltaLon) * cos(lat2Rad);
    float x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(deltaLon);
    
    float bearing = atan2(y, x) * RAD_TO_DEG;
    
    return normalizeAngle(bearing);
}

float NavigationUtils::normalizeAngle(float angle) {
    // Normalize angle to 0-360 degrees
    while (angle < 0.0f) {
        angle += 360.0f;
    }
    while (angle >= 360.0f) {
        angle -= 360.0f;
    }
    return angle;
}

float NavigationUtils::calculateRelativeAngle(float currentHeading, float targetBearing) {
    float relativeAngle = targetBearing - currentHeading;
    
    // Normalize to -180 to +180 degrees
    if (relativeAngle > 180.0f) {
        relativeAngle -= 360.0f;
    } else if (relativeAngle < -180.0f) {
        relativeAngle += 360.0f;
    }
    
    return relativeAngle;
}