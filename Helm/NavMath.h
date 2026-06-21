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

// Great-circle destination from start point, initial bearing, and distance.
inline void calcDestination(float latDeg, float lonDeg, float bearingDeg, float distM,
                            float& outLat, float& outLon) {
    float lat  = latDeg * (float)DEG_TO_RAD;
    float lon  = lonDeg * (float)DEG_TO_RAD;
    float brng = bearingDeg * (float)DEG_TO_RAD;
    float ang  = distM / EARTH_RADIUS_M;

    float lat2 = asinf(sinf(lat) * cosf(ang) + cosf(lat) * sinf(ang) * cosf(brng));
    float lon2 = lon + atan2f(sinf(brng) * sinf(ang) * cosf(lat),
                              cosf(ang) - sinf(lat) * sinf(lat2));

    outLat = lat2 * (float)RAD_TO_DEG;
    outLon = fmodf(lon2 * (float)RAD_TO_DEG + 540.0f, 360.0f) - 180.0f;
}

// Calibration table: estimated boat speed in m/s at each motor speed level 0–10.
// Tune by running at each level and measuring GPS ground speed.
constexpr float speedLevelToMs[11] = {
    0.0f,   // 0 – stopped
    0.30f,  // 1
    0.55f,  // 2
    0.80f,  // 3
    1.05f,  // 4
    1.35f,  // 5
    1.65f,  // 6
    1.95f,  // 7
    2.30f,  // 8
    2.65f,  // 9
    3.00f   // 10
};

} // namespace NavMath

// -------------------------------------------------------
// 1-D Kalman filter for GPS distance noise reduction.
// Defined outside the NavMath namespace so controllers can
// use it as a plain member type without `using namespace NavMath`.
// Large initial p collapses to the first measurement on the
// very first call to update() — no explicit init flag needed.
// -------------------------------------------------------
struct KalmanFilter1D {
    float x = 0.0f;
    float p = 9999.0f;  // large initial covariance → K≈1 on first measurement
    static constexpr float Q = 0.25f;  // process noise (distance changes ~0.5 m/step)
    static constexpr float R = 2.25f;  // measurement noise (GPS ±1.5 m typical)

    float update(float z) {
        p += Q;
        float k = p / (p + R);
        x += k * (z - x);
        p *= (1.0f - k);
        return x;
    }

    void reset() { x = 0.0f; p = 9999.0f; }
};
