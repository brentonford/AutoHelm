#include "DataModels.h"
#include "DisplayManager.h"
#include "GPSManager.h"
#include "CompassManager.h"
#include "NavigationManager.h"
#include "NavigationUtils.h"

DisplayManager displayManager;
GPSManager gpsManager(SystemConfig::GPS_RX_PIN, SystemConfig::GPS_TX_PIN);
CompassManager compassManager;
NavigationManager navigationManager;
bool displayAvailable = false;
bool gpsAvailable = false;
bool compassAvailable = false;

void setup() {
    Serial.begin(115200);
    while (!Serial) {
        ; // Wait for serial port to connect
    }
    
    Serial.println("=== Helm System Starting ===");
    Serial.println("Initializing core systems...");
    
    Serial.print("Initializing OLED display... ");
    displayAvailable = displayManager.begin();
    if (displayAvailable) {
        Serial.println("SUCCESS");
        displayManager.showStartupScreen();
    } else {
        Serial.println("FAILED - continuing without display");
    }
    
    Serial.print("Initializing GPS... ");
    gpsAvailable = gpsManager.begin();
    if (gpsAvailable) {
        Serial.println("SUCCESS");
    } else {
        Serial.println("FAILED - continuing without GPS");
    }
    
    Serial.print("Initializing compass... ");
    compassAvailable = compassManager.begin();
    if (compassAvailable) {
        Serial.println("SUCCESS");
    } else {
        Serial.println("FAILED - continuing without compass");
    }
    
    Serial.print("System ready. Build version: ");
    Serial.println(SystemConfig::VERSION);
    
    // Run navigation calculator tests
    NavigationUtils::runNavigationTests();
    
    // Show test commands
    Serial.println("\n=== Test Commands ===");
    Serial.println("'w' - Set test waypoint (Sydney Opera House)");
    Serial.println("'n' - Toggle navigation enabled/disabled");
    Serial.println("'c' - Clear navigation target");
    Serial.println("'t' - Show current navigation state");
    Serial.println("======================\n");
}

void loop() {
    GPSData gpsData;
    float heading = 0.0;
    
    // Handle serial commands for testing
    handleSerialCommands();
    
    if (gpsAvailable) {
        gpsManager.update();
        gpsData = gpsManager.getData();
    }
    
    if (compassAvailable) {
        heading = compassManager.readHeading();
    }
    
    // Update navigation manager with current GPS and compass data
    navigationManager.update(gpsData, heading);
    
    // Get current navigation state
    NavigationState navState = navigationManager.getState();
    
    // Output navigation status to serial for testing
    if (navigationManager.isNavigationEnabled()) {
        Serial.print("NAV: Mode=");
        switch(navState.mode) {
            case NavigationMode::IDLE: Serial.print("IDLE"); break;
            case NavigationMode::NAVIGATING: Serial.print("NAVIGATING"); break;
            case NavigationMode::ARRIVED: Serial.print("ARRIVED"); break;
        }
        Serial.print(" | Dist=");
        Serial.print(navState.distanceToTarget, 1);
        Serial.print("m | Bearing=");
        Serial.print(navState.bearingToTarget, 1);
        Serial.print("° | RelAngle=");
        Serial.print(navState.relativeAngle, 1);
        Serial.println("°");
    }
    
    // Output compass heading for testing
    if (compassAvailable) {
        Serial.print("Heading: ");
        Serial.print(heading, 1);
        Serial.println(" degrees");
    }
    
    if (displayAvailable) {
        if (gpsAvailable && compassAvailable) {
            displayManager.updateGPSAndCompass(gpsData, heading);
        } else if (gpsAvailable) {
            displayManager.updateGPSDisplay(gpsData);
        } else if (compassAvailable) {
            displayManager.showCompassHeading(heading);
        }
    }
    
    delay(1000);
}

void handleSerialCommands() {
    if (Serial.available()) {
        char command = Serial.read();
        
        switch(command) {
            case 'w':
                // Set test waypoint - Sydney Opera House coordinates
                Serial.println("Setting test waypoint: Sydney Opera House (-33.8568, 151.2153)");
                navigationManager.setTarget(-33.8568, 151.2153);
                Serial.println("Test waypoint set. Use 'n' to enable navigation.");
                break;
                
            case 'n':
                // Toggle navigation enabled/disabled
                if (navigationManager.isNavigationEnabled()) {
                    navigationManager.setNavigationEnabled(false);
                    Serial.println("Navigation DISABLED");
                } else {
                    navigationManager.setNavigationEnabled(true);
                    Serial.println("Navigation ENABLED");
                }
                break;
                
            case 'c':
                // Clear navigation target
                navigationManager.clearTarget();
                navigationManager.setNavigationEnabled(false);
                Serial.println("Navigation target cleared");
                break;
                
            case 't':
                // Show current navigation state
                showNavigationTestResults();
                break;
        }
    }
}

void showNavigationTestResults() {
    Serial.println("\n=== Navigation Manager Test Results ===");
    
    NavigationState state = navigationManager.getState();
    
    Serial.print("Navigation Enabled: ");
    Serial.println(navigationManager.isNavigationEnabled() ? "YES" : "NO");
    
    Serial.print("Current Mode: ");
    switch(state.mode) {
        case NavigationMode::IDLE:
            Serial.println("IDLE");
            break;
        case NavigationMode::NAVIGATING:
            Serial.println("NAVIGATING");
            break;
        case NavigationMode::ARRIVED:
            Serial.println("ARRIVED");
            break;
    }
    
    if (state.targetLatitude != 0.0 || state.targetLongitude != 0.0) {
        Serial.print("Target: ");
        Serial.print(state.targetLatitude, 6);
        Serial.print(", ");
        Serial.println(state.targetLongitude, 6);
        
        Serial.print("Distance to target: ");
        Serial.print(state.distanceToTarget, 2);
        Serial.println(" meters");
        
        Serial.print("Bearing to target: ");
        Serial.print(state.bearingToTarget, 2);
        Serial.println(" degrees");
        
        Serial.print("Relative angle: ");
        Serial.print(state.relativeAngle, 2);
        Serial.println(" degrees");
        
        Serial.print("Has arrived: ");
        Serial.println(navigationManager.hasArrived() ? "YES" : "NO");
    } else {
        Serial.println("No target set");
    }
    
    // Show current GPS data for reference
    GPSData gpsData = gpsManager.getData();
    if (gpsData.hasFix) {
        Serial.print("Current position: ");
        Serial.print(gpsData.latitude, 6);
        Serial.print(", ");
        Serial.println(gpsData.longitude, 6);
    } else {
        Serial.println("Current position: No GPS fix");
    }
    
    Serial.println("========================================\n");
}