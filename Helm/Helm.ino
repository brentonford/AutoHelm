#include <Wire.h>
#include "DataModels.h"
#include "GPSManager.h"
#include "NavigationManager.h"
#include "DisplayManager.h"
#include "CompassManager.h"
#include "WatersnakeRFController.h"
#include "GPSReceiver.h"
#include "NavigationUtils.h"

// Hardware managers
GPSManager gpsManager;
NavigationManager* navigationManager;
DisplayManager displayManager;
CompassManager compassManager;
WatersnakeRFController watersnakeRFController;
GPSReceiver gpsReceiver;

// System state
bool previousGpsFix = false;
unsigned long lastStatusUpdate = 0;
unsigned long lastCalibrationDataSent = 0;

// Forward declarations for notification functions
void playNavigationEnabled();
void playWaypointSet();
void playGpsFixLost();
void playGpsFixed();
void playDestinationReached();

void setup() {
    Serial.begin(9600);
    delay(100);
    Serial.println("GPS Navigation Starting...");
    
    if (!displayManager.begin()) {
        while(1) delay(10);
    }
    
    gpsManager.begin();
    
    if (!compassManager.begin()) {
        while(1) delay(10);
    }
    
    navigationManager = new NavigationManager(&watersnakeRFController);
    
    if (!gpsReceiver.begin("Helm")) {
        Serial.println("Failed to initialize BLE GPS Receiver!");
    } else {
        Serial.println("BLE GPS Receiver initialized successfully");
    }
    
    pinMode(SystemConfig::BUZZER_PIN, OUTPUT);
    
    displayManager.updateDisplay(GPSData(), 0, NavigationState(), false);
    
    Serial.println("Test Transmitter");
    Serial.println("sending RIGHT...");
    watersnakeRFController.transmitRight(3);
    delay(2000);
    
    Serial.println("sending LEFT...");
    watersnakeRFController.transmitLeft(3);
    delay(2000);
    
    Serial.println("Setup complete!");
}

void loop() {
    gpsReceiver.update();
    
    if (gpsReceiver.isCalibrationMode()) {
        handleCalibrationMode();
        return;
    }
    
    if (gpsReceiver.hasTarget()) {
        navigationManager->setTarget(gpsReceiver.getLatitude(), gpsReceiver.getLongitude());
        playWaypointSet();
        gpsReceiver.clearTarget();
    }
    
    float heading = compassManager.readHeading();
    
    gpsManager.update();
    GPSData gpsData = gpsManager.getCurrentData();
    
    if (gpsManager.hasFixStatusChanged()) {
        if (gpsData.hasFix) {
            playGpsFixed();
        } else {
            playGpsFixLost();
        }
    }
    
    navigationManager->setNavigationEnabled(gpsReceiver.isNavigationEnabled());
    navigationManager->update(gpsData, heading);
    NavigationState navState = navigationManager->getState();
    
    static bool wasNavigating = false;
    if (navState.isNavigating && !wasNavigating) {
        playNavigationEnabled();
    }
    wasNavigating = navState.isNavigating;
    
    static bool wasDestinationReached = false;
    if (navState.hasReachedDestination && !wasDestinationReached) {
        playDestinationReached();
    }
    wasDestinationReached = navState.hasReachedDestination;
    
    displayManager.updateDisplay(gpsData, heading, navState, gpsReceiver.isConnected());
    
    gpsManager.printDebugInfo(heading);
    
    if (millis() - lastStatusUpdate >= 500) {
        gpsReceiver.sendNavigationStatus(
            gpsData.hasFix, gpsData.satellites, gpsData.latitude, gpsData.longitude,
            gpsData.altitude, heading, navState.currentDistance, navState.currentBearing,
            navState.targetLatitude, navState.targetLongitude,
            navState.isNavigating, navState.hasReachedDestination
        );
        lastStatusUpdate = millis();
    }
    
    delay(100);
}

void handleCalibrationMode() {
    float x, y, z, minX, minY, minZ, maxX, maxY, maxZ;
    compassManager.getCalibrationData(x, y, z, minX, minY, minZ, maxX, maxY, maxZ);
    
    if (millis() - lastCalibrationDataSent >= 500) {
        gpsReceiver.sendCalibrationData(x, y, z, minX, minY, minZ, maxX, maxY, maxZ);
        lastCalibrationDataSent = millis();
    }
    
    displayManager.showCalibrationScreen(x, y, z);
    delay(100);
}