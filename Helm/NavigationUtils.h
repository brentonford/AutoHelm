#ifndef NAVIGATION_UTILS_H
#define NAVIGATION_UTILS_H

#include <Arduino.h>
#include <math.h>
#include "DataModels.h"

class NavigationUtils {
public:
    static float calculateDistance(float lat1, float lon1, float lat2, float lon2);
    static float calculateBearing(float lat1, float lon1, float lat2, float lon2);
    static float normalizeAngle(float angle);
    static float calculateRelativeAngle(float bearing, float heading);
    
    static void playTone(int frequency, int duration);
    static void playNavigationEnabled();
    static void playWaypointSet();
    static void playGpsFixLost();
    static void playGpsFixed();
    static void playAppConnected();
    static void playAppDisconnected();
    static void playDestinationReached();
};

// Forward declarations for notification functions
void playNavigationEnabled();
void playWaypointSet();
void playGpsFixLost();
void playGpsFixed();
void playAppConnected();
void playAppDisconnected();
void playDestinationReached();

#endif