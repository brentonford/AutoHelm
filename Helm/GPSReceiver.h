/*
 * GPSReceiver.h
 * 
 * Bluetooth Low Energy GPS waypoint receiver library
 * Receives GPS coordinates from mobile app via BLE connection
 * 
 * Protocol: "$GPS,latitude,longitude,altitude*"
 * Example: "$GPS,-32.940931,151.718029,45.2*"
 * 
 * Hardware Requirements:
 * - Arduino with BLE capability (Arduino Nano 33 BLE, UNO R4 WiFi, etc.)
 * - ArduinoBLE library
 * 
 * Usage:
 * GPSReceiver gpsReceiver;
 * gpsReceiver.begin("DeviceName");
 * 
 * In loop():
 * gpsReceiver.update();
 * if (gpsReceiver.hasTarget()) {
 *     float lat = gpsReceiver.getLatitude();
 *     float lon = gpsReceiver.getLongitude();
 * }
 */

#ifndef GPS_RECEIVER_H
#define GPS_RECEIVER_H

#include <Arduino.h>
#include <ArduinoBLE.h>

class GPSReceiver {
private:
    BLEService gpsService;
    BLECharacteristic gpsCharacteristic;
    BLECharacteristic statusCharacteristic;
    
    double targetLatitude;
    double targetLongitude;
    double targetAltitude;
    bool hasValidTarget;
    String inputBuffer;
    
    void parseGPSData(String data);
    
public:
    GPSReceiver();
    
    bool begin(const char* deviceName);
    void update();
    bool hasTarget();
    double getLatitude();
    double getLongitude();
    double getAltitude();
    void clearTarget();
    bool isConnected();
    void sendNavigationStatus(bool hasGpsFix, int satellites, double currentLat, double currentLon, 
                             double altitude, float heading, float distance, float bearing, 
                             double targetLat, double targetLon);
};

#endif