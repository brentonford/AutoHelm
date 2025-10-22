#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_MMC56x3.h>
#include <Wire.h>
#include <SoftwareSerial.h>
#include <math.h>
#include "GPSParser.h"
#include "WatersnakeRFController.h"


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

// Create a GPS reader
GPSReader gps(gpsSerial);

// Initialize compass/magnetometer
Adafruit_MMC5603 compass = Adafruit_MMC5603(12345);

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

// Set your destination coordinates here (latitude, longitude)
const float DESTINATION_LAT = -32.940931;  // Latitude in decimal degrees
const float DESTINATION_LON = 151.718029;  // Longitude in decimal degrees

// Variables to store the latest GPS information
float latest_distance = 0;
float latest_bearing = 0;

float calculate_distance(float lat1, float lon1, float lat2, float lon2);
float calculate_bearing(float lat1, float lon1, float lat2, float lon2);
void draw_arrow(float angle, int center_x, int center_y, int size);
float read_heading();
void adjustHeading(float relativeAngle, WatersnakeRFController& remote);
void updateDisplay(GPSData gpsData, float heading, float distance, float bearing);
void printDebugInfo(GPSData gpsData, float heading);

WatersnakeRFController remote;

void setup() {
  // Initialize serial for debugging
  Serial.begin(9600);
  Serial.println("GPS Navigation Starting...");
  
  // Initialize I2C and OLED display
  if(!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println(F("SSD1306 allocation failed"));
    for(;;); // Don't proceed, loop forever
  }
  
  // Initialize GPS
  gpsSerial.begin(9600);
  
  // Initialize magnetometer
  if (!compass.begin(MMC56X3_DEFAULT_ADDRESS, &Wire1)) {
    Serial.println("Ooops, no MMC5603 detected ... Check your wiring!");
    while (1) delay(10);
  }
  
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
  display.setCursor(0, 0);
  display.println("GPS Navigation System");
  display.println("Initializing...");
  display.display();
  delay(2000);
}


void loop() {
  // Clear the display
  display.clearDisplay();
  
  // Get compass heading
  float heading = read_heading();
  
  // Get current GPS data
  GPSData gps_data = gps.get_data();
  
  // If we have valid GPS data, calculate distance and bearing
  if (gps_data.has_fix) {
    // Calculate distance to destination
    latest_distance = calculate_distance(gps_data.latitude, gps_data.longitude, DESTINATION_LAT, DESTINATION_LON);
    
    // Calculate bearing to destination
    latest_bearing = calculate_bearing(gps_data.latitude, gps_data.longitude, DESTINATION_LAT, DESTINATION_LON);
    
    // Calculate the difference between bearing to destination and current heading
    float relative_angle = fmod((latest_bearing - heading + 360.0), 360.0);

    adjustHeading(relative_angle, remote);

  }
  
  // Update the display
  updateDisplay(gpsData, heading, latest_distance, latest_bearing);

  printDebugInfo(gpsData, heading);
  
  // Update at 10 Hz
  delay(100);
}