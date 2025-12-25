#include "DataModels.h"
#include "CC1101.h"
#include "Remote.h"
#include "GpsManager.h"
#include "CompassManager.h"
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
BleManager ble;

bool cc1101Available = false;
bool remoteAvailable = false;
bool gpsAvailable = false;
bool compassAvailable = false;
bool bleAvailable = false;

float currentHeading = 0.0f;
uint32_t lastStatusBroadcastTime = 0;
constexpr uint32_t statusBroadcastIntervalMs = 500;

Button activeHoldButton = Button::Count;
bool isHoldActive = false;
uint32_t lastHoldTransmitTime = 0;
uint32_t holdStartTime = 0;
constexpr uint32_t holdTransmitIntervalMs = 68;
constexpr uint32_t holdTransmitTimeoutMs = 30000;

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
    Serial.printf("[Compass] Heading: %.1f deg\n", currentHeading);
}

void printSensorStatus() {
    Serial.println();
    Serial.println("[Sensors] Status:");
    Serial.printf("  GPS Available:     %s\n", gpsAvailable ? "YES" : "NO");
    Serial.printf("  GPS Fix Valid:     %s\n", gps.hasValidFix() ? "YES" : "NO");
    Serial.printf("  GPS DOP Valid:     %s (< %.1f)\n", gps.hasAcceptableDop() ? "YES" : "NO", NavigationConfig::maxDop);
    Serial.printf("  Compass Available: %s\n", compassAvailable ? "YES" : "NO");
    Serial.printf("  BLE Available:     %s\n", bleAvailable ? "YES" : "NO");
    Serial.printf("  BLE Connected:     %s\n", ble.isConnected() ? "YES" : "NO");
}

void processBleRfCommand() {
    if (!ble.hasRfCommandPending()) {
        return;
    }

    if (!remoteAvailable) {
        ble.consumeRfCommand();
        return;
    }

    bool isHold = ble.isRfHoldCommand();
    String cmd = ble.consumeRfCommand();

    if (cmd == "LEFT") {
        Serial.println("[BLE] Processing LEFT command");
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
    } else {
        Serial.printf("[BLE] Unknown RF command: %s\n", cmd.c_str());
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
        case BleCommand::StartCalibration:
            Serial.println("[BLE] Calibration start requested");
            compass.startCalibration();
            ble.sendResponse("{\"ack\":\"CAL_STARTED\"}");
            break;

        case BleCommand::StopCalibration:
            Serial.println("[BLE] Calibration stop requested");
            compass.stopCalibration();
            {
                CompassCalibration cal = compass.getCalibration();
                String response = "{\"ack\":\"CAL_STOPPED\",";
                response += "\"offsetX\":" + String(cal.offsetX, 2) + ",";
                response += "\"offsetY\":" + String(cal.offsetY, 2) + ",";
                response += "\"offsetZ\":" + String(cal.offsetZ, 2) + ",";
                response += "\"scaleX\":" + String(cal.scaleX, 4) + ",";
                response += "\"scaleY\":" + String(cal.scaleY, 4) + ",";
                response += "\"scaleZ\":" + String(cal.scaleZ, 4) + "}";
                ble.sendResponse(response);
            }
            break;

        case BleCommand::None:
            break;

        default:
            break;
    }
}

void broadcastSensorStatus() {
    if (!bleAvailable || !ble.isConnected())
        return;

    uint32_t now = millis();
    if ((now - lastStatusBroadcastTime) < statusBroadcastIntervalMs)
        return;

    lastStatusBroadcastTime = now;

    GpsData gpsData = gps.getData();
    ble.sendSensorStatus(gpsData, currentHeading);
}

void checkBleDisconnect() {
    if (ble.wasJustDisconnected()) {
        Serial.println("[Safety] BLE disconnected");
        
        if (isHoldActive) {
            Serial.println("[Safety] Stopping hold transmission");
            isHoldActive = false;
            if (remoteAvailable) {
                remote.transmitSingle(Button::Release);
            }
        }
        
        ble.clearDisconnectFlag();
    }
}

void setup() {
    Serial.begin(Config::serialBaud);
    delay(1000);

    Serial.println();
    Serial.println("=== Helm System Starting ===");
    Serial.println("=== SENSOR MODE: Provides GPS/Compass data only ===");
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
    Serial.println("[Helm] Setup complete - Awaiting app commands");
    Serial.println();
    Serial.println("Commands:");
    Serial.println("  Hold:    R/L/U/D/M/S (right/left/up/down/motor/momentary)");
    Serial.println("  Single:  r/l/u/d/m/s");
    Serial.println("  Release: 0");
    Serial.println("  GPS:     g (print status)");
    Serial.println("  GPS:     G (toggle debug output)");
    Serial.println("  Compass: c (print heading)");
    Serial.println("  Sensors: v (validation status)");
}

void loop() {
    if (gpsAvailable)
        gps.update();

    if (compassAvailable)
        currentHeading = compass.readHeading();

    if (bleAvailable) {
        ble.update();
        processBleCommand();
        processBleRfCommand();
        processHoldTransmission();
    }

    checkBleDisconnect();
    broadcastSensorStatus();

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

        case 'r': 
            Serial.println("[TEST] Manual RIGHT command");
            remote.transmitSingle(Button::Right); 
            break;
        case 'l': 
            Serial.println("[TEST] Manual LEFT command");
            remote.transmitSingle(Button::Left); 
            break;
        case 'u': 
            Serial.println("[TEST] Manual UP command");
            remote.transmitSingle(Button::Up); 
            break;
        case 'd': 
            Serial.println("[TEST] Manual DOWN command");
            remote.transmitSingle(Button::Down); 
            break;
        case 'm': 
            Serial.println("[TEST] Manual MOTOR command");
            remote.transmitSingle(Button::Motor); 
            break;
        case 's': 
            Serial.println("[TEST] Manual MOMENTARY command");
            remote.transmitSingle(Button::Momentary); 
            break;

        case '0': 
            Serial.println("[TEST] Manual RELEASE command");
            remote.transmitSingle(Button::Release); 
            break;

        case 'g': printGpsStatus(); break;
        case 'G': gps.setDebugEnabled(!gps.isDebugEnabled()); break;
        case 'c': printCompassHeading(); break;
        case 'v': printSensorStatus(); break;
    }
}