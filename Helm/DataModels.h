#pragma once

#include <cstdint>

namespace Pins {
    // SPI - CC1101 RF Module
    constexpr uint8_t cc1101Cs   = 5;
    constexpr uint8_t cc1101Gdo0 = 4;
    constexpr uint8_t cc1101Sck  = 18;
    constexpr uint8_t cc1101Miso = 19;
    constexpr uint8_t cc1101Mosi = 23;

    // UART2 - GPS Module
    constexpr uint8_t gpsRx = 16;
    constexpr uint8_t gpsTx = 17;

    // I2C - Magnetometer
    constexpr uint8_t i2cSda = 21;
    constexpr uint8_t i2cScl = 22;
}

namespace Config {
    constexpr uint32_t serialBaud = 115200;
    constexpr uint32_t gpsBaud    = 9600;
}

namespace NavigationConfig {
    constexpr uint8_t minSatellites = 4;
    constexpr float maxDop = 5.0f;
    constexpr float arrivalThresholdM = 5.0f;
    constexpr float headingToleranceDeg = 15.0f;
    constexpr uint32_t correctionIntervalMs = 2000;
}

enum class NavigationState : uint8_t {
    Idle,
    Navigating,
    Arrived
};

enum class HeadingCorrection : uint8_t {
    None,
    Left,
    Right
};

struct Waypoint {
    float latitude;
    float longitude;
    bool isSet;

    Waypoint()
        : latitude(0.0f)
        , longitude(0.0f)
        , isSet(false) {
    }

    void set(float lat, float lon) {
        latitude = lat;
        longitude = lon;
        isSet = true;
    }

    void clear() {
        latitude = 0.0f;
        longitude = 0.0f;
        isSet = false;
    }
};

struct NavigationData {
    float distanceToTarget;
    float bearingToTarget;
    float relativeAngle;

    NavigationData()
        : distanceToTarget(0.0f)
        , bearingToTarget(0.0f)
        , relativeAngle(0.0f) {
    }
};

struct GpsData {
    float latitude;
    float longitude;
    float altitude;
    float hdop;
    float vdop;
    float pdop;
    uint8_t satellites;
    bool hasFix;
    uint32_t timestamp;

    GpsData()
        : latitude(0.0f)
        , longitude(0.0f)
        , altitude(0.0f)
        , hdop(99.0f)
        , vdop(99.0f)
        , pdop(99.0f)
        , satellites(0)
        , hasFix(false)
        , timestamp(0) {
    }
};

struct CompassCalibration {
    float offsetX;
    float offsetY;
    float offsetZ;
    float scaleX;
    float scaleY;
    float scaleZ;

    CompassCalibration()
        : offsetX(0.0f)
        , offsetY(0.0f)
        , offsetZ(0.0f)
        , scaleX(1.0f)
        , scaleY(1.0f)
        , scaleZ(1.0f) {
    }
};

struct SensorStatus {
    bool gpsAvailable;
    bool gpsFixValid;
    bool gpsDopValid;
    bool compassAvailable;

    bool isNavigationReady() const {
        return gpsAvailable && gpsFixValid && gpsDopValid && compassAvailable;
    }

    SensorStatus()
        : gpsAvailable(false)
        , gpsFixValid(false)
        , gpsDopValid(false)
        , compassAvailable(false) {
    }
};