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
float magXmax = 0.00;
float magYmax = 0.00;
float magZmax = 0.00;
float magXmin = 0.00;
float magYmin = 0.00;
float magZmin = 0.00;

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
    
    // Draw the arrow at the center of the display
    draw_arrow(relative_angle, 30, 26, 26);
    
    // Show distance
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    if (latest_distance >= 1000) {
      display.setCursor(4, 57);
      display.print(latest_distance/1000, 1);
      display.print(" km");
    } else {
      display.setCursor(4, 57);
      display.print((int)latest_distance);
      display.print(" m");
    }
    
    // Show altitude
    display.setCursor(94, 57);
    display.print(gps_data.altitude, 1);
    
    // Show current coordinates
    display.setCursor(64, 2);
    display.print(gps_data.latitude, 6);
    display.setCursor(64, 12);
    display.print(gps_data.longitude, 6);
    
    // Show destination coordinates
    display.setCursor(64, 30);
    display.print(DESTINATION_LAT, 6);
    display.setCursor(64, 40);
    display.print(DESTINATION_LON, 6);
    
    // Draw the partial octagon around the arrow
    display.drawLine(47, 0, 58, 11, SSD1306_WHITE);
    display.drawLine(58, 11, 58, 38, SSD1306_WHITE);
    display.drawLine(58, 38, 47, 49, SSD1306_WHITE);
    display.drawLine(0, 11, 11, 0, SSD1306_WHITE);
    display.drawLine(0, 11, 0, 38, SSD1306_WHITE);          
    display.drawLine(0, 38, 11, 49, SSD1306_WHITE);
    
    // Draw the partial box around altitude
    display.drawLine(86, 54, 86, 64, SSD1306_WHITE);
    display.drawLine(86, 54, 128, 54, SSD1306_WHITE);
    
    // Draw the line between the current coords and the target
    display.drawLine(70, 24, 128, 24, SSD1306_WHITE);
  } else {
    // No GPS fix - show "Waiting for GPS" and satellite count if available
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(14, 20);
    display.print("Waiting for GPS");
    display.setCursor(44, 35);
    display.print("No Fix");
    
    // Show satellite count
    display.setCursor(24, 50);
    display.print("Satellites: ");
    display.print(gps_data.satellites);
  }
  
  // Print debug information to the serial console
  Serial.print("Satellites: ");
  Serial.print(gps_data.satellites);
  Serial.print(", Position: ");
  Serial.print(gps_data.latitude, 6);
  Serial.print(", ");
  Serial.print(gps_data.longitude, 6);
  Serial.print(", Altitude: ");
  Serial.print(gps_data.altitude);
  Serial.print(" m, Fix: ");
  Serial.print(gps_data.has_fix ? "Yes" : "No");
  Serial.print(", Heading: ");
  Serial.println(heading);
  
  // Update the display
  display.display();
  
  // Update at 10 Hz
  delay(100);
}