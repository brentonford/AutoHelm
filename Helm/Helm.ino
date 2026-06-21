#include "DataModels.h"
#include "CC1101.h"
#include "Remote.h"
#include "GpsManager.h"
#include "CompassManager.h"
#include "LIS3DHManager.h"
#include "BleManager.h"
#include "SpotLockController.h"
#include "WaypointNavController.h"
#include "HelmModeManager.h"

CC1101 cc1101(
    Pins::cc1101Cs,
    Pins::cc1101Sck,
    Pins::cc1101Miso,
    Pins::cc1101Mosi
);

Remote remote(cc1101, Pins::cc1101Gdo0);
GpsManager gps(Pins::gpsRx, Pins::gpsTx);
CompassManager compass(Pins::i2cSda, Pins::i2cScl);
LIS3DHManager accel;   // shares I2C bus with compass; begin() called after compass.begin()
BleManager ble;
SpotLockController spotLock(remote);
WaypointNavController waypointNav(remote);
HelmModeManager helmMode(gps, ble, spotLock, waypointNav);

bool cc1101Available  = false;
bool remoteAvailable  = false;
bool gpsAvailable     = false;
bool compassAvailable = false;
bool accelAvailable   = false;
bool bleAvailable     = false;

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

// Non-blocking one-shot RF burst for momentary BLE/serial commands
struct ManualBurstState {
    bool active = false;
    Button button = Button::Count;
    uint32_t holdStart = 0;
    uint32_t lastRetransmit = 0;
};
ManualBurstState manualBurst;
constexpr uint32_t manualBurstDurationMs = 1000;

// Emergency stop state machine (non-blocking)
enum class EmergencyStopState : uint8_t {
    Idle,
    HoldingDown,
    BetweenSteps,
    Complete
};
EmergencyStopState emergencyStopState = EmergencyStopState::Idle;
uint8_t emergencyStopCount = 0;
uint32_t emergencyStopPhaseStart = 0;
uint32_t emergencyStopLastRetransmit = 0;
constexpr uint32_t emergencyStopHoldMs = 1000;
constexpr uint32_t emergencyStopIntervalMs = 500;
constexpr uint8_t emergencyStopMaxCount = 10;
constexpr uint32_t emergencyStopRetransmitMs = 68;

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
    Serial.printf("  Tilt Comp (LIS3DH):%s\n", accelAvailable ? "YES" : "NO");
    Serial.printf("  BLE Available:     %s\n", bleAvailable ? "YES" : "NO");
    Serial.printf("  BLE Connected:     %s\n", ble.isConnected() ? "YES" : "NO");
}

void processNavCommand() {
    if (!ble.hasNavSettingsPending() && !ble.hasNavCommandPending()) return;

    if (ble.hasNavSettingsPending()) {
        SpotLockSettings settings = ble.consumeNavSettings();
        helmMode.applyNavSettings(settings);
    }

    if (!ble.hasNavCommandPending()) return;

    NavCommand cmd = ble.consumeNavCommand();
    switch (cmd) {
        case NavCommand::Start:
            if (remoteAvailable) {
                helmMode.requestNavStart(ble.getNavTargetLat(), ble.getNavTargetLon(),
                                         ble.getNavTargetSpeed());
            } else {
                ble.sendResponse("{\"error\":\"RF not available\"}");
            }
            break;
        case NavCommand::Cancel:
            helmMode.requestNavCancel();
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

    if (ble.hasSlSettingsPending()) {
        SpotLockSettings settings = ble.consumeSlSettings();
        helmMode.applySpotLockSettings(settings);
    }

    if (!ble.hasSpotLockCommandPending())
        return;

    SpotLockCommand cmd = ble.consumeSpotLockCommand();
    switch (cmd) {
        case SpotLockCommand::Engage:
            if (remoteAvailable) {
                helmMode.requestSpotLockEngage(ble.getSlEngageLat(), ble.getSlEngageLon());
            } else {
                ble.sendResponse("{\"error\":\"RF not available\"}");
            }
            break;

        case SpotLockCommand::Disengage:
            helmMode.requestSpotLockDisengage();
            break;

        case SpotLockCommand::Jog:
            if (helmMode.requestSpotLockJog(ble.getSlJogDir())) {
                ble.sendResponse("{\"ack\":\"SPOTLOCK_JOG\"}");
            }
            break;

        case SpotLockCommand::None:
            break;

        default:
            break;
    }
}

void startManualBurst(Button button) {
    if (!remoteAvailable) return;

    manualBurst.active = true;
    manualBurst.button = button;
    manualBurst.holdStart = millis();
    manualBurst.lastRetransmit = 0;
    remote.transmitSingle(button);
}

void processManualBurst() {
    if (!manualBurst.active || !remoteAvailable) return;

    uint32_t now = millis();
    if ((now - manualBurst.holdStart) >= manualBurstDurationMs) {
        remote.transmitSingle(Button::Release);
        manualBurst.active = false;
        manualBurst.button = Button::Count;
        return;
    }

    if (manualBurst.lastRetransmit == 0 ||
        (now - manualBurst.lastRetransmit) >= holdTransmitIntervalMs) {
        remote.transmitSingle(manualBurst.button);
        manualBurst.lastRetransmit = now;
    }
}

void processBleRfCommand() {
    if (!helmMode.allowsManualRf())
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
            startManualBurst(Button::Left);
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
            startManualBurst(Button::Right);
        }
    } else if (cmd == "UP") {
        startManualBurst(Button::Up);
    } else if (cmd == "DOWN") {
        startManualBurst(Button::Down);
    } else if (cmd == "MOTOR") {
        startManualBurst(Button::Motor);
    } else if (cmd == "MOMENTARY") {
        startManualBurst(Button::Momentary);
    } else if (cmd == "RELEASE") {
        portENTER_CRITICAL(&holdStateMux);
        isHoldActive = false;
        portEXIT_CRITICAL(&holdStateMux);
        manualBurst.active = false;
        remote.transmitSingle(Button::Release);
        Serial.println("[BLE] Stopping hold transmission");
    }
}

void processHoldTransmission() {
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
    ble.sendSensorStatus(gpsData, currentHeading, spotLock.getState(), waypointNav.getState(),
                         helmMode.getHelmState());
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

void startEmergencyStop() {
    if (!remoteAvailable) {
        Serial.println("[Safety] Cannot perform emergency stop - RF not available");
        return;
    }

    if (emergencyStopState != EmergencyStopState::Idle &&
        emergencyStopState != EmergencyStopState::Complete) {
        return;
    }

    Serial.println("[Safety] EMERGENCY STOP - BLE Disconnected");
    Serial.println("[Safety] Sending 10 RF_DOWN commands to reduce speed to 0");

    emergencyStopState = EmergencyStopState::HoldingDown;
    emergencyStopCount = 0;
    emergencyStopPhaseStart = 0;
    emergencyStopLastRetransmit = 0;
}

void processEmergencyStop() {
    if (emergencyStopState == EmergencyStopState::Idle ||
        emergencyStopState == EmergencyStopState::Complete) {
        return;
    }

    if (!remoteAvailable) {
        emergencyStopState = EmergencyStopState::Idle;
        return;
    }

    uint32_t now = millis();

    switch (emergencyStopState) {
        case EmergencyStopState::HoldingDown:
            if (emergencyStopPhaseStart == 0) {
                emergencyStopPhaseStart = now;
                emergencyStopLastRetransmit = 0;
                remote.transmitSingle(Button::Down);
            }

            if ((now - emergencyStopPhaseStart) >= emergencyStopHoldMs) {
                remote.transmitSingle(Button::Release);
                emergencyStopCount++;
                Serial.printf("[Safety] Emergency stop %d/%d\n",
                              emergencyStopCount, emergencyStopMaxCount);
                emergencyStopPhaseStart = now;
                emergencyStopState = EmergencyStopState::BetweenSteps;
                break;
            }

            if (emergencyStopLastRetransmit == 0 ||
                (now - emergencyStopLastRetransmit) >= emergencyStopRetransmitMs) {
                remote.transmitSingle(Button::Down);
                emergencyStopLastRetransmit = now;
            }
            break;

        case EmergencyStopState::BetweenSteps:
            if ((now - emergencyStopPhaseStart) >= emergencyStopIntervalMs) {
                if (emergencyStopCount >= emergencyStopMaxCount) {
                    emergencyStopState = EmergencyStopState::Complete;
                    Serial.println("[Safety] Emergency stop complete - speed should be 0");
                } else {
                    emergencyStopState = EmergencyStopState::HoldingDown;
                    emergencyStopPhaseStart = 0;
                }
            }
            break;

        default:
            break;
    }
}

void checkBleDisconnect() {
    if (ble.wasJustDisconnected()) {
        Serial.println("[Safety] BLE disconnected");

        if (helmMode.isAutonomousActive()) {
            Serial.println("[Safety] Autonomous control active – continuing operation");
        } else {
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

            manualBurst.active = false;
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

    Serial.print("[LIS3DH] Initializing... ");
    accelAvailable = accel.begin();
    Serial.println(accelAvailable ? "SUCCESS" : "FAILED (tilt compensation disabled)");

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

    if (compassAvailable) {
        if (accelAvailable) {
            float ax, ay, az;
            if (accel.readAccel(ax, ay, az)) {
                float pitchRad = atan2f(-ax, sqrtf(ay * ay + az * az));
                float rollRad  = atan2f(ay, az);
                currentHeading = compass.readHeadingTilted(pitchRad, rollRad);
            } else {
                currentHeading = compass.readHeading();
            }
        } else {
            currentHeading = compass.readHeading();
        }
    }

    if (remoteAvailable) {
        helmMode.update(gps.getData(), currentHeading);
    }

    if (bleAvailable) {
        ble.update();
        processBleCommand();
        processSpotLockCommand();
        processNavCommand();
        processBleRfCommand();
        processManualBurst();
        processHoldTransmission();
        streamCalibrationData();
    }

    checkBleDisconnect();
    processEmergencyStop();
    broadcastSensorStatus();

    if (!Serial.available())
        return;

    char c = Serial.read();

    switch (c) {
        case 'R': startManualBurst(Button::Right); break;
        case 'L': startManualBurst(Button::Left); break;
        case 'U': startManualBurst(Button::Up); break;
        case 'D': startManualBurst(Button::Down); break;
        case 'M': startManualBurst(Button::Motor); break;
        case 'S': startManualBurst(Button::Momentary); break;

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