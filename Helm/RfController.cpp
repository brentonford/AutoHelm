#include "RfController.h"

#define BURST_DURATION_MS 14
#define BURST_GAP_MS 54
#define BURST_COUNT 4

RfController::RfController(uint8_t csPin, uint8_t rstPin) 
    : csPin(csPin), rstPin(rstPin), initialized(false) {}

void RfController::writeRegister(uint8_t addr, uint8_t value) {
    SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
    digitalWrite(csPin, LOW);
    delayMicroseconds(10);
    SPI.transfer(addr | 0x80);
    SPI.transfer(value);
    delayMicroseconds(10);
    digitalWrite(csPin, HIGH);
    SPI.endTransaction();
    delayMicroseconds(10);
}

uint8_t RfController::readRegister(uint8_t addr) {
    SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0));
    digitalWrite(csPin, LOW);
    delayMicroseconds(10);
    SPI.transfer(addr & 0x7F);
    uint8_t value = SPI.transfer(0x00);
    delayMicroseconds(10);
    digitalWrite(csPin, HIGH);
    SPI.endTransaction();
    return value;
}

void RfController::configureFskMode() {
    writeRegister(0x01, 0x04);
    delay(10);
    
    writeRegister(0x02, 0x00);
    delay(1);
    
    writeRegister(0x07, 0x6C);
    delay(1);
    writeRegister(0x08, 0x7A);
    delay(1);
    writeRegister(0x09, 0xE1);
    delay(1);
    
    writeRegister(0x03, 0x01);
    delay(1);
    writeRegister(0x04, 0x40);
    delay(1);
    
    writeRegister(0x05, 0x0C);
    delay(1);
    writeRegister(0x06, 0x35);
    delay(1);
    
    writeRegister(0x19, 0x42);
    delay(1);
    writeRegister(0x1A, 0x90);
    delay(1);
    
    writeRegister(0x11, 0x9F);
    delay(1);
    writeRegister(0x12, 0x09);
    delay(1);
    
    writeRegister(0x6F, 0x30);
    delay(10);
}

bool RfController::begin() {
    Serial.println("[RF] Resetting RFM69...");
    pinMode(rstPin, OUTPUT);
    digitalWrite(rstPin, HIGH);
    delay(10);
    digitalWrite(rstPin, LOW);
    delay(10);
    digitalWrite(rstPin, HIGH);
    delay(100);
    
    Serial.println("[RF] Initializing SPI...");
    SPI.begin();
    pinMode(csPin, OUTPUT);
    digitalWrite(csPin, HIGH);
    delay(10);
    
    Serial.println("[RF] Waiting for chip ready...");
    uint8_t timeout = 0;
    while (timeout < 50) {
        uint8_t opmode = readRegister(0x01);
        Serial.print("[RF] OpMode poll: 0x");
        Serial.println(opmode, HEX);
        
        if (opmode != 0x00 && opmode != 0xFF) {
            Serial.println("[RF] Chip ready");
            break;
        }
        
        delay(10);
        timeout++;
    }
    
    if (timeout >= 50) {
        Serial.println("[RF] Chip not ready after reset");
    }
    
    Serial.println("[RF] Checking version...");
    uint8_t version = readRegister(0x10);
    Serial.print("[RF] Version: 0x");
    Serial.println(version, HEX);
    
    if (version != 0x24) {
        Serial.println("[RF] ERROR: Wrong version");
        return false;
    }
    
    Serial.println("[RF] Forcing standby mode...");
    for (int i = 0; i < 10; i++) {
        writeRegister(0x01, 0x04);
        delay(10);
        uint8_t opmode = readRegister(0x01);
        Serial.print("[RF] OpMode attempt ");
        Serial.print(i + 1);
        Serial.print(": 0x");
        Serial.println(opmode, HEX);
        
        if (opmode == 0x04) {
            Serial.println("[RF] Standby mode confirmed");
            break;
        }
    }
    
    Serial.println("[RF] Configuring FSK mode...");
    configureFskMode();
    
    Serial.println("[RF] Verifying config...");
    Serial.print("[RF] OpMode: 0x");
    Serial.println(readRegister(0x01), HEX);
    Serial.print("[RF] Freq: 0x");
    Serial.print(readRegister(0x07), HEX);
    Serial.print(" 0x");
    Serial.print(readRegister(0x08), HEX);
    Serial.print(" 0x");
    Serial.println(readRegister(0x09), HEX);
    
    uint8_t finalOpMode = readRegister(0x01);
    if (finalOpMode == 0x00) {
        Serial.println("[RF] ERROR: Still in sleep mode");
        return false;
    }
    
    initialized = true;
    Serial.println("[RF] Initialization complete");
    return true;
}

void RfController::transmitBurstPattern(uint8_t repeatCount) {
    if (!initialized) return;
    
    for (uint8_t repeat = 0; repeat < repeatCount; repeat++) {
        writeRegister(0x01, 0x0C);
        delay(BURST_DURATION_MS);
        writeRegister(0x01, 0x04);
        
        if (repeat < repeatCount - 1) {
            delay(BURST_GAP_MS);
        }
    }
}

void RfController::transmitSimpleBurst() {
    transmitBurstPattern(BURST_COUNT);
}

void RfController::transmitRightButton() {
    Serial.println("[RF] TX: Right button");
    transmitBurstPattern(BURST_COUNT);
}

void RfController::transmitLeftButton() {
    Serial.println("[RF] TX: Left button");
    transmitBurstPattern(BURST_COUNT);
}

bool RfController::isInitialized() {
    return initialized;
}

void RfController::printDebugInfo() {
    Serial.println("[RF] === Debug Info ===");
    Serial.print("[RF] Version: 0x");
    Serial.println(readRegister(0x10), HEX);
    Serial.print("[RF] OpMode: 0x");
    Serial.println(readRegister(0x01), HEX);
    Serial.print("[RF] DataModul: 0x");
    Serial.println(readRegister(0x02), HEX);
    Serial.print("[RF] Freq: 0x");
    Serial.print(readRegister(0x07), HEX);
    Serial.print(" 0x");
    Serial.print(readRegister(0x08), HEX);
    Serial.print(" 0x");
    Serial.println(readRegister(0x09), HEX);
    Serial.print("[RF] PA Level: 0x");
    Serial.println(readRegister(0x11), HEX);
}