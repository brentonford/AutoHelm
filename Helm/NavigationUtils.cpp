#include "NavigationUtils.h"

float NavigationUtils::calculateDistance(float lat1, float lon1, float lat2, float lon2) {
    float lat1Rad = lat1 * NavConstants::degToRad;
    float lat2Rad = lat2 * NavConstants::degToRad;
    float deltaLat = (lat2 - lat1) * NavConstants::degToRad;
    float deltaLon = (lon2 - lon1) * NavConstants::degToRad;

    float a = sin(deltaLat / 2.0f) * sin(deltaLat / 2.0f) +
              cos(lat1Rad) * cos(lat2Rad) *
              sin(deltaLon / 2.0f) * sin(deltaLon / 2.0f);

    float c = 2.0f * atan2(sqrt(a), sqrt(1.0f - a));

    return NavConstants::earthRadiusM * c;
}

float NavigationUtils::calculateBearing(float lat1, float lon1, float lat2, float lon2) {
    float lat1Rad = lat1 * NavConstants::degToRad;
    float lat2Rad = lat2 * NavConstants::degToRad;
    float deltaLon = (lon2 - lon1) * NavConstants::degToRad;

    float x = sin(deltaLon) * cos(lat2Rad);
    float y = cos(lat1Rad) * sin(lat2Rad) -
              sin(lat1Rad) * cos(lat2Rad) * cos(deltaLon);

    float bearing = atan2(x, y) * NavConstants::radToDeg;

    return normalizeHeading(bearing);
}

float NavigationUtils::normalizeAngle(float angle) {
    while (angle > 180.0f)
        angle -= 360.0f;
    while (angle < -180.0f)
        angle += 360.0f;
    return angle;
}

float NavigationUtils::normalizeHeading(float heading) {
    while (heading < 0.0f)
        heading += 360.0f;
    while (heading >= 360.0f)
        heading -= 360.0f;
    return heading;
}

float NavigationUtils::calculateRelativeAngle(float currentHeading, float targetBearing) {
    float diff = targetBearing - currentHeading;
    return normalizeAngle(diff);
}