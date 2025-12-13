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
bool rmtAvailable = false;

// Test payload: preamble + sync (no device ID or command)
const char* testPayload = "2aaaaaaad391d391";

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
        Serial.print("[RMT] Initializing... ");
        rmtAvailable = remote.begin();
        Serial.println(rmtAvailable ? "SUCCESS" : "FAILED");
    }

    Serial.println();
    Serial.println("[Helm] Setup complete");
    Serial.println("[Helm] Commands: 't' = test TX carrier, 'm' = test Manchester");
}

void loop() {
    if (!Serial.available())
        return;

    char c = Serial.read();

    if (c == 't' && cc1101Available) {
        Serial.println("[TX] Test carrier 100ms");
        cc1101.startTx();
        delay(100);
        cc1101.stopTx();
        Serial.println("[TX] Done");
    }

    if (c == 'm' && rmtAvailable) {
        Serial.println("[TX] Test Manchester payload");
        remote.transmitPayload(testPayload);
        Serial.println("[TX] Done");
    }
}