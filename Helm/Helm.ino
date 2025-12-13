#include "DataModels.h"
#include "CC1101.h"
#include "Remote.h"

CC1101 cc1101(
    Pins::cc1101Cs,
    Pins::cc1101Sck,
    Pins::cc1101Miso,
    Pins::cc1101Mosi
);

Remote remote(cc1101, Pins::cc1101Gdo0);

bool cc1101Available = false;
bool remoteAvailable = false;

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

    Serial.println();
    Serial.println("[Helm] Setup complete");
    Serial.println();
    Serial.println("Commands:");
    Serial.println("  Hold:   R/L/U/D/M/S (right/left/up/down/motor/momentary)");
    Serial.println("  Single: r/l/u/d/m/s");
    Serial.println("  Release: 0");
}

void loop() {
    if (!Serial.available())
        return;

    if (!remoteAvailable)
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
    }
}