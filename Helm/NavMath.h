#pragma once
#include <math.h>
#include <Arduino.h>  // DEG_TO_RAD, RAD_TO_DEG

// Shared navigation math used by SpotLockController and WaypointNavController.
// Keeping the implementations in one place ensures any precision fix is applied
// consistently across both controllers.

namespace NavMath {

static constexpr float EARTH_RADIUS_M = 6371000.0f;

inline float haversineDistance(float lat1Deg, float lon1Deg,
                                float lat2Deg, float lon2Deg) {
    float lat1 = lat1Deg * (float)DEG_TO_RAD;
    float lat2 = lat2Deg * (float)DEG_TO_RAD;
    float dLat = (lat2Deg - lat1Deg) * (float)DEG_TO_RAD;
    float dLon = (lon2Deg - lon1Deg) * (float)DEG_TO_RAD;
    float a = sinf(dLat * 0.5f) * sinf(dLat * 0.5f) +
              cosf(lat1) * cosf(lat2) * sinf(dLon * 0.5f) * sinf(dLon * 0.5f);
    return EARTH_RADIUS_M * 2.0f * atan2f(sqrtf(a), sqrtf(1.0f - a));
}

inline float bearingTo(float lat1Deg, float lon1Deg,
                        float lat2Deg, float lon2Deg) {
    float lat1 = lat1Deg * (float)DEG_TO_RAD;
    float lat2 = lat2Deg * (float)DEG_TO_RAD;
    float dLon = (lon2Deg - lon1Deg) * (float)DEG_TO_RAD;
    float y = sinf(dLon) * cosf(lat2);
    float x = cosf(lat1) * sinf(lat2) - sinf(lat1) * cosf(lat2) * cosf(dLon);
    return fmodf(atan2f(y, x) * (float)RAD_TO_DEG + 360.0f, 360.0f);
}

inline float normalizeAngle180(float angle) {
    while (angle >  180.0f) angle -= 360.0f;
    while (angle < -180.0f) angle += 360.0f;
    return angle;
}

// Flat-earth destination projection.
// Accurate to ~0.01% within a few hundred metres at latitudes below 60°;
// error grows at higher latitudes (the constant 111320 is calibrated at the equator).
inline void calcDestination(float lat, float lon, float headingDeg, float distM,
                             float& outLat, float& outLon) {
    float rad  = headingDeg * (float)DEG_TO_RAD;
    float mpdl = 111320.0f;  // metres per degree of latitude (equatorial approximation)
    outLat = lat + (distM / mpdl) * cosf(rad);
    outLon = lon + (distM / (mpdl * cosf(lat * (float)DEG_TO_RAD))) * sinf(rad);
}

} // namespace NavMath
