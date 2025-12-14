#pragma once

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "DataModels.h",

namespace BleConfig {
    constexpr const char* deviceName = "Helm";
    constexpr const char* serviceUuid = "0000FFE0-0000-1000-8000-00805F9B34FB";
    constexpr const char* waypointCharUuid = "0000FFE1-0000-1000-8000-00805F9B34FB";
    constexpr const char* statusCharUuid = "0000FFE2-0000-1000-8000-00805F9B34FB";
    constexpr const char* commandCharUuid = "0000FFE3-0000-1000-8000-00805F9B34FB";
    constexpr const char* calibrationCharUuid = "0000FFE4-0000-1000-8000-00805F9B34FB";
    constexpr uint32_t statusIntervalMs = 500;
}

enum class BleCommand : uint8_t {
    None,
    NavEnable,
    NavDisable,
    StartCalibration,
    StopCalibration
};

struct BleStatus {
    bool connected;
    bool waypointReceived;
    float waypointLat;
    float waypointLon;
    BleCommand pendingCommand;

    BleStatus()
        : connected(false)
        , waypointReceived(false)
        , waypointLat(0.0f)
        , waypointLon(0.0f)
        , pendingCommand(BleCommand::None) {
    }
};

class BleManager : public BLEServerCallbacks, public BLECharacteristicCallbacks {
public:
    BleManager();

    bool begin();
    void update();
    void sendStatus(const GpsData& gpsData, float heading, const NavigationData& navData, const Waypoint& target);
    void sendCalibrationData(const String& data);
    void sendResponse(const String& response);

    bool isConnected() const;
    bool hasWaypointPending() const;
    Waypoint consumeWaypoint();
    BleCommand consumeCommand();

    // BLEServerCallbacks
    void onConnect(BLEServer* server) override;
    void onDisconnect(BLEServer* server) override;

    // BLECharacteristicCallbacks
    void onWrite(BLECharacteristic* characteristic) override;

private:
    BLEServer* _server;
    BLEService* _service;
    BLECharacteristic* _waypointChar;
    BLECharacteristic* _statusChar;
    BLECharacteristic* _commandChar;
    BLECharacteristic* _calibrationChar;
    BleStatus _status;
    uint32_t _lastStatusTime;

    void parseWaypoint(const String& data);
    void parseCommand(const String& data);
    String buildStatusJson(const GpsData& gpsData, float heading, const NavigationData& navData, const Waypoint& target);
};