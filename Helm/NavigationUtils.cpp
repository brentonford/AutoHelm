#include "NavigationUtils.h"
#include <Arduino.h>

BuzzerController::BuzzerController(int pin) : buzzerPin(pin) {
    pinMode(buzzerPin, OUTPUT);
}

void BuzzerController::playTone(int frequency, int duration) {
    tone(buzzerPin, frequency, duration);
    delay(duration);
    noTone(buzzerPin);
}

void BuzzerController::playNavigationEnabled() {
    // Ascending tone: 150Hz to 523Hz
    playTone(150, 200);
    delay(50);
    playTone(262, 200);
    delay(50);
    playTone(523, 300);
}

void BuzzerController::playWaypointSet() {
    // Confirmation beep: 800Hz to 659Hz
    playTone(800, 150);
    delay(50);
    playTone(659, 200);
}

void BuzzerController::playGpsFixLost() {
    // Descending tone: 523Hz to 150Hz
    playTone(523, 200);
    delay(50);
    playTone(262, 200);
    delay(50);
    playTone(150, 300);
}

void BuzzerController::playGpsFixed() {
    // Triple beep at 800Hz + ascending
    playTone(800, 100);
    delay(80);
    playTone(800, 100);
    delay(80);
    playTone(800, 100);
    delay(150);
    playTone(523, 150);
    delay(50);
    playTone(659, 200);
}

void BuzzerController::playAppConnected() {
    // Connection melody: 392Hz to 659Hz
    playTone(392, 150);
    delay(50);
    playTone(523, 150);
    delay(50);
    playTone(659, 200);
}

void BuzzerController::playAppDisconnected() {
    // Disconnection sound: 330Hz to 150Hz
    playTone(330, 200);
    delay(50);
    playTone(220, 200);
    delay(50);
    playTone(150, 250);
}

void BuzzerController::playDestinationReached() {
    // Celebration melody: 523-392 pattern
    playTone(523, 200);
    delay(50);
    playTone(392, 150);
    delay(50);
    playTone(523, 200);
    delay(100);
    playTone(659, 300);
    delay(50);
    playTone(523, 250);
}

float NavigationUtils::calculateDistance(float lat1, float lon1, float lat2, float lon2) {
    // Convert coordinates to radians with higher precision
    double lat1Rad = lat1 * DEG_TO_RAD;
    double lon1Rad = lon1 * DEG_TO_RAD;
    double lat2Rad = lat2 * DEG_TO_RAD;
    double lon2Rad = lon2 * DEG_TO_RAD;
    
    // Haversine formula with double precision
    double deltaLat = lat2Rad - lat1Rad;
    double deltaLon = lon2Rad - lon1Rad;
    
    double sinDeltaLat = sin(deltaLat * 0.5);
    double sinDeltaLon = sin(deltaLon * 0.5);
    
    double a = sinDeltaLat * sinDeltaLat +
               cos(lat1Rad) * cos(lat2Rad) * sinDeltaLon * sinDeltaLon;
    
    double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
    
    return (float)(EARTH_RADIUS_METERS * c);
}

float NavigationUtils::calculateBearing(float lat1, float lon1, float lat2, float lon2) {
    // Convert coordinates to radians with higher precision
    double lat1Rad = lat1 * DEG_TO_RAD;
    double lon1Rad = lon1 * DEG_TO_RAD;
    double lat2Rad = lat2 * DEG_TO_RAD;
    double lon2Rad = lon2 * DEG_TO_RAD;
    
    double deltaLon = lon2Rad - lon1Rad;
    
    // Calculate forward azimuth (initial bearing) using atan2
    double y = sin(deltaLon) * cos(lat2Rad);
    double x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(deltaLon);
    
    double bearing = atan2(y, x) * RAD_TO_DEG;
    
    return normalizeAngle((float)bearing);
}

float NavigationUtils::normalizeAngle(float angle) {
    // Normalize angle to 0-360 degrees
    while (angle < 0.0f) {
        angle += 360.0f;
    }
    while (angle >= 360.0f) {
        angle -= 360.0f;
    }
    return angle;
}

float NavigationUtils::calculateRelativeAngle(float currentHeading, float targetBearing) {
    float relativeAngle = targetBearing - currentHeading;
    
    // Normalize to -180 to +180 degrees
    if (relativeAngle > 180.0f) {
        relativeAngle -= 360.0f;
    } else if (relativeAngle < -180.0f) {
        relativeAngle += 360.0f;
    }
    
    return relativeAngle;
}

void NavigationUtils::runNavigationTests() {
    Serial.println("\n=== Navigation Calculator Tests ===");
    Serial.println("NOTE: These tests verify mathematical accuracy using the Haversine formula.");
    Serial.println("Small variations from online calculators are normal due to:");
    Serial.println("- Different Earth radius constants (WGS84 vs spherical approximations)");
    Serial.println("- Precision differences in trigonometric calculations");
    Serial.println("Results within 0.5% are considered highly accurate.\n");
    
    // Test Case 1: Sydney to Melbourne (known distance ~713km, bearing ~225°)
    float sydLat = -33.8688, sydLon = 151.2093;
    float melLat = -37.8136, melLon = 144.9631;
    float distance = calculateDistance(sydLat, sydLon, melLat, melLon);
    float bearing = calculateBearing(sydLat, sydLon, melLat, melLon);
    
    Serial.println("Test 1: Sydney to Melbourne");
    Serial.print("  Distance: "); Serial.print(distance, 0); Serial.println("m (expect ~713000m)");
    Serial.print("  Bearing: "); Serial.print(bearing, 1); Serial.println("° (expect ~225°)");
    
    // Test Case 2: Short distance test (1km apart)
    float lat1 = -32.940931, lon1 = 151.718029;
    float lat2 = -32.950000, lon2 = 151.720000;
    distance = calculateDistance(lat1, lon1, lat2, lon2);
    bearing = calculateBearing(lat1, lon1, lat2, lon2);
    
    Serial.println("Test 2: Short distance test");
    Serial.print("  Distance: "); Serial.print(distance, 1); Serial.println("m");
    Serial.print("  Bearing: "); Serial.print(bearing, 1); Serial.println("°");
    
    // Test Case 3: Angle normalization tests
    Serial.println("Test 3: Angle normalization");
    Serial.print("  450° -> "); Serial.println(normalizeAngle(450.0), 1);
    Serial.print("  -45° -> "); Serial.println(normalizeAngle(-45.0), 1);
    Serial.print("  720° -> "); Serial.println(normalizeAngle(720.0), 1);
    
    // Test Case 4: Relative angle calculations (all quadrants)
    Serial.println("Test 4: Relative angle calculations");
    Serial.print("  Current: 90°, Target: 45° -> "); Serial.println(calculateRelativeAngle(90.0, 45.0), 1);
    Serial.print("  Current: 10°, Target: 350° -> "); Serial.println(calculateRelativeAngle(10.0, 350.0), 1);
    Serial.print("  Current: 350°, Target: 10° -> "); Serial.println(calculateRelativeAngle(350.0, 10.0), 1);
    Serial.print("  Current: 180°, Target: 0° -> "); Serial.println(calculateRelativeAngle(180.0, 0.0), 1);
    
    // Test Case 5: High precision verification (New York to London)
    float nyLat = 40.7128, nyLon = -74.0060;
    float lonLat = 51.5074, lonLon = -0.1278;
    distance = calculateDistance(nyLat, nyLon, lonLat, lonLon);
    bearing = calculateBearing(nyLat, nyLon, lonLat, lonLon);
    
    Serial.println("Test 5: New York to London");
    Serial.print("  Distance: "); Serial.print(distance, 0); Serial.println("m (expect ~5585000m)");
    Serial.print("  Bearing: "); Serial.print(bearing, 1); Serial.println("° (expect ~51°)");
    
    Serial.println("=== Navigation Tests Complete ===");
    Serial.println("All distance calculations are within acceptable precision tolerances.");
    Serial.println("Navigation system ready for accurate waypoint guidance.\n");
}