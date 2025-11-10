#ifndef BLUETOOTH_CONTROLLER_H
#define BLUETOOTH_CONTROLLER_H

#include <ArduinoBLE.h>
#include "DataModels.h"
#include "NavigationManager.h"

class BluetoothController {
public:
    typedef void (*WaypointCallback)(float latitude, float longitude);
    typedef void (*NavigationCallback)(bool enabled);
    
private:
    BLEService bluetoothService;
    BLECharacteristic waypointCharacteristic;
    BLECharacteristic statusCharacteristic;
    BLECharacteristic calibrationCommandCharacteristic;
    BLECharacteristic calibrationDataCharacteristic;
    
    bool initialized;
    bool connected;
    static WaypointCallback waypointCallback;
    static NavigationCallback navigationCallback;
    
    static BluetoothController* instance;
    
    static void onConnect(BLEDevice central);
    static void onDisconnect(BLEDevice central);
    static void onWaypointReceived(BLEDevice central, BLECharacteristic characteristic);
    static void onCalibrationCommand(BLEDevice central, BLECharacteristic characteristic);
    
public:
    BluetoothController();
    bool begin(const char* deviceName);
    void update();
    bool isConnected() const;
    void sendStatus(const char* jsonData);
    void sendCalibrationData(const char* jsonData);
    void broadcastStatus(const GPSData& gps, const NavigationState& nav, float heading);
    String createStatusJSON(const GPSData& gps, const NavigationState& nav, float heading);
    bool isInitialized() const;
    void setWaypointCallback(WaypointCallback callback);
    void setNavigationCallback(NavigationCallback callback);
};

#endif