#include "DataModels.h"

void setup() {
    Serial.begin(Config::serialBaud);
    delay(1000);

    Serial.println();
    Serial.println("=== Helm System Starting ===");
    Serial.println();

    Serial.println("[Config] Pin assignments:");
    Serial.printf("  CC1101 CS:   GPIO %d\n", Pins::cc1101Cs);
    Serial.printf("  CC1101 GDO0: GPIO %d\n", Pins::cc1101Gdo0);
    Serial.printf("  CC1101 SCK:  GPIO %d\n", Pins::cc1101Sck);
    Serial.printf("  CC1101 MISO: GPIO %d\n", Pins::cc1101Miso);
    Serial.printf("  CC1101 MOSI: GPIO %d\n", Pins::cc1101Mosi);
    Serial.printf("  GPS RX:      GPIO %d\n", Pins::gpsRx);
    Serial.printf("  GPS TX:      GPIO %d\n", Pins::gpsTx);
    Serial.printf("  I2C SDA:     GPIO %d\n", Pins::i2cSda);
    Serial.printf("  I2C SCL:     GPIO %d\n", Pins::i2cScl);
    Serial.println();

    Serial.println("[Helm] Setup complete");
}

void loop() {
}