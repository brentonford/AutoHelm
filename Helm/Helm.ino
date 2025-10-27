#include <Wire.h>
#include "DataModels.h"
#include "GPSManager.h"
#include "NavigationManager.h"
#include "DisplayManager.h"
#include "CompassManager.h"
#include "GPSReceiver.h"
#include "NavigationUtils.h"
#include "RfController.h"

#define RF_CS_PIN 10
#define RF_RST_PIN 9

// Hardware managers
GPSManager gpsManager;
NavigationManager* navigationManager;
DisplayManager displayManager;
CompassManager compassManager;
GPSReceiver gpsReceiver;
RfController rfController(RF_CS_PIN, RF_RST_PIN);

// System state
bool previousGpsFix = false;
unsigned long lastStatusUpdate = 0;
unsigned long lastCalibrationDataSent = 0;

// Hardware status flags
bool displayAvailable = false;
bool compassAvailable = false;
bool bleAvailable = false;
bool rfControllerAvailable = false;

// Forward declarations for notification functions
void playNavigationEnabled();
void playWaypointSet();
void playGpsFixLost();
void playGpsFixed();
void playDestinationReached();

void setup() {
    Serial.begin(9600);
    delay(2000);
    
    Serial.println("SERIAL COMMUNICATION TEST - IF YOU SEE THIS, SERIAL IS WORKING");
    Serial.flush();
    delay(500);
    
    Serial.println("=== Helm System Starting ===");
    Serial.flush();
    Serial.println("Initializing components...");
    Serial.flush();
    
    // Initialize display (non-blocking)
    Serial.print("Initializing OLED display... ");
    Serial.flush();
    displayAvailable = displayManager.begin();
    if (!displayAvailable) {
        Serial.print("FAILED - continuing without display");
    }
    Serial.flush();
    
    // Initialize GPS (always works)
    Serial.print("Initializing GPS... ");
    Serial.flush();
    gpsManager.begin();
    Serial.flush();
    
    // Initialize compass (non-blocking)
    Serial.print("Initializing compass... ");
    Serial.flush();
    compassAvailable = compassManager.begin();
    if (!compassAvailable) {
        Serial.println("FAILED - continuing without compass");
    }
    Serial.flush();
    
    // Initialize navigation manager
    Serial.print("Initializing navigation... ");
    Serial.flush();
    navigationManager = new NavigationManager(&rfController);
    Serial.println("SUCCESS");
    Serial.flush();
    
    // Initialize BLE GPS Receiver (non-blocking)
    Serial.print("Initializing BLE GPS Receiver... ");
    Serial.flush();
    bleAvailable = gpsReceiver.begin("Helm");
    if (bleAvailable) {
        Serial.println("SUCCESS");
    } else {
        Serial.println("FAILED - continuing without BLE");
    }
    Serial.flush();
    
    // Initialize buzzer pin
    Serial.print("Initializing buzzer... ");
    Serial.flush();
    pinMode(SystemConfig::BUZZER_PIN, OUTPUT);
    Serial.println("SUCCESS");
    Serial.flush();
    
    // Update display if available
    if (displayAvailable) {
        displayManager.updateDisplay(GPSData(), 0, NavigationState(), false);
    }

    rfControllerAvailable = rfController.begin();
    if (rfControllerAvailable) {
        Serial.println("RF Controller ready");
        rfController.printDebugInfo();
    } else {
        Serial.println("RF Controller FAILED");
    }
    
    Serial.println("=== Setup Complete ===");
    Serial.flush();
    Serial.println();
    Serial.println("Starting main loop...");
    Serial.flush();
}

void loop() {

    // Trigger RF Controller on serial command
    if (Serial.available()) {
        char cmd = Serial.read();
        
        if (cmd == 'r') {
            rfController.transmitRightButton();
        } else if (cmd == 'l') {
            rfController.transmitLeftButton();
        } else if (cmd == 't') {
            rfController.transmitSimpleBurst();
        } else if (cmd == 'd') {
            rfController.printDebugInfo();
        }
    }

    // Update BLE receiver if available
    if (bleAvailable) {
        gpsReceiver.update();
        
        // Handle calibration mode
        if (gpsReceiver.isCalibrationMode()) {
            handleCalibrationMode();
            return;
        }
        
        // Check for new waypoints
        if (gpsReceiver.hasTarget()) {
            Serial.println("New waypoint received from BLE!");
            navigationManager->setTarget(gpsReceiver.getLatitude(), gpsReceiver.getLongitude());
            playWaypointSet();
            gpsReceiver.clearTarget();
        }
        
        // Update navigation enabled state
        navigationManager->setNavigationEnabled(gpsReceiver.isNavigationEnabled());
    }
    
    // Read compass heading if available
    float heading = 0.0;
    if (compassAvailable) {
        heading = compassManager.readHeading();
    } else {
        heading = 0.0; // Default heading when compass unavailable
    }
    
    // Update GPS
    gpsManager.update();
    GPSData gpsData = gpsManager.getCurrentData();
    
    // Handle GPS fix status changes
    if (gpsManager.hasFixStatusChanged()) {
        if (gpsData.hasFix) {
            Serial.println("GPS fix acquired!");
            playGpsFixed();
        } else {
            Serial.println("GPS fix lost!");
            playGpsFixLost();
        }
    }
    
    // Update navigation
    navigationManager->update(gpsData, heading);
    NavigationState navState = navigationManager->getState();
    
    // Handle navigation state changes
    static bool wasNavigating = false;
    if (navState.isNavigating && !wasNavigating) {
        Serial.println("Navigation started!");
        playNavigationEnabled();
    }
    wasNavigating = navState.isNavigating;
    
    static bool wasDestinationReached = false;
    if (navState.hasReachedDestination && !wasDestinationReached) {
        Serial.println("Destination reached!");
        playDestinationReached();
    }
    wasDestinationReached = navState.hasReachedDestination;
    
    // Update display if available
    if (displayAvailable) {
        displayManager.updateDisplay(gpsData, heading, navState, bleAvailable ? gpsReceiver.isConnected() : false);
    }
    
    // Print debug info
    gpsManager.printDebugInfo(heading);
    
    // Send status via BLE if available
    if (bleAvailable && millis() - lastStatusUpdate >= 500) {
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
    if (!compassAvailable) {
        Serial.println("Calibration requested but compass not available!");
        return;
    }
    
    float x, y, z, minX, minY, minZ, maxX, maxY, maxZ;
    compassManager.getCalibrationData(x, y, z, minX, minY, minZ, maxX, maxY, maxZ);
    
    // Send calibration data via BLE if available
    if (bleAvailable && millis() - lastCalibrationDataSent >= 500) {
        gpsReceiver.sendCalibrationData(x, y, z, minX, minY, minZ, maxX, maxY, maxZ);
        lastCalibrationDataSent = millis();
    }
    
    // Show calibration screen if display available
    if (displayAvailable) {
        displayManager.showCalibrationScreen(x, y, z);
    }
    
    delay(100);
}