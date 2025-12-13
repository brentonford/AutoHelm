#include "DataModels.h"
#include "CC1101.h"

CC1101 cc1101(
    Pins::cc1101Cs,
    Pins::cc1101Sck,
    Pins::cc1101Miso,
    Pins::cc1101Mosi
);

bool cc1101Available = false;

void setup() {
    Serial.begin(Config::serialBaud);
    delay(1000);

    Serial.println();
    Serial.println("=== Helm System Starting ===");
    Serial.println();

    Serial.print("[CC1101] Initializing... ");
    cc1101Available = cc1101.begin();
    Serial.println(cc1101Available ? "SUCCESS" : "FAILED");

    if (!cc1101Available) {
        Serial.println("[CC1101] Check wiring and power (3.3V only)");
    }

    Serial.println();
    Serial.println("[Helm] Setup complete");
}

void loop() {
}