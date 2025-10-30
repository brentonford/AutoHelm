#ifndef NAVIGATION_UTILS_H
#define NAVIGATION_UTILS_H

class NavigationUtils {
public:
    static float calculateDistance(float lat1, float lon1, float lat2, float lon2);
    static float calculateBearing(float lat1, float lon1, float lat2, float lon2);
    static float normalizeAngle(float angle);
    static float calculateRelativeAngle(float currentHeading, float targetBearing);
    static void runNavigationTests();
    
private:
    static constexpr float EARTH_RADIUS_METERS = 6371008.8f;  // WGS84 mean radius
};

#endif