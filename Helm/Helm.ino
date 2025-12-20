#include "DataModels.h"
#include "CC1101.h"
#include "Remote.h"
#include "GpsManager.h"
#include "CompassManager.h"
#include "NavigationUtils.h"
#include "NavigationManager.h"
#include "BleManager.h"

CC1101 cc1101(
    Pins::cc1101Cs,
    Pins::cc1101Sck,
    Pins::cc1101Miso,
    Pins::cc1101Mosi
);

Remote remote(cc1101, Pins::cc1101Gdo0);
GpsManager gps(Pins::gpsRx, Pins::gpsTx);
CompassManager compass(Pins::i2cSda, Pins::i2cScl);
NavigationManager navigation;
BleManager ble;

bool cc1101Available = false;
bool remoteAvailable = false;
bool gpsAvailable = false;
bool compassAvailable = false;
bool bleAvailable = false;
bool bleWasConnected = false;

float currentHeading = 0.0f;
uint32_t lastStatusPrintTime = 0;
constexpr uint32_t statusPrintIntervalMs = 5000;

Button activeHoldButton = Button::Count;
bool isHoldActive = false;
uint32_t lastHoldTransmitTime = 0;
uint32_t holdStartTime = 0;
constexpr uint32_t holdTransmitIntervalMs = 68;
constexpr uint32_t holdTransmitTimeoutMs = 30000;

constexpr float testWaypointLat = -33.8523f;
constexpr float testWaypointLon = 151.2108f;

void printGpsStatus() {
    GpsData data = gps.getData();

    Serial.println();
    Serial.println("[GPS] Status:");
    Serial.printf("  Fix: %s\n", data.hasFix ? "YES" : "NO");
    Serial.printf("  Satellites: %d\n", data.satellites);

    if (data.hasFix) {
        Serial.printf("  Position: %.6f, %.6f\n", data.latitude, data.longitude);
        Serial.printf("  Altitude: %.1f m\n", data.altitude);
        Serial.printf("  HDOP: %.1f  VDOP: %.1f  PDOP: %.1f\n", data.hdop, data.vdop, data.pdop);
        Serial.printf("  Data age: %lu ms\n", millis() - data.timestamp);
    } else {
        Serial.println("  Waiting for fix...");
    }
    Serial.println();
}

void printCompassHeading() {
    if (!compassAvailable) {
        Serial.println("[Compass] Not available");
        return;
    }
    Serial.printf("[Compass] Heading: %.1f°\n", currentHeading);
}

void printSensorStatus() {
    SensorStatus status;
    status.gpsAvailable = gpsAvailable;
    status.compassAvailable = compassAvailable;

    if (gpsAvailable) {
        status.gpsFixValid = gps.hasValidFix();
        status.gpsDopValid = gps.hasAcceptableDop();
    }

    Serial.println();
    Serial.println("[Sensors] Status:");
    Serial.printf("  GPS Available:     %s\n", status.gpsAvailable ? "YES" : "NO");
    Serial.printf("  GPS Fix Valid:     %s\n", status.gpsFixValid ? "YES" : "NO");
    Serial.printf("  GPS DOP Valid:     %s (< %.1f)\n", status.gpsDopValid ? "YES" : "NO", NavigationConfig::maxDop);
    Serial.printf("  Compass Available: %s\n", status.compassAvailable ? "YES" : "NO");
    Serial.printf("  BLE Available:     %s\n", bleAvailable ? "YES" : "NO");
    Serial.printf("  BLE Connected:     %s\n", ble.isConnected() ? "YES" : "NO");
    Serial.printf("  Motor Responding:  %s\n", navigation.isMotorResponding() ? "YES" : "NO");
    Serial.println();
    Serial.printf("  Navigation Ready:  %s\n", status.isNavigationReady() ? "YES" : "NO");
}

void printNavigationStatus() {
    Serial.println();
    Serial.println("[Nav] Status:");

    const char* stateStr = "UNKNOWN";
    switch (navigation.getState()) {
        case NavigationState::Idle:          stateStr = "IDLE"; break;
        case NavigationState::Navigating:    stateStr = "NAVIGATING"; break;
        case NavigationState::Arrived:       stateStr = "ARRIVED"; break;
        case NavigationState::PathFollowing: stateStr = "PATH_FOLLOWING"; break;
        case NavigationState::SpotLock:      stateStr = "SPOT_LOCK"; break;
        case NavigationState::Manual:        stateStr = "MANUAL"; break;
    }

    Serial.printf("  State: %s\n", stateStr);
    Serial.printf("  Enabled: %s\n", navigation.isEnabled() ? "YES" : "NO");
    Serial.printf("  Spot Lock: %s\n", navigation.isSpotLockActive() ? "ACTIVE" : "OFF");

    SpeedState speedState = navigation.getSpeedState();
    Serial.printf("  Speed Level: %d/%d\n", speedState.currentLevel, speedState.targetLevel);

    if (navigation.hasTarget()) {
        Waypoint target = navigation.getTarget();
        Serial.printf("  Target: %.6f, %.6f\n", target.latitude, target.longitude);

        if (navigation.isEnabled()) {
            NavigationData navData = navigation.getNavigationData();
            Serial.printf("  Distance: %.1f m\n", navData.distanceToTarget);
            Serial.printf("  Bearing:  %.1f°\n", navData.bearingToTarget);
            Serial.printf("  Relative: %+.1f°\n", navData.relativeAngle);
            Serial.printf("  Needs Correction: %s\n", navigation.needsCorrection() ? "YES" : "NO");
        }
    } else {
        Serial.println("  Target: NOT SET");
    }
}

void setTestWaypoint() {
    navigation.setTarget(testWaypointLat, testWaypointLon);
}

void toggleNavigation() {
    navigation.setEnabled(!navigation.isEnabled());
}

void processHeadingCorrection() {
    if (!remoteAvailable)
        return;

    HeadingCorrection correction = navigation.getRequiredCorrection();

    switch (correction) {
        case HeadingCorrection::Left:
            remote.transmitSingle(Button::Left);
            break;
        case HeadingCorrection::Right:
            remote.transmitSingle(Button::Right);
            break;
        case HeadingCorrection::None:
            break;
    }
}

void processSpeedControl() {
    if (!remoteAvailable)
        return;

    int8_t speedAdj = navigation.getSpeedAdjustment();
    if (speedAdj > 0) {
        remote.transmitSingle(Button::Up);
        Serial.println("[Speed] UP");
    } else if (speedAdj < 0) {
        remote.transmitSingle(Button::Down);
        Serial.println("[Speed] DOWN");
    }
}

void processBleWaypoint() {
    if (!ble.hasWaypointPending())
        return;

    Waypoint wp = ble.consumeWaypoint();
    if (wp.isSet) {
        navigation.setTarget(wp.latitude, wp.longitude);
    }
}

void processBleRfCommand() {
    if (!ble.hasRfCommandPending())
        return;

    if (!remoteAvailable)
        return;

    bool isHold = ble.isRfHoldCommand();
    String cmd = ble.consumeRfCommand();
    Serial.printf("[BLE] RF Command: %s (Hold: %s)\n", cmd.c_str(), isHold ? "YES" : "NO");

    if (cmd == "LEFT") {
        if (isHold) {
            activeHoldButton = Button::Left;
            isHoldActive = true;
            holdStartTime = millis();
            lastHoldTransmitTime = millis();
            Serial.println("[BLE] Starting LEFT hold transmission");
            remote.transmitSingle(Button::Left);
        } else {
            remote.transmitHold(Button::Left, 1000);
        }
    } else if (cmd == "RIGHT") {
        if (isHold) {
            activeHoldButton = Button::Right;
            isHoldActive = true;
            holdStartTime = millis();
            lastHoldTransmitTime = millis();
            Serial.println("[BLE] Starting RIGHT hold transmission");
            remote.transmitSingle(Button::Right);
        } else {
            remote.transmitHold(Button::Right, 1000);
        }
    } else if (cmd == "UP") {
        remote.transmitHold(Button::Up, 1000);
    } else if (cmd == "DOWN") {
        remote.transmitHold(Button::Down, 1000);
    } else if (cmd == "MOTOR") {
        remote.transmitHold(Button::Motor, 1000);
    } else if (cmd == "MOMENTARY") {
        remote.transmitHold(Button::Momentary, 1000);
    } else if (cmd == "RELEASE") {
        isHoldActive = false;
        remote.transmitSingle(Button::Release);
        Serial.println("[BLE] Stopping hold transmission");
    }
}

void processHoldTransmission() {
    if (!isHoldActive || !remoteAvailable)
        return;

    uint32_t now = millis();

    if ((now - holdStartTime) >= holdTransmitTimeoutMs) {
        Serial.println("[Safety] Hold transmission timeout - releasing");
        isHoldActive = false;
        remote.transmitSingle(Button::Release);
        return;
    }

    if (lastHoldTransmitTime == 0 || (now - lastHoldTransmitTime) >= holdTransmitIntervalMs) {
        remote.transmitSingle(activeHoldButton);
        lastHoldTransmitTime = now;
    }
}

void processBleCommand() {
    BleCommand cmd = ble.consumeCommand();

    switch (cmd) {
        case BleCommand::NavEnable: {
            GpsData gpsData = gps.getData();
            if (!navigation.canEnableNavigation(gpsData)) {
                String error = "{\"error\":\"";
                if (!navigation.hasTarget()) {
                    error += "No target set";
                } else if (!gpsData.hasFix) {
                    error += "No GPS fix";
                } else if (gpsData.satellites < NavigationConfig::minSatellites) {
                    error += "Insufficient satellites";
                } else if (gpsData.hdop >= NavigationConfig::maxDop) {
                    error += "Poor GPS accuracy";
                }
                error += "\"}";
                Serial.printf("[BLE] Cannot enable nav: %s\n", error.c_str());
                ble.sendResponse(error);
                return;
            }
            navigation.setEnabled(true);
            ble.sendResponse("{\"ack\":\"NAV_ENABLED\"}");
            break;
        }

        case BleCommand::NavDisable:
            navigation.setEnabled(false);
            ble.sendResponse("{\"ack\":\"NAV_DISABLED\"}");
            break;

        case BleCommand::StartCalibration:
            Serial.println("[BLE] Calibration start requested");
            ble.sendResponse("{\"ack\":\"CAL_STARTED\"}");
            break;

        case BleCommand::StopCalibration:
            Serial.println("[BLE] Calibration stop requested");
            ble.sendResponse("{\"ack\":\"CAL_STOPPED\"}");
            break;

        case BleCommand::SpotLockEngage: {
            GpsData gpsData = gps.getData();
            if (!gpsData.hasFix) {
                ble.sendResponse("{\"error\":\"No GPS fix\"}");
                return;
            }
            navigation.engageSpotLock(gpsData.latitude, gpsData.longitude);
            ble.sendResponse("{\"ack\":\"SPOT_LOCK_ENGAGED\"}");
            break;
        }

        case BleCommand::SpotLockDisengage:
            navigation.disengageSpotLock();
            ble.sendResponse("{\"ack\":\"SPOT_LOCK_DISENGAGED\"}");
            break;

        case BleCommand::SpotLockJogForward:
            navigation.jogSpotLock(currentHeading, 2);
            ble.sendResponse("{\"ack\":\"JOG_FWD\"}");
            break;

        case BleCommand::SpotLockJogBack:
            navigation.jogSpotLock(currentHeading, 0);
            ble.sendResponse("{\"ack\":\"JOG_BACK\"}");
            break;

        case BleCommand::SpotLockJogLeft:
            navigation.jogSpotLock(currentHeading, -1);
            ble.sendResponse("{\"ack\":\"JOG_LEFT\"}");
            break;

        case BleCommand::SpotLockJogRight:
            navigation.jogSpotLock(currentHeading, 1);
            ble.sendResponse("{\"ack\":\"JOG_RIGHT\"}");
            break;

        case BleCommand::PathStart:
            if (navigation.getActivePath()) {
                navigation.startPath();
                ble.sendResponse("{\"ack\":\"PATH_STARTED\"}");
            } else {
                ble.sendResponse("{\"error\":\"No path set\"}");
            }
            break;

        case BleCommand::PathStop:
            navigation.stopPath();
            ble.sendResponse("{\"ack\":\"PATH_STOPPED\"}");
            break;

        case BleCommand::ManualMode:
            navigation.setEnabled(false);
            ble.sendResponse("{\"ack\":\"MANUAL_MODE\"}");
            break;

        case BleCommand::None:
            break;

        default:
            break;
    }

    if (ble.hasPendingSpeed()) {
        float speed = ble.consumePendingSpeed();
        navigation.setTargetSpeedKmh(speed);
    }
}

void broadcastStatus() {
    if (!bleAvailable || !ble.isConnected())
        return;

    GpsData gpsData = gps.getData();
    NavigationData navData = navigation.getNavigationData();
    Waypoint target = navigation.getTarget();
    NavigationState navState = navigation.getState();
    SpeedState speedState = navigation.getSpeedState();

    ble.sendStatus(gpsData, currentHeading, navData, target, navState, speedState);
}

void checkSafetyConditions() {
    if (!navigation.isEnabled())
        return;

    GpsData gpsData = gps.getData();
    navigation.checkSafetyConditions(gpsData);

    if (!navigation.isEnabled()) {
        const char* reason = navigation.getDisableReason();
        if (reason) {
            String response = "{\"nav_disabled\":\"";
            response += reason;
            response += "\"}";
            ble.sendResponse(response);
        }
    }
}

void checkBleConnection() {
    bool bleConnected = ble.isConnected();

    if (bleWasConnected && !bleConnected) {
        if (isHoldActive) {
            Serial.println("[Safety] BLE disconnected - stopping hold transmission");
            isHoldActive = false;
            if (remoteAvailable) {
                remote.transmitSingle(Button::Release);
            }
        }

        if (navigation.isEnabled()) {
            Serial.println("[Safety] BLE disconnected - disabling navigation");
            navigation.setEnabled(false);
        }
    }

    bleWasConnected = bleConnected;
}

void printPeriodicStatus() {
    if (!navigation.isEnabled())
        return;

    uint32_t now = millis();
    if ((now - lastStatusPrintTime) < statusPrintIntervalMs)
        return;

    lastStatusPrintTime = now;

    GpsData gpsData = gps.getData();
    NavigationData navData = navigation.getNavigationData();

    Serial.println();
    Serial.println("[Nav] Periodic Status:");
    Serial.printf("  GPS: %s, Sats: %d, HDOP: %.1f\n",
        gpsData.hasFix ? "FIX" : "NO FIX", gpsData.satellites, gpsData.hdop);
    Serial.printf("  Position: %.6f, %.6f\n", gpsData.latitude, gpsData.longitude);
    Serial.printf("  Heading: %.1f°, Target Bearing: %.1f°\n", currentHeading, navData.bearingToTarget);
    Serial.printf("  Distance: %.1f m, Relative: %+.1f°\n", navData.distanceToTarget, navData.relativeAngle);
}

void setup() {
    Serial.begin(Config::serialBaud);
    delay(1000);

    Serial.println();
    Serial.println("=== Helm System Starting ===");
    Serial.println();

    Serial.print("[CC1101] Initializing... ");
    cc1101Available = cc1101.begin();
    Serial.println(cc1101Available ? "SUCCESS" : "FAILED");

    if (cc1101Available) {
        Serial.print("[Remote] Initializing... ");
        remoteAvailable = remote.begin();
        Serial.println(remoteAvailable ? "SUCCESS" : "FAILED");
    }

    Serial.print("[GPS] Initializing... ");
    gpsAvailable = gps.begin();
    Serial.println(gpsAvailable ? "SUCCESS" : "FAILED");

    Serial.print("[Compass] Initializing... ");
    compassAvailable = compass.begin();
    Serial.println(compassAvailable ? "SUCCESS" : "FAILED");

    Serial.print("[BLE] Initializing... ");
    bleAvailable = ble.begin();
    Serial.println(bleAvailable ? "SUCCESS" : "FAILED");

    Serial.println();
    Serial.println("[Helm] Setup complete");
    Serial.println();
    Serial.println("Commands:");
    Serial.println("  Hold:    R/L/U/D/M/S (right/left/up/down/motor/momentary)");
    Serial.println("  Single:  r/l/u/d/m/s");
    Serial.println("  Release: 0");
    Serial.println("  GPS:     g (print status)");
    Serial.println("  Compass: c (print heading)");
    Serial.println("  Sensors: v (validation status)");
    Serial.println("  Nav:     n (navigation status)");
    Serial.println("  Nav:     w (set test waypoint)");
    Serial.println("  Nav:     e (enable/disable navigation)");
    Serial.println("  Nav:     x (clear waypoint)");
    Serial.println("  Spot:    p (engage spot lock)");
    Serial.println("  Spot:    o (disengage spot lock)");
}

void loop() {
    if (gpsAvailable)
        gps.update();

    if (compassAvailable)
        currentHeading = compass.readHeading();

    if (bleAvailable) {
        ble.update();
        processBleWaypoint();
        processBleCommand();
        processBleRfCommand();
        processHoldTransmission();
    }

    checkBleConnection();
    checkSafetyConditions();

    if (navigation.isEnabled() && gpsAvailable && compassAvailable) {
        GpsData gpsData = gps.getData();
        navigation.update(gpsData, currentHeading);
        processHeadingCorrection();
        processSpeedControl();
    }

    broadcastStatus();
    printPeriodicStatus();

    if (!Serial.available())
        return;

    char c = Serial.read();

    switch (c) {
        case 'R': remote.transmitHold(Button::Right); break;
        case 'L': remote.transmitHold(Button::Left); break;
        case 'U': remote.transmitHold(Button::Up); break;
        case 'D': remote.transmitHold(Button::Down); break;
        case 'M': remote.transmitHold(Button::Motor); break;
        case 'S': remote.transmitHold(Button::Momentary); break;

        case 'r': remote.transmitSingle(Button::Right); break;
        case 'l': remote.transmitSingle(Button::Left); break;
        case 'u': remote.transmitSingle(Button::Up); break;
        case 'd': remote.transmitSingle(Button::Down); break;
        case 'm': remote.transmitSingle(Button::Motor); break;
        case 's': remote.transmitSingle(Button::Momentary); break;

        case '0': remote.transmitSingle(Button::Release); break;

        case 'g': printGpsStatus(); break;
        case 'c': printCompassHeading(); break;
        case 'v': printSensorStatus(); break;
        case 'n': printNavigationStatus(); break;
        case 'w': setTestWaypoint(); break;
        case 'e': toggleNavigation(); break;
        case 'x': navigation.clearTarget(); break;

        case 'p': {
            GpsData gpsData = gps.getData();
            if (gpsData.hasFix) {
                navigation.engageSpotLock(gpsData.latitude, gpsData.longitude);
            } else {
                Serial.println("[Nav] Cannot engage spot lock: No GPS fix");
            }
            break;
        }
        case 'o':
            navigation.disengageSpotLock();
            break;
    }
}