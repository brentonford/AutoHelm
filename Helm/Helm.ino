#include "DataModels.h"
#include "CC1101.h"
#include "Remote.h"
#include "GpsManager.h"
#include "CompassManager.h"
#include "BleManager.h"
#include "SpotLockController.h"
#include "WaypointNavController.h"

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
SpotLockController spotLock(remote);
WaypointNavController waypointNav(remote);

bool cc1101Available = false;
bool remoteAvailable = false;
bool gpsAvailable = false;
bool compassAvailable = false;
bool bleAvailable = false;

float currentHeading = 0.0f;
uint32_t lastStatusBroadcastTime = 0;
constexpr uint32_t statusBroadcastIntervalMs = 500;

// Hold button state - protected by mutex for thread safety between BLE callback and main loop
portMUX_TYPE holdStateMux = portMUX_INITIALIZER_UNLOCKED;
volatile Button activeHoldButton = Button::Count;
volatile bool isHoldActive = false;
volatile uint32_t lastHoldTransmitTime = 0;
volatile uint32_t holdStartTime = 0;
constexpr uint32_t holdTransmitIntervalMs = 68;
constexpr uint32_t holdTransmitTimeoutMs = 30000;

// Emergency stop state machine (non-blocking)
enum class EmergencyStopState : uint8_t {
    Idle,
    InProgress,
    Complete
};
volatile EmergencyStopState emergencyStopState = EmergencyStopState::Idle;
volatile uint8_t emergencyStopCount = 0;
volatile uint32_t lastEmergencyStopTime = 0;
constexpr uint32_t emergencyStopIntervalMs = 500;
constexpr uint8_t emergencyStopMaxCount = 10;

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

void processNavCommand() {
    if (!ble.hasNavCommandPending()) return;

    NavCommand cmd = ble.consumeNavCommand();
    switch (cmd) {
        case NavCommand::Start:
            if (remoteAvailable) {
                spotLock.disengage();  // safety: cancel SpotLock if active
                waypointNav.start(ble.getNavTargetLat(), ble.getNavTargetLon(),
                                  ble.getNavTargetSpeed());
                ble.sendResponse("{\"ack\":\"NAV_STARTED\"}");
            } else {
                ble.sendResponse("{\"error\":\"RF not available\"}");
            }
            break;
        case NavCommand::Cancel:
            waypointNav.cancel();
            ble.sendResponse("{\"ack\":\"NAV_CANCELLED\"}");
            break;
        case NavCommand::None:
            break;
        default:
            break;
    }
}

void processSpotLockCommand() {
    if (!ble.hasSpotLockCommandPending() && !ble.hasSlSettingsPending())
        return;

    // Apply settings to both controllers before engage
    if (ble.hasSlSettingsPending()) {
        SpotLockSettings settings = ble.consumeSlSettings();
        spotLock.applySettings(settings);
        waypointNav.applySettings(settings);
    }

    if (!ble.hasSpotLockCommandPending())
        return;

    SpotLockCommand cmd = ble.consumeSpotLockCommand();
    switch (cmd) {
        case SpotLockCommand::Engage:
            if (remoteAvailable) {
                spotLock.engage(ble.getSlEngageLat(), ble.getSlEngageLon());
                ble.sendResponse("{\"ack\":\"SPOTLOCK_ENGAGED\"}");
            } else {
                ble.sendResponse("{\"error\":\"RF not available\"}");
            }
            break;

        case SpotLockCommand::Disengage:
            spotLock.disengage();
            ble.sendResponse("{\"ack\":\"SPOTLOCK_DISENGAGED\"}");
            break;

        case SpotLockCommand::Jog:
            spotLock.jog(ble.getSlJogDir());
            break;

        case SpotLockCommand::None:
            break;

        default:
            break;
    }
}

void processBleRfCommand() {
    // Manual RF commands are blocked while SpotLock or navigation is active
    if (spotLock.isActive() || waypointNav.isActive())
        return;

    if (!ble.hasRfCommandPending())
        return;

    if (!remoteAvailable)
        return;

    bool isHold = ble.isRfHoldCommand();
    String cmd = ble.consumeRfCommand();
    Serial.printf("[BLE] RF Command: %s (Hold: %s)\n", cmd.c_str(), isHold ? "YES" : "NO");

    if (cmd == "LEFT") {
        if (isHold) {
            portENTER_CRITICAL(&holdStateMux);
            activeHoldButton = Button::Left;
            isHoldActive = true;
            holdStartTime = millis();
            lastHoldTransmitTime = millis();
            portEXIT_CRITICAL(&holdStateMux);
            Serial.println("[BLE] Starting LEFT hold transmission");
            remote.transmitSingle(Button::Left);
        } else {
            remote.transmitHold(Button::Left, 1000);
        }
    } else if (cmd == "RIGHT") {
        if (isHold) {
            portENTER_CRITICAL(&holdStateMux);
            activeHoldButton = Button::Right;
            isHoldActive = true;
            holdStartTime = millis();
            lastHoldTransmitTime = millis();
            portEXIT_CRITICAL(&holdStateMux);
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
        portENTER_CRITICAL(&holdStateMux);
        isHoldActive = false;
        portEXIT_CRITICAL(&holdStateMux);
        remote.transmitSingle(Button::Release);
        Serial.println("[BLE] Stopping hold transmission");
    }
}

void processHoldTransmission() {
    // Read state atomically
    portENTER_CRITICAL(&holdStateMux);
    bool holdActive = isHoldActive;
    Button holdButton = activeHoldButton;
    uint32_t startTime = holdStartTime;
    uint32_t lastTransmit = lastHoldTransmitTime;
    portEXIT_CRITICAL(&holdStateMux);

    if (!holdActive || !remoteAvailable)
        return;

    uint32_t now = millis();

    if ((now - startTime) >= holdTransmitTimeoutMs) {
        Serial.println("[Safety] Hold transmission timeout - releasing");
        portENTER_CRITICAL(&holdStateMux);
        isHoldActive = false;
        portEXIT_CRITICAL(&holdStateMux);
        remote.transmitSingle(Button::Release);
        return;
    }

    if (lastTransmit == 0 || (now - lastTransmit) >= holdTransmitIntervalMs) {
        remote.transmitSingle(holdButton);
        portENTER_CRITICAL(&holdStateMux);
        lastHoldTransmitTime = now;
        portEXIT_CRITICAL(&holdStateMux);
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
    
    if (ble.hasCalibrationPending()) {
        CompassCalibration cal = ble.consumeCalibration();
        compass.setCalibration(cal);
        Serial.println("[BLE] Calibration values applied to compass");
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
    ble.sendSensorStatus(gpsData, currentHeading, spotLock.getState(), waypointNav.getState());
}

void streamCalibrationData() {
    if (!bleAvailable || !ble.isConnected())
        return;
    
    if (!compassAvailable)
        return;
    
    if (!compass.isCalibrating())
        return;
    
    if (!compass.shouldStreamCalibrationData())
        return;
    
    String calibrationJson = compass.getCalibrationJson();
    ble.sendCalibrationData(calibrationJson);
    compass.markCalibrationDataSent();
}

// Initiates the non-blocking emergency stop sequence
void startEmergencyStop() {
    if (!remoteAvailable) {
        Serial.println("[Safety] Cannot perform emergency stop - RF not available");
        return;
    }

    if (emergencyStopState != EmergencyStopState::Idle) {
        return;  // Already in progress
    }

    Serial.println("[Safety] EMERGENCY STOP - BLE Disconnected");
    Serial.println("[Safety] Sending 10 RF_DOWN commands to reduce speed to 0");

    emergencyStopState = EmergencyStopState::InProgress;
    emergencyStopCount = 0;
    lastEmergencyStopTime = 0;
}

// Processes emergency stop state machine (non-blocking)
void processEmergencyStop() {
    if (emergencyStopState != EmergencyStopState::InProgress)
        return;

    if (!remoteAvailable) {
        emergencyStopState = EmergencyStopState::Idle;
        return;
    }

    uint32_t now = millis();

    if (lastEmergencyStopTime == 0 || (now - lastEmergencyStopTime) >= emergencyStopIntervalMs) {
        emergencyStopCount++;
        remote.transmitHold(Button::Down, 1000);
        Serial.printf("[Safety] Emergency stop %d/%d\n", emergencyStopCount, emergencyStopMaxCount);
        lastEmergencyStopTime = now;

        if (emergencyStopCount >= emergencyStopMaxCount) {
            emergencyStopState = EmergencyStopState::Complete;
            Serial.println("[Safety] Emergency stop complete - speed should be 0");
        }
    }
}

void checkBleDisconnect() {
    if (ble.wasJustDisconnected()) {
        Serial.println("[Safety] BLE disconnected");

        if (spotLock.isActive() || waypointNav.isActive()) {
            // Autonomous control is active – continue without emergency stop
            Serial.println("[Safety] Autonomous control active – continuing operation");
        } else {
            // No autonomous control – apply safety stop for any manual hold
            portENTER_CRITICAL(&holdStateMux);
            bool wasHoldActive = isHoldActive;
            isHoldActive = false;
            portEXIT_CRITICAL(&holdStateMux);

            if (wasHoldActive) {
                Serial.println("[Safety] Stopping manual hold transmission");
                if (remoteAvailable) {
                    remote.transmitSingle(Button::Release);
                }
            }

            startEmergencyStop();
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
    Serial.println("  Compass: C (toggle debug output)");
    Serial.println("  Sensors: v (validation status)");
}

void loop() {
    if (gpsAvailable)
        gps.update();

    if (compassAvailable)
        currentHeading = compass.readHeading();

    // SpotLock and WaypointNav run every loop iteration for precise timing
    if (remoteAvailable) {
        spotLock.update(gps.getData(), currentHeading);

        if (waypointNav.isActive()) {
            bool arrived = waypointNav.update(gps.getData(), currentHeading);
            if (arrived) {
                // Seamless handoff: nav ends, SpotLock holds the target position
                float tLat = waypointNav.getState().targetLat;
                float tLon = waypointNav.getState().targetLon;
                Serial.printf("[Helm] NAV arrived – engaging SpotLock at %.6f,%.6f\n", tLat, tLon);
                waypointNav.cancel();
                spotLock.engage(tLat, tLon);
                ble.sendResponse("{\"ack\":\"NAV_ARRIVED\"}");
            }
        }
    }

    if (bleAvailable) {
        ble.update();
        processBleCommand();
        processSpotLockCommand();
        processNavCommand();
        processBleRfCommand();        // blocked when SpotLock or nav active
        processHoldTransmission();    // manual BLE holds (only when both inactive)
        streamCalibrationData();
    }

    checkBleDisconnect();
    processEmergencyStop();
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

        case 'r': remote.transmitSingle(Button::Right); break;
        case 'l': remote.transmitSingle(Button::Left); break;
        case 'u': remote.transmitSingle(Button::Up); break;
        case 'd': remote.transmitSingle(Button::Down); break;
        case 'm': remote.transmitSingle(Button::Motor); break;
        case 's': remote.transmitSingle(Button::Momentary); break;

        case '0': remote.transmitSingle(Button::Release); break;

        case 'g': printGpsStatus(); break;
        case 'G': gps.setDebugEnabled(!gps.isDebugEnabled()); break;
        case 'c': printCompassHeading(); break;
        case 'C': compass.setDebugEnabled(!compass.isDebugEnabled()); break;
        case 'v': printSensorStatus(); break;
    }
}