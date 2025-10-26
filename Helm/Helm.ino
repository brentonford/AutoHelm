#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_MMC56x3.h>
#include <Wire.h>
#include <SoftwareSerial.h>
#include <math.h>
#include "WatersnakeRFController.h"
#include "GPSReceiver.h"


// OLED display configuration
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
#define SCREEN_ADDRESS 0x3C
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire1, OLED_RESET);

// GPS pins configuration
const int GPS_RX_PIN = 2;  // Arduino pin connected to GPS TX
const int GPS_TX_PIN = 3;  // Arduino pin connected to GPS RX

// Initialize the software serial port for GPS
SoftwareSerial gpsSerial(GPS_RX_PIN, GPS_TX_PIN);

// GPS data structure
struct GPSData {
    bool has_fix;
    int satellites;
    double latitude;
    double longitude;
    double altitude;
    String time;
};

// Simple GPS parser function
GPSData parseGPS() {
    GPSData data = {false, 0, 0.0, 0.0, 0.0, ""};
    // Placeholder GPS parsing - integrate with actual GPS module
    // For now, return default values
    return data;
}

// Initialize compass/magnetometer
Adafruit_MMC5603 compass = Adafruit_MMC5603(12345);

// Initialize RF controller
WatersnakeRFController watersnakeRFController;

// Initialize BLE GPS waypoint receiver
GPSReceiver gpsReceiver;

// Calibration values for magnetometer
float magXmax = 31.91;
float magYmax = 101.72;
float magZmax = 54.58;
float magXmin = -73.95;
float magYmin = -6.86;
float magZmin = -55.41;

// Calculated offsets (hard iron calibration)
float magXoffset = (magXmax + magXmin) / 2.0; // -27.015
float magYoffset = (magYmax + magYmin) / 2.0; // -3.675
float magZoffset = (magZmax + magZmin) / 2.0; // -34.255

// Calculate scaling factors (soft iron calibration)
float avgDelta;
float magXscale, magYscale, magZscale;

// Default destination coordinates (will be overridden by BLE waypoints)
float DESTINATION_LAT = -32.940931;
float DESTINATION_LON = 151.718029;

// Navigation parameters
const float HEADING_TOLERANCE = 15.0;
const float MIN_CORRECTION_INTERVAL = 2000;
const float MIN_DISTANCE_METERS = 5.0;

// Variables to store the latest GPS information
float latest_distance = 0;
float latest_bearing = 0;
unsigned long lastCorrectionTime = 0;
bool isNavigating = false;
bool hasReachedDestination = false;
bool previousGpsFix = false;

// Calibration variables
float calMagMinX, calMagMaxX;
float calMagMinY, calMagMaxY;
float calMagMinZ, calMagMaxZ;
unsigned long lastCalibrationDataSent = 0;

// Function declarations
float calculate_distance(float lat1, float lon1, float lat2, float lon2);
float calculate_bearing(float lat1, float lon1, float lat2, float lon2);
void draw_arrow(float angle, int center_x, int center_y, int size);
float read_heading();
void adjustHeading(float relativeAngle);
void updateDisplay(GPSData gpsData, float heading, float distance, float bearing);
void printDebugInfo(GPSData gpsData, float heading);
void handleCalibrationMode();
void playNavigationEnabled();
void playWaypointSet();
void playGpsFixLost();
void playGpsFixed();
void playAppConnected();
void playAppDisconnected();
void playDestinationReached();


void setup() {
    Serial.begin(9600);
    delay(100);
    Serial.println("GPS Navigation Starting...");
    
    // Initialize I2C and OLED display
    if(!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
        Serial.println(F("SSD1306 allocation failed"));
        for(;;);
    } else {
        Serial.println("OLED initialised!");
    }
    
    // Initialize GPS
    gpsSerial.begin(9600);
    Serial.println("GPS initialised!");
    
    // Initialize magnetometer
    if (!compass.begin(MMC56X3_DEFAULT_ADDRESS, &Wire1)) {
        Serial.println("Ooops, no MMC5603 detected ... Check your wiring!");
        while (1) delay(10);
    } else {
        Serial.println("Magnetometer initialised!");
    }

    // // Initialize RFM69HCW transmitter
    // if (!watersnakeRFController.begin()) {
    //     Serial.println(F("RFM69HCW initialization failed!"));
    //     while (1) {
    //         delay(1000);
    //     }
    // } else {
    //     Serial.println(F("RFM69HCW initialized successfully"));
    //     Serial.println(F("Frequency: 433.032 MHz"));
    // }

// Initialize BLE GPS receiver
    if (!gpsReceiver.begin("Helm")) {
        Serial.println("Failed to initialize BLE GPS Receiver!");
    } else {
        Serial.println("BLE GPS Receiver initialized successfully");
    }
    
    // Initialize buzzer pin for nautical notifications
    pinMode(8, OUTPUT);
    
    // Calculate scaling factors for magnetometer
    float xRange = magXmax - magXmin;
    float yRange = magYmax - magYmin;
    float zRange = magZmax - magZmin;
    
  // Calculate average range for scaling
    avgDelta = (xRange + yRange + zRange) / 3.0;
    
  // Set scales (with safety checks)
    magXscale = (xRange > 0.1) ? avgDelta / xRange : 1.0;
    magYscale = (yRange > 0.1) ? avgDelta / yRange : 1.0;
    magZscale = (zRange > 0.1) ? avgDelta / zRange : 1.0;
    
    // Clear the display
    display.clearDisplay();
    display.display();
    
    // Show startup message
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(1, 5);
    display.print("GPS Navigation System");
    display.setCursor(1, 30);
    display.print("Initialising...");
    display.setCursor(1, 45);
    display.print("Testing transmitter...");
    display.display();
    
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
    display.clearDisplay();
    
    // Update BLE GPS receiver
    gpsReceiver.update();
    
    // Handle calibration mode
    if (gpsReceiver.isCalibrationMode()) {
        handleCalibrationMode();
        return; // Skip normal navigation during calibration
    }
    
    // Check for new waypoint from mobile app
    if (gpsReceiver.hasTarget()) {
        DESTINATION_LAT = gpsReceiver.getLatitude();
        DESTINATION_LON = gpsReceiver.getLongitude();
        Serial.println("New waypoint received from mobile app!");
        Serial.print("Target: ");
        Serial.print(DESTINATION_LAT, 6);
        Serial.print(", ");
        Serial.println(DESTINATION_LON, 6);
        playWaypointSet();
        gpsReceiver.clearTarget();
    }
    
    // Get compass heading
    float heading = read_heading();
    
    // Get current GPS data
    GPSData gps_data = parseGPS();
    
    // Check for GPS fix status changes
    if (gps_data.has_fix != previousGpsFix) {
        if (gps_data.has_fix) {
            Serial.println("GPS fix acquired!");
            playGpsFixed();
        } else {
            Serial.println("GPS fix lost!");
            playGpsFixLost();
        }
        previousGpsFix = gps_data.has_fix;
    }
    
    // If we have valid GPS data, calculate distance and bearing
    if (gps_data.has_fix) {
        // Calculate distance to destination
        latest_distance = calculate_distance(gps_data.latitude, gps_data.longitude, DESTINATION_LAT, DESTINATION_LON);
        
        // Calculate bearing to destination
        latest_bearing = calculate_bearing(gps_data.latitude, gps_data.longitude, DESTINATION_LAT, DESTINATION_LON);
        
        // Check if we should navigate (only if navigation is enabled)
        if (gpsReceiver.isNavigationEnabled() && latest_distance > MIN_DISTANCE_METERS) {
            // Calculate the difference between bearing to destination and current heading
            float relative_angle = fmod((latest_bearing - heading + 360.0), 360.0);
            
            // Check if navigation was just enabled
            if (!isNavigating) {
                playNavigationEnabled();
            }
            
            // Adjust heading if needed
            adjustHeading(relative_angle);
            isNavigating = true;
            hasReachedDestination = false;
        } else if (latest_distance <= MIN_DISTANCE_METERS) {
            // Check if we just reached destination
            if (!hasReachedDestination) {
                Serial.println("Destination reached!");
                playDestinationReached();
            }
            isNavigating = false;
            hasReachedDestination = true;
        } else {
            // Navigation disabled
            isNavigating = false;
            hasReachedDestination = false;
        }
    }
    
    // Update the display
    updateDisplay(gps_data, heading, latest_distance, latest_bearing, gpsReceiver.isConnected(), isNavigating, hasReachedDestination);
    
    printDebugInfo(gps_data, heading);
    
    // Send navigation status to connected app every 500ms
    static unsigned long lastStatusUpdate = 0;
    if (millis() - lastStatusUpdate >= 500) {
        gpsReceiver.sendNavigationStatus(
            gps_data.has_fix,
            gps_data.satellites,
            gps_data.latitude,
            gps_data.longitude,
            gps_data.altitude,
            heading,
            latest_distance,
            latest_bearing,
            DESTINATION_LAT,
            DESTINATION_LON,
            isNavigating,
            hasReachedDestination
        );
        lastStatusUpdate = millis();
    }
    
    // Update at 10 Hz
    delay(100);
}

void handleCalibrationMode() {
    // Get magnetometer event for calibration
    sensors_event_t magEvent;
    compass.getEvent(&magEvent);
    
    // Track min/max values during calibration
    static bool firstReading = true;
    if (firstReading) {
        calMagMinX = calMagMaxX = magEvent.magnetic.x;
        calMagMinY = calMagMaxY = magEvent.magnetic.y;
        calMagMinZ = calMagMaxZ = magEvent.magnetic.z;
        firstReading = false;
    } else {
        if (magEvent.magnetic.x < calMagMinX) calMagMinX = magEvent.magnetic.x;
        if (magEvent.magnetic.x > calMagMaxX) calMagMaxX = magEvent.magnetic.x;
        if (magEvent.magnetic.y < calMagMinY) calMagMinY = magEvent.magnetic.y;
        if (magEvent.magnetic.y > calMagMaxY) calMagMaxY = magEvent.magnetic.y;
        if (magEvent.magnetic.z < calMagMinZ) calMagMinZ = magEvent.magnetic.z;
        if (magEvent.magnetic.z > calMagMaxZ) calMagMaxZ = magEvent.magnetic.z;
    }
    
    // Send calibration data to app every 500ms
    if (millis() - lastCalibrationDataSent >= 500) {
        gpsReceiver.sendCalibrationData(
            magEvent.magnetic.x, magEvent.magnetic.y, magEvent.magnetic.z,
            calMagMinX, calMagMinY, calMagMinZ,
            calMagMaxX, calMagMaxY, calMagMaxZ
        );
        lastCalibrationDataSent = millis();
    }
    
    // Display calibration status
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(16, 5);
    display.print("CALIBRATION MODE");
    display.setCursor(4, 20);
    display.print("Rotate device slowly");
    display.setCursor(8, 30);
    display.print("in all directions");
    display.setCursor(4, 45);
    display.print("X: ");
    display.print(magEvent.magnetic.x, 1);
    display.setCursor(4, 55);
    display.print("Y: ");
    display.print(magEvent.magnetic.y, 1);
    display.setCursor(64, 55);
    display.print("Z: ");
    display.print(magEvent.magnetic.z, 1);
    display.display();
    
    delay(100);
}
