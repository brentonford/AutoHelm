#pragma once

#include <cstdint>
#include <cstring>
#include <cmath>

namespace Pins {
    constexpr uint8_t cc1101Cs   = 5;
    constexpr uint8_t cc1101Gdo0 = 4;
    constexpr uint8_t cc1101Sck  = 18;
    constexpr uint8_t cc1101Miso = 19;
    constexpr uint8_t cc1101Mosi = 23;
    constexpr uint8_t gpsRx = 16;
    constexpr uint8_t gpsTx = 17;
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
}

// SpotLock algorithm settings – mirrors iOS SpotLockSettings (Codable)
struct SpotLockSettings {
    float    deadZoneRadius            = 2.0f;
    float    activationThreshold       = 4.0f;
    float    jogDistance               = 1.5f;
    uint8_t  minSpeed                  = 3;
    uint8_t  maxSpeed                  = 10;
    float    proportionalGain          = 1.0f;
    float    speedChangeDelayMs        = 2000.0f;
    float    headingTolerance          = 10.0f;
    float    correctionIntervalMs      = 1000.0f;
    float    smallAngleThreshold       = 30.0f;
    float    largeAngleThreshold       = 90.0f;
    uint16_t smallSteeringDuration     = 200;
    uint16_t mediumSteeringDuration    = 600;
    uint16_t largeSteeringDuration     = 1000;
    float    maxRotationBeforeUntangle = 720.0f;
    float    rotationPerMs             = 0.1f;
    uint8_t  minSatellites             = 4;
    float    maxHDOP                   = 5.0f;
    uint8_t  maxConsecutiveGpsFail     = 5;
    uint8_t  filterWindowSize          = 5;
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
    float headingOffset;

    CompassCalibration()
        : offsetX(0.0f)
        , offsetY(0.0f)
        , offsetZ(0.0f)
        , scaleX(1.0f)
        , scaleY(1.0f)
        , scaleZ(1.0f)
        , headingOffset(0.0f) {
    }
};

// Top-level system state, derived in Helm.ino and broadcast via BLE telemetry.
enum class HelmState : uint8_t {
    Idle           = 0,
    SpotLockActive = 1,
    NavApproaching = 2,
    NavArriving    = 3,
    Disengaging    = 4,  // either controller is ramping down
    Fault          = 5
};