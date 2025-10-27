#ifndef NAVIGATION_MANAGER_H
#define NAVIGATION_MANAGER_H

#include <Arduino.h>
#include "DataModels.h"
#include "NavigationUtils.h"
#include "DeviceRFController.h"

class NavigationManager {
private:
    NavigationState state;
    DeviceRFController* rfController;
    
public:
    NavigationManager(DeviceRFController* controller);
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