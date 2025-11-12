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
    int effectiveMTU;
    int negotiatedMTU;
    static WaypointCallback waypointCallback;
    static NavigationCallback navigationCallback;
    
    static BluetoothController* instance;
    
    static void onConnect(BLEDevice central);
    static void onDisconnect(BLEDevice central);
    static void onWaypointReceived(BLEDevice central, BLECharacteristic characteristic);
    static void onCalibrationCommand(BLEDevice central, BLECharacteristic characteristic);
    
    // MTU negotiation and optimization
    void requestHigherMTU();
    void updateEffectiveMTU(int mtu);
    void probeMTUCapacity();
    void detectActualMTU(int successfulLength);
    
    // Fragmentation methods
    bool sendFragmentedMessage(const char* jsonData);
    void sendFragment(const char* data, int dataLen, uint8_t seqNum, uint8_t totalFragments, uint16_t totalLength);
    bool isValidCompleteJSON(const char* jsonData);
    String createEssentialStatusJSON();
    String createTestJSON(int targetSize);
    uint8_t calculateChecksum(const char* data, int length);
    
public:
    BluetoothController();
    bool begin(const char* deviceName);
    void update();
    bool isConnected() const;
    void sendStatus(const char* jsonData);
    void sendCalibrationData(const char* jsonData);
    void broadcastStatus(const GPSData& gps, const NavigationState& nav, float heading);
    String createStatusJSON(const GPSData& gps, const NavigationState& nav, float heading);
    String createCompressedStatusJSON();
    bool isInitialized() const;
    void setWaypointCallback(WaypointCallback callback);
    void setNavigationCallback(NavigationCallback callback);
    int getMTU() const { return negotiatedMTU; }
};

#endif