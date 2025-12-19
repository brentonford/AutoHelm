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

// Hold transmission state
Button activeHoldButton = Button::Count;
bool isHoldActive = false;
uint32_t lastHoldTransmitTime = 0;
uint32_t holdStartTime = 0;
constexpr uint32_t holdTransmitIntervalMs = 68;
constexpr uint32_t holdTransmitTimeoutMs = 30000;

// Test waypoint (Sydney Harbour Bridge)
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
        Serial.printf("  HDOP: %.1f  VDOP: %.1f  PDOP: %.1f\n",
            data.hdop, data.vdop, data.pdop);
    }
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
    Serial.printf("  GPS DOP Valid:     %s (< %.1f)\n",
        status.gpsDopValid ? "YES" : "NO", NavigationConfig::maxDop);
    Serial.printf("  Compass Available: %s\n", status.compassAvailable ? "YES" : "NO");
    Serial.printf("  BLE Available:     %s\n", bleAvailable ? "YES" : "NO");
    Serial.printf("  BLE Connected:     %s\n", ble.isConnected() ? "YES" : "NO");
    Serial.println();
    Serial.printf("  Navigation Ready:  %s\n", status.isNavigationReady() ? "YES" : "NO");
}

void testNavigationCalculations() {
    Serial.println();
    Serial.println("[Nav] Testing navigation calculations...");

    float lat1 = -33.8568f;
    float lon1 = 151.2153f;
    float lat2 = -33.8523f;
    float lon2 = 151.2108f;

    float distance = NavigationUtils::calculateDistance(lat1, lon1, lat2, lon2);
    float bearing = NavigationUtils::calculateBearing(lat1, lon1, lat2, lon2);

    Serial.println("  From: Sydney Opera House (-33.8568, 151.2153)");
    Serial.println("  To:   Sydney Harbour Bridge (-33.8523, 151.2108)");
    Serial.printf("  Distance: %.1f m (expected ~680m)\n", distance);
    Serial.printf("  Bearing:  %.1f° (expected ~315°)\n", bearing);

    Serial.println();
    Serial.println("  Relative angle tests:");
    Serial.printf("    Heading 0°, Bearing 90°:   %+.1f° (expected +90)\n",
        NavigationUtils::calculateRelativeAngle(0.0f, 90.0f));
    Serial.printf("    Heading 0°, Bearing 270°:  %+.1f° (expected -90)\n",
        NavigationUtils::calculateRelativeAngle(0.0f, 270.0f));
    Serial.printf("    Heading 90°, Bearing 0°:   %+.1f° (expected -90)\n",
        NavigationUtils::calculateRelativeAngle(90.0f, 0.0f));
    Serial.printf("    Heading 350°, Bearing 10°: %+.1f° (expected +20)\n",
        NavigationUtils::calculateRelativeAngle(350.0f, 10.0f));
}

void printNavigationStatus() {
    Serial.println();
    Serial.println("[Nav] Status:");

    const char* stateStr = "UNKNOWN";
    switch (navigation.getState()) {
        case NavigationState::Idle:       stateStr = "IDLE"; break;
        case NavigationState::Navigating: stateStr = "NAVIGATING"; break;
        case NavigationState::Arrived:    stateStr = "ARRIVED"; break;
    }

    Serial.printf("  State: %s\n", stateStr);
    Serial.printf("  Enabled: %s\n", navigation.isEnabled() ? "YES" : "NO");

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
            remote.transmitSingle(Button::Left);  // Transmit immediately
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
            remote.transmitSingle(Button::Right);  // Transmit immediately
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
    
    // Safety timeout
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

        case BleCommand::None:
            break;
    }
}

void broadcastStatus() {
    if (!bleAvailable || !ble.isConnected())
        return;

    GpsData gpsData = gps.getData();
    NavigationData navData = navigation.getNavigationData();
    Waypoint target = navigation.getTarget();

    ble.sendStatus(gpsData, currentHeading, navData, target);
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
        // Stop hold transmission immediately on disconnect
        if (isHoldActive) {
            Serial.println("[Safety] BLE disconnected - stopping hold transmission");
            isHoldActive = false;
            if (remoteAvailable) {
                remote.transmitSingle(Button::Release);
            }
        }
        
        // Disable navigation
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
        gpsData.hasFix ? "FIX" : "NO FIX",
        gpsData.satellites,
        gpsData.hdop);
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
    Serial.println("  Nav:     t (test calculations)");
    Serial.println("  Nav:     n (navigation status)");
    Serial.println("  Nav:     w (set test waypoint)");
    Serial.println("  Nav:     e (enable/disable navigation)");
    Serial.println("  Nav:     x (clear waypoint)");
}

void loop() {
    // Update GPS
    if (gpsAvailable)
        gps.update();

    // Update compass
    if (compassAvailable)
        currentHeading = compass.readHeading();

    // Process BLE inputs
    if (bleAvailable) {
        ble.update();
        processBleWaypoint();
        processBleCommand();
        processBleRfCommand();
        processHoldTransmission();
    }

    // Safety checks
    checkBleConnection();
    checkSafetyConditions();

    // Update navigation
    if (navigation.isEnabled() && gpsAvailable && compassAvailable) {
        GpsData gpsData = gps.getData();
        navigation.update(gpsData, currentHeading);
        processHeadingCorrection();
    }

    // Broadcast status via BLE
    broadcastStatus();

    // Periodic status to serial
    printPeriodicStatus();

    // Process serial commands
    if (!Serial.available())
        return;

    char c = Serial.read();

    switch (c) {
        // Hold commands (uppercase)
        case 'R': remote.transmitHold(Button::Right); break;
        case 'L': remote.transmitHold(Button::Left); break;
        case 'U': remote.transmitHold(Button::Up); break;
        case 'D': remote.transmitHold(Button::Down); break;
        case 'M': remote.transmitHold(Button::Motor); break;
        case 'S': remote.transmitHold(Button::Momentary); break;

        // Single commands (lowercase)
        case 'r': remote.transmitSingle(Button::Right); break;
        case 'l': remote.transmitSingle(Button::Left); break;
        case 'u': remote.transmitSingle(Button::Up); break;
        case 'd': remote.transmitSingle(Button::Down); break;
        case 'm': remote.transmitSingle(Button::Motor); break;
        case 's': remote.transmitSingle(Button::Momentary); break;

        // Release
        case '0': remote.transmitSingle(Button::Release); break;

        // GPS status
        case 'g': printGpsStatus(); break;

        // Compass heading
        case 'c': printCompassHeading(); break;

        // Sensor validation
        case 'v': printSensorStatus(); break;

        // Navigation commands
        case 't': testNavigationCalculations(); break;
        case 'n': printNavigationStatus(); break;
        case 'w': setTestWaypoint(); break;
        case 'e': toggleNavigation(); break;
        case 'x': navigation.clearTarget(); break;
    }
}