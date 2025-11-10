#include "DataModels.h"
#include "DisplayManager.h"
#include "GPSManager.h"
#include "CompassManager.h"
#include "NavigationManager.h"
#include "NavigationUtils.h"
#include "BluetoothController.h"

DisplayManager displayManager;
GPSManager gpsManager(SystemConfig::GPS_RX_PIN, SystemConfig::GPS_TX_PIN);
CompassManager compassManager;
NavigationManager navigationManager;
BuzzerController buzzer(SystemConfig::BUZZER_PIN);
BluetoothController bluetoothController;
bool displayAvailable = false;
bool gpsAvailable = false;
bool compassAvailable = false;
bool bluetoothAvailable = false;

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
    
    Serial.print("Initializing Bluetooth... ");
    bluetoothAvailable = bluetoothController.begin("Helm");
    if (bluetoothAvailable) {
        Serial.println("SUCCESS");
        // Set waypoint reception callback
        bluetoothController.setWaypointCallback(onWaypointReceived);
        // Set navigation control callback
        bluetoothController.setNavigationCallback(onNavigationControlReceived);
    } else {
        Serial.println("FAILED - continuing without Bluetooth");
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
    Serial.println("\n=== Audio Test Commands ===");
    Serial.println("'1' - Play navigation enabled sound");
    Serial.println("'2' - Play waypoint set sound");
    Serial.println("'3' - Play GPS fix lost sound");
    Serial.println("'4' - Play GPS fixed sound");
    Serial.println("'5' - Play app connected sound");
    Serial.println("'6' - Play app disconnected sound");
    Serial.println("'7' - Play destination reached sound");
    Serial.println("================================\n");
}

void loop() {
    GPSData gpsData;
    float heading = 0.0;
    
    // Handle serial commands for testing
    handleSerialCommands();
    
    // Update Bluetooth controller
    if (bluetoothAvailable) {
        bluetoothController.update();
    }
    
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
    
    // Send status data via Bluetooth
    if (bluetoothAvailable && bluetoothController.isConnected()) {
        sendBluetoothStatus(gpsData, heading, navState);
    }
    
    if (displayAvailable) {
        if (navigationManager.isNavigationEnabled() && navState.mode != NavigationMode::IDLE) {
            // Show navigation display when actively navigating
            displayManager.updateNavigationDisplay(navState, heading);
        } else if (gpsAvailable && compassAvailable) {
            displayManager.updateGPSAndCompass(gpsData, heading);
        } else if (gpsAvailable) {
            displayManager.updateGPSDisplay(gpsData);
        } else if (compassAvailable) {
            displayManager.showCompassHeading(heading);
        }
    }
    
    delay(200);  // 5Hz update rate for navigation arrow
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
                
            case '1':
                Serial.println("Playing navigation enabled sound...");
                buzzer.playNavigationEnabled();
                break;
                
            case '2':
                Serial.println("Playing waypoint set sound...");
                buzzer.playWaypointSet();
                break;
                
            case '3':
                Serial.println("Playing GPS fix lost sound...");
                buzzer.playGpsFixLost();
                break;
                
            case '4':
                Serial.println("Playing GPS fixed sound...");
                buzzer.playGpsFixed();
                break;
                
            case '5':
                Serial.println("Playing app connected sound...");
                buzzer.playAppConnected();
                break;
                
            case '6':
                Serial.println("Playing app disconnected sound...");
                buzzer.playAppDisconnected();
                break;
                
            case '7':
                Serial.println("Playing destination reached sound...");
                buzzer.playDestinationReached();
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

void onWaypointReceived(float latitude, float longitude) {
    Serial.print("Setting navigation target from BLE: ");
    Serial.print(latitude, 6);
    Serial.print(", ");
    Serial.println(longitude, 6);
    
    // Set target and enable navigation immediately
    navigationManager.setTarget(latitude, longitude);
    navigationManager.setNavigationEnabled(true);
    
    // Play waypoint set confirmation sound
    buzzer.playWaypointSet();
    
    Serial.println("Navigation enabled - heading to received waypoint");
}

void onNavigationControlReceived(bool enabled) {
    if (enabled) {
        Serial.println("Navigation enabled via BLE command");
        navigationManager.setNavigationEnabled(true);
        buzzer.playNavigationEnabled();
    } else {
        Serial.println("Navigation disabled via BLE command");
        navigationManager.setNavigationEnabled(false);
    }
}

void sendBluetoothStatus(const GPSData& gpsData, float heading, const NavigationState& navState) {
    // Use BluetoothController's JSON formatting for consistency
    String statusJson = bluetoothController.createStatusJSON(gpsData, navState, heading);
    
    // Send via BLE
    bluetoothController.sendStatus(statusJson.c_str());
    
    // Output JSON to Serial for testing when BLE connected
    if (bluetoothController.isConnected()) {
        static unsigned long lastJsonOutput = 0;
        unsigned long currentTime = millis();
        
        // Output at ~1Hz rate
        if (currentTime - lastJsonOutput >= 1000) {
            Serial.print("BLE JSON: ");
            Serial.println(statusJson);
            lastJsonOutput = currentTime;
        }
    }
}