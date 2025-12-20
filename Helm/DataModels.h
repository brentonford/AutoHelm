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
    constexpr float arrivalThresholdM = 5.0f;
    constexpr float headingToleranceDeg = 15.0f;
    constexpr uint32_t correctionIntervalMs = 2000;
}

namespace PathConfig {
    constexpr uint8_t maxPaths = 16;
    constexpr uint8_t maxWaypointsPerPath = 50;
    constexpr float defaultSpeedMs = 1.0f;  // 3.6 km/hr
}

enum class NavigationState : uint8_t {
    Idle,
    Navigating,
    Arrived,
    PathFollowing,
    SpotLock,
    Manual
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
    char name[32];
    bool spotLockEnabled;
    float approachSpeed;
    float arrivalRadius;

    Waypoint()
        : latitude(0.0f)
        , longitude(0.0f)
        , isSet(false)
        , spotLockEnabled(false)
        , approachSpeed(0.0f)
        , arrivalRadius(5.0f) {
        name[0] = '\0';
    }

    void set(float lat, float lon) {
        latitude = lat;
        longitude = lon;
        isSet = true;
    }

    void set(float lat, float lon, const char* wpName) {
        set(lat, lon);
        strncpy(name, wpName, 31);
        name[31] = '\0';
    }

    void clear() {
        latitude = 0.0f;
        longitude = 0.0f;
        isSet = false;
        name[0] = '\0';
        spotLockEnabled = false;
        approachSpeed = 0.0f;
        arrivalRadius = 5.0f;
    }
};

struct Path {
    uint16_t pathId;
    char name[32];
    Waypoint waypoints[PathConfig::maxWaypointsPerPath];
    uint8_t waypointCount;
    float defaultSpeed;
    bool loop;
    bool active;

    Path()
        : pathId(0)
        , waypointCount(0)
        , defaultSpeed(PathConfig::defaultSpeedMs)
        , loop(false)
        , active(false) {
        name[0] = '\0';
    }

    bool addWaypoint(const Waypoint& wp) {
        if (waypointCount >= PathConfig::maxWaypointsPerPath)
            return false;
        waypoints[waypointCount++] = wp;
        return true;
    }

    bool addWaypoint(float lat, float lon, const char* wpName = nullptr) {
        if (waypointCount >= PathConfig::maxWaypointsPerPath)
            return false;
        waypoints[waypointCount].set(lat, lon);
        if (wpName) {
            strncpy(waypoints[waypointCount].name, wpName, 31);
        }
        waypointCount++;
        return true;
    }

    Waypoint* getCurrentWaypoint(uint8_t index) {
        if (index < waypointCount)
            return &waypoints[index];
        return nullptr;
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

struct SpeedState {
    uint8_t currentLevel;
    uint8_t targetLevel;
    float currentSpeedMs;

    SpeedState()
        : currentLevel(0)
        , targetLevel(4)
        , currentSpeedMs(0) {
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