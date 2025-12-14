#pragma once

#include <Arduino.h>
#include <math.h>

namespace NavConstants {
    constexpr float earthRadiusM = 6371000.0f;
    constexpr float degToRad = PI / 180.0f;
    constexpr float radToDeg = 180.0f / PI;
}

class NavigationUtils {
public:
    static float calculateDistance(float lat1, float lon1, float lat2, float lon2);
    static float calculateBearing(float lat1, float lon1, float lat2, float lon2);
    static float normalizeAngle(float angle);
    static float normalizeHeading(float heading);
    static float calculateRelativeAngle(float currentHeading, float targetBearing);
};