#pragma once

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "DataModels.h"
#include "SpotLockController.h"
#include "WaypointNavController.h"

namespace BleConfig {
    constexpr const char* deviceName = "Helm";
    constexpr const char* serviceUuid = "0000FFE0-0000-1000-8000-00805F9B34FB";
    constexpr const char* sensorStatusCharUuid = "0000FFE2-0000-1000-8000-00805F9B34FB";
    constexpr const char* commandCharUuid = "0000FFE3-0000-1000-8000-00805F9B34FB";
    constexpr const char* calibrationCharUuid = "0000FFE4-0000-1000-8000-00805F9B34FB";
    constexpr const char* responseCharUuid = "0000FFE5-0000-1000-8000-00805F9B34FB";
    constexpr uint32_t statusIntervalMs = 500;
    constexpr size_t jsonBufferSize = 768;  // Enlarged for SpotLock + WaypointNav telemetry fields
}

enum class BleCommand : uint8_t {
    None,
    StartCalibration,
    StopCalibration
};

enum class SpotLockCommand : uint8_t {
    None,
    Engage,
    Disengage,
    Jog,
    ApplySettings
};

enum class NavCommand : uint8_t {
    None,
    Start,
    Cancel
};

struct BleStatus {
    bool connected;
    BleCommand pendingCommand;
    String pendingRfCommand;
    bool isHoldCommand;
    CompassCalibration pendingCalibration;
    bool hasCalibrationPending;

    // SpotLock commands
    SpotLockCommand  pendingSlCommand;
    float            slEngageLat;
    float            slEngageLon;
    SpotLockJogDir   slJogDir;
    SpotLockSettings slPendingSettings;
    bool             hasSlSettingsPending;

    // Waypoint navigation commands
    NavCommand       pendingNavCommand;
    float            navTargetLat;
    float            navTargetLon;
    uint8_t          navTargetSpeed;
    SpotLockSettings navPendingSettings;
    bool             hasNavSettingsPending;

    BleStatus()
        : connected(false)
        , pendingCommand(BleCommand::None)
        , pendingRfCommand("")
        , isHoldCommand(false)
        , hasCalibrationPending(false)
        , pendingSlCommand(SpotLockCommand::None)
        , slEngageLat(0.0f)
        , slEngageLon(0.0f)
        , slJogDir(SpotLockJogDir::Forward)
        , hasSlSettingsPending(false)
        , pendingNavCommand(NavCommand::None)
        , navTargetLat(0.0f)
        , navTargetLon(0.0f)
        , navTargetSpeed(5)
        , hasNavSettingsPending(false) {
    }
};

class BleManager : public BLEServerCallbacks, public BLECharacteristicCallbacks {
public:
    BleManager();

    bool begin();
    void update();
    void sendSensorStatus(const GpsData& gpsData, float heading,
                          const SpotLockState& slState, const WaypointNavState& navState,
                          HelmState helmState);
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

    // SpotLock command accessors
    bool            hasSpotLockCommandPending() const;
    SpotLockCommand consumeSpotLockCommand();
    float           getSlEngageLat() const;
    float           getSlEngageLon() const;
    SpotLockJogDir  getSlJogDir() const;
    bool            hasSlSettingsPending() const;
    SpotLockSettings consumeSlSettings();

    // Navigation command accessors
    bool             hasNavCommandPending() const;
    NavCommand       consumeNavCommand();
    float            getNavTargetLat() const;
    float            getNavTargetLon() const;
    uint8_t          getNavTargetSpeed() const;
    bool             hasNavSettingsPending() const;
    SpotLockSettings consumeNavSettings();

    bool wasJustDisconnected() const;
    void clearDisconnectFlag();

    void onConnect(BLEServer* server) override;
    void onDisconnect(BLEServer* server) override;
    void onWrite(BLECharacteristic* characteristic) override;

private:
    BLEServer*         _server;
    BLEService*        _service;
    BLECharacteristic* _sensorStatusChar;
    BLECharacteristic* _commandChar;
    BLECharacteristic* _calibrationChar;
    BLECharacteristic* _responseChar;
    BleStatus          _status;
    uint32_t           _lastStatusTime;
    bool               _justDisconnected;

    void   parseCommand(const char* data);
    String buildSensorStatusJson(const GpsData& gpsData, float heading,
                                 const SpotLockState& slState,
                                 const WaypointNavState& navState,
                                 HelmState helmState);
};