#pragma once

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "DataModels.h"

namespace BleConfig {
    constexpr const char* deviceName = "Helm";
    constexpr const char* serviceUuid = "0000FFE0-0000-1000-8000-00805F9B34FB";
    constexpr const char* sensorStatusCharUuid = "0000FFE2-0000-1000-8000-00805F9B34FB";
    constexpr const char* commandCharUuid = "0000FFE3-0000-1000-8000-00805F9B34FB";
    constexpr const char* calibrationCharUuid = "0000FFE4-0000-1000-8000-00805F9B34FB";
    constexpr const char* responseCharUuid = "0000FFE5-0000-1000-8000-00805F9B34FB";  // Dedicated response characteristic
    constexpr uint32_t statusIntervalMs = 500;
    constexpr size_t jsonBufferSize = 384;  // Increased buffer size for JSON with high precision floats
}

enum class BleCommand : uint8_t {
    None,
    StartCalibration,
    StopCalibration
};

struct BleStatus {
    bool connected;
    BleCommand pendingCommand;
    String pendingRfCommand;
    bool isHoldCommand;
    CompassCalibration pendingCalibration;
    bool hasCalibrationPending;

    BleStatus()
        : connected(false)
        , pendingCommand(BleCommand::None)
        , pendingRfCommand("")
        , isHoldCommand(false)
        , hasCalibrationPending(false) {
    }
};

class BleManager : public BLEServerCallbacks, public BLECharacteristicCallbacks {
public:
    BleManager();

    bool begin();
    void update();
    void sendSensorStatus(const GpsData& gpsData, float heading);
    void sendCalibrationData(const String& data);
    void sendResponse(const String& response);
    void sendResponse(const char* response);

    bool isConnected() const;
    BleCommand consumeCommand();
    bool hasRfCommandPending() const;
    String consumeRfCommand();
    bool isRfHoldCommand() const;
    bool hasCalibrationPending() const;
    CompassCalibration consumeCalibration();
    
    bool wasJustDisconnected() const;
    void clearDisconnectFlag();

    void onConnect(BLEServer* server) override;
    void onDisconnect(BLEServer* server) override;
    void onWrite(BLECharacteristic* characteristic) override;

private:
    BLEServer* _server;
    BLEService* _service;
    BLECharacteristic* _sensorStatusChar;
    BLECharacteristic* _commandChar;
    BLECharacteristic* _calibrationChar;
    BLECharacteristic* _responseChar;  // Dedicated response characteristic
    BleStatus _status;
    uint32_t _lastStatusTime;
    bool _justDisconnected;

    void parseCommand(const char* data);
    String buildSensorStatusJson(const GpsData& gpsData, float heading);
};