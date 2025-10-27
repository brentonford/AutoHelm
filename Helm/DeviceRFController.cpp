/*
 * DeviceRFController.cpp
 * 
 * Implementation of device RF control library for 433MHz remote control
 */

#include "DeviceRFController.h"
#include <SPI.h>

const char* DeviceRFController::ENCRYPT_KEY = "sampleEncryptKey";

DeviceRFController::DeviceRFController() 
    : radio(RF_CS_PIN, RF_INT_PIN, IS_RFM69HCW), initialized(false) {
}

void DeviceRFController::testSPIPins() {
    pinMode(RF_CS_PIN, OUTPUT);
    digitalWrite(RF_CS_PIN, HIGH);
    delay(10);
    
    pinMode(RF_RST_PIN, OUTPUT);
    digitalWrite(RF_RST_PIN, HIGH);
    delay(10);
    
    pinMode(RF_INT_PIN, INPUT);
    
    SPI.begin();
}

uint8_t DeviceRFController::readRegisterDirect(uint8_t addr) {
    digitalWrite(RF_CS_PIN, LOW);
    delayMicroseconds(10);
    
    SPI.transfer(addr & 0x7F);
    uint8_t value = SPI.transfer(0x00);
    
    delayMicroseconds(10);
    digitalWrite(RF_CS_PIN, HIGH);
    
    return value;
}

void DeviceRFController::writeRegisterDirect(uint8_t addr, uint8_t value) {
    SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
    
    digitalWrite(RF_CS_PIN, LOW);
    delayMicroseconds(50);
    
    SPI.transfer(addr | 0x80);
    SPI.transfer(value);
    
    delayMicroseconds(50);
    digitalWrite(RF_CS_PIN, HIGH);
    
    SPI.endTransaction();
    delayMicroseconds(10);
}

void DeviceRFController::performModuleHealthCheck() {
    uint8_t version = readRegisterDirect(0x10);
    
    if (version != 0x24) {
        Serial.println("RFM69 communication failed");
        return;
    }
}

bool DeviceRFController::begin() {
    testSPIPins();
    
    pinMode(RF_RST_PIN, OUTPUT);
    digitalWrite(RF_RST_PIN, HIGH);
    delay(100);
    digitalWrite(RF_RST_PIN, LOW);
    delay(100);
    
    performModuleHealthCheck();
    
    if (!radio.initialize(FREQUENCY, NODEID, NETWORKID)) {
        Serial.println("RFM69 init failed");
        return false;
    }
    
    radio.setHighPower();
    radio.encrypt(ENCRYPT_KEY);
    
    pinMode(RF_INT_PIN, OUTPUT);
    digitalWrite(RF_INT_PIN, LOW);
    
    initialized = true;
    
    return true;
}

void DeviceRFController::sendPwmBit(bool bit) {
    if (bit) {
        digitalWrite(RF_INT_PIN, HIGH);
        delayMicroseconds(LONG_PULSE_US);
        digitalWrite(RF_INT_PIN, LOW);
        delayMicroseconds(SHORT_PULSE_US);
    } else {
        digitalWrite(RF_INT_PIN, HIGH);
        delayMicroseconds(SHORT_PULSE_US);
        digitalWrite(RF_INT_PIN, LOW);
        delayMicroseconds(LONG_PULSE_US);
    }
}

void DeviceRFController::sendSyncPulse() {
    digitalWrite(RF_INT_PIN, HIGH);
    delayMicroseconds(SYNC_PULSE_US);
    digitalWrite(RF_INT_PIN, LOW);
    delayMicroseconds(GAP_US);
}

void DeviceRFController::transmitCode(uint64_t codeHigh, uint64_t codeLow) {
    sendSyncPulse();
    
    for (int8_t i = 39; i >= 0; i--) {
        bool bit = (codeHigh >> i) & 1;
        sendPwmBit(bit);
    }
    
    for (int8_t i = 49; i >= 0; i--) {
        bool bit = (codeLow >> i) & 1;
        sendPwmBit(bit);
    }
    
    delay(2);
}

void DeviceRFController::transmitRight(uint8_t repeatCount) {
    if (!initialized) {
        Serial.println("Cannot transmit - RF controller not initialized");
        return;
    }
    
    Serial.print("Transmitting RIGHT command (");
    Serial.print(repeatCount);
    Serial.println(" repeats)");
    for (uint8_t i = 0; i < repeatCount; i++) {
        transmitCode(RIGHT_CODE_HIGH, RIGHT_CODE_LOW);
        delay(50);
    }
}

void DeviceRFController::transmitLeft(uint8_t repeatCount) {
    if (!initialized) {
        Serial.println("Cannot transmit - RF controller not initialized");
        return;
    }
    
    Serial.print("Transmitting LEFT command (");
    Serial.print(repeatCount);
    Serial.println(" repeats)");
    for (uint8_t i = 0; i < repeatCount; i++) {
        transmitCode(LEFT_CODE_HIGH, LEFT_CODE_LOW);
        delay(50);
    }
}

bool DeviceRFController::isInitialized() const {
    return initialized;
}