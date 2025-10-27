#ifndef NAVIGATION_MANAGER_H
#define NAVIGATION_MANAGER_H

#include <Arduino.h>
#include "DataModels.h"
#include "NavigationUtils.h"
#include "RfController.h"

class NavigationManager {
private:
    NavigationState state;
    RfController* rfController;
    
public:
    NavigationManager(RfController* controller);
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