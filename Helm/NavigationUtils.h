#ifndef NAVIGATION_UTILS_H
#define NAVIGATION_UTILS_H

class NavigationUtils {
public:
    static float calculateDistance(float lat1, float lon1, float lat2, float lon2);
    static float calculateBearing(float lat1, float lon1, float lat2, float lon2);
    static float normalizeAngle(float angle);
    static float calculateRelativeAngle(float currentHeading, float targetBearing);
    
private:
    static constexpr float EARTH_RADIUS_METERS = 6371000.0f;
    static constexpr float DEG_TO_RAD = 0.017453292519943295f;
    static constexpr float RAD_TO_DEG = 57.29577951308232f;
};

#endif