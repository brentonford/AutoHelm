#include "DataModels.h"
#include "CC1101.h"
#include "Remote.h"
#include "GpsManager.h"

CC1101 cc1101(
    Pins::cc1101Cs,
    Pins::cc1101Sck,
    Pins::cc1101Miso,
    Pins::cc1101Mosi
);

Remote remote(cc1101, Pins::cc1101Gdo0);

GpsManager gps(Pins::gpsRx, Pins::gpsTx);

bool cc1101Available = false;
bool remoteAvailable = false;
bool gpsAvailable = false;

uint32_t lastGpsPrint = 0;
constexpr uint32_t gpsPrintInterval = 2000;

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

    Serial.println();
    Serial.println("[Helm] Setup complete");
    Serial.println();
    Serial.println("Commands:");
    Serial.println("  Hold:   R/L/U/D/M/S (right/left/up/down/motor/momentary)");
    Serial.println("  Single: r/l/u/d/m/s");
    Serial.println("  Release: 0");
    Serial.println("  GPS:    g (print status)");
}

void loop() {
    if (gpsAvailable)
        gps.update();

    if (Serial.available()) {
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
        }
    }
}