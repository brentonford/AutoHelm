#ifndef NAVIGATION_MANAGER_H
#define NAVIGATION_MANAGER_H

#include "DataModels.h"

enum class NavigationMode {
    IDLE,
    NAVIGATING,
    ARRIVED
};

struct NavigationState {
    NavigationMode mode;
    float targetLatitude;
    float targetLongitude;
    float distanceToTarget;
    float bearingToTarget;
    float relativeAngle;
};

class NavigationManager {
private:
    NavigationState state;
    bool navigationEnabled;
    unsigned long lastUpdateTime;
    
public:
    NavigationManager();
    void setTarget(float latitude, float longitude);
    void update(const GPSData& gpsData, float heading);
    void setNavigationEnabled(bool enabled);
    NavigationState getState() const;
    bool hasArrived() const;
    bool isNavigationEnabled() const;
    void clearTarget();
};

#endif