#pragma once

#include <Arduino.h>
#include "DataModels.h"
#include "NavigationUtils.h"

class NavigationManager {
public:
    NavigationManager();

    void setTarget(float latitude, float longitude);
    void clearTarget();
    void update(const GpsData& gpsData, float heading);
    void setEnabled(bool enabled);

    bool isEnabled() const;
    bool hasTarget() const;
    bool hasArrived() const;
    NavigationState getState() const;
    NavigationData getNavigationData() const;
    Waypoint getTarget() const;

private:
    Waypoint _target;
    NavigationState _state;
    NavigationData _navData;
    bool _enabled;

    void calculateNavigation(const GpsData& gpsData, float heading);
    bool checkArrival();
};