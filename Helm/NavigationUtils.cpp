#include "NavigationUtils.h"

float NavigationUtils::calculateDistance(float lat1, float lon1, float lat2, float lon2) {
    lat1 = lat1 * M_PI / 180.0;
    lon1 = lon1 * M_PI / 180.0;
    lat2 = lat2 * M_PI / 180.0;
    lon2 = lon2 * M_PI / 180.0;
    
    float dlat = lat2 - lat1;
    float dlon = lon2 - lon1;
    float a = sin(dlat/2) * sin(dlat/2) + cos(lat1) * cos(lat2) * sin(dlon/2) * sin(dlon/2);
    float c = 2 * atan2(sqrt(a), sqrt(1-a));
    
    float r = 6371000;
    return c * r;
}

float NavigationUtils::calculateBearing(float lat1, float lon1, float lat2, float lon2) {
    lat1 = lat1 * M_PI / 180.0;
    lon1 = lon1 * M_PI / 180.0;
    lat2 = lat2 * M_PI / 180.0;
    lon2 = lon2 * M_PI / 180.0;
    
    float dlon = lon2 - lon1;
    float y = sin(dlon) * cos(lat2);
    float x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon);
    float initial_bearing = atan2(y, x);
    
    initial_bearing = initial_bearing * 180.0 / M_PI;
    return fmod((initial_bearing + 360.0), 360.0);
}

float NavigationUtils::normalizeAngle(float angle) {
    while (angle > 180.0) angle -= 360.0;
    while (angle < -180.0) angle += 360.0;
    return angle;
}

float NavigationUtils::calculateRelativeAngle(float bearing, float heading) {
    float relativeAngle = fmod((bearing - heading + 360.0), 360.0);
    return normalizeAngle(relativeAngle > 180.0 ? relativeAngle - 360.0 : relativeAngle);
}

void NavigationUtils::playTone(int frequency, int duration) {
    if (frequency > 0) {
        tone(SystemConfig::BUZZER_PIN, frequency, duration);
    }
    delay(duration);
}

void NavigationUtils::playNavigationEnabled() {
    playTone(150, 200);
    delay(50);
    playTone(200, 200);
    delay(50);
    playTone(250, 400);
    delay(100);
    playTone(392, 150);
    playTone(523, 300);
}

void NavigationUtils::playWaypointSet() {
    playTone(800, 100);
    delay(100);
    playTone(800, 100);
    delay(50);
    playTone(440, 150);
    playTone(523, 200);
    playTone(659, 250);
}

void NavigationUtils::playGpsFixLost() {
    playTone(523, 300);
    delay(100);
    playTone(440, 300);
    delay(100);
    playTone(349, 300);
    delay(100);
    playTone(150, 800);
    delay(200);
    playTone(150, 400);
}

void NavigationUtils::playGpsFixed() {
    for (int i = 0; i < 3; i++) {
        playTone(800, 80);
        delay(120);
    }
    delay(100);
    playTone(262, 150);
    playTone(330, 150);
    playTone(392, 150);
    playTone(523, 300);
}

void NavigationUtils::playAppConnected() {
    playTone(392, 120);
    playTone(523, 120);
    delay(80);
    playTone(659, 120);
    playTone(392, 120);
    delay(80);
    playTone(523, 200);
    playTone(659, 300);
}

void NavigationUtils::playAppDisconnected() {
    playTone(330, 200);
    delay(50);
    playTone(262, 200);
    delay(100);
    playTone(200, 400);
    delay(100);
    playTone(150, 600);
}

void NavigationUtils::playDestinationReached() {
    playTone(523, 150);
    playTone(587, 150);
    playTone(659, 150);
    delay(100);
    playTone(523, 150);
    playTone(587, 150);
    playTone(659, 150);
    delay(100);
    playTone(392, 200);
    playTone(523, 400);
}

// Forward declaration implementations
void playNavigationEnabled() {
    NavigationUtils::playNavigationEnabled();
}

void playWaypointSet() {
    NavigationUtils::playWaypointSet();
}

void playGpsFixLost() {
    NavigationUtils::playGpsFixLost();
}

void playGpsFixed() {
    NavigationUtils::playGpsFixed();
}

void playAppConnected() {
    NavigationUtils::playAppConnected();
}

void playAppDisconnected() {
    NavigationUtils::playAppDisconnected();
}

void playDestinationReached() {
    NavigationUtils::playDestinationReached();
}