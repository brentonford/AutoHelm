#include "DataModels.h"
#include "DisplayManager.h"
#include "GPSManager.h"
#include "CompassManager.h"
#include "NavigationUtils.h"

DisplayManager displayManager;
GPSManager gpsManager(SystemConfig::GPS_RX_PIN, SystemConfig::GPS_TX_PIN);
CompassManager compassManager;
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
}

void loop() {
    GPSData gpsData;
    float heading = 0.0;
    
    if (gpsAvailable) {
        gpsManager.update();
        gpsData = gpsManager.getData();
    }
    
    if (compassAvailable) {
        heading = compassManager.readHeading();
        
        // Output compass heading to serial for testing
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