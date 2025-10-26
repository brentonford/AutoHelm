#ifndef NAVIGATION_MANAGER_H
#define NAVIGATION_MANAGER_H

#include <Arduino.h>
#include "DataModels.h"
#include "NavigationUtils.h"
#include "WatersnakeRFController.h"

class NavigationManager {
private:
    NavigationState state;
    WatersnakeRFController* rfController;
    
public:
    NavigationManager(WatersnakeRFController* controller);
    void setTarget(float latitude, float longitude);
    void setNavigationEnabled(bool enabled);
    void update(const GPSData& gpsData, float heading);
    NavigationState getState() const;
    bool hasReachedDestination() const;
    
private:
    void adjustHeading(float relativeAngle);
    bool shouldCorrectHeading(float relativeAngle);
};

#endif