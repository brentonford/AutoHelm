/*
 * WatersnakeRFController.cpp
 * 
 * Implementation of Watersnake RF control library
 */

#include "WatersnakeRFController.h"
#include <SPI.h>

WatersnakeRFController::WatersnakeRFController() 
    : rf69(RF_CS_PIN, RF_INT_PIN), initialized(false) {
}

bool WatersnakeRFController::begin() {
    pinMode(RF_RST_PIN, OUTPUT);
    digitalWrite(RF_RST_PIN, LOW);
    delay(10);
    digitalWrite(RF_RST_PIN, HIGH);
    delay(10);
    
    if (!rf69.init()) {
        return false;
    }
    
    if (!rf69.setFrequency(FREQUENCY)) {
        return false;
    }
    
    rf69.setModemConfig(RH_RF69::FSK_Rb2Fd5);
    
    uint16_t fdevReg = (uint16_t)((FREQ_DEVIATION * 1000.0) / 61.035);
    rf69.spiWrite(RH_RF69_REG_05_FDEVMSB, fdevReg >> 8);
    rf69.spiWrite(RH_RF69_REG_06_FDEVLSB, fdevReg & 0xFF);
    
    uint16_t bitrateReg = (uint16_t)(32000000.0 / BITRATE);
    rf69.spiWrite(RH_RF69_REG_03_BITRATEMSB, bitrateReg >> 8);
    rf69.spiWrite(RH_RF69_REG_04_BITRATELSB, bitrateReg & 0xFF);
    
    rf69.setTxPower(20, true);
    
    rf69.spiWrite(RH_RF69_REG_37_PACKETCONFIG1, 0x00);
    rf69.spiWrite(RH_RF69_REG_6F_TESTDAGC, 0x30);
    
    pinMode(RF_INT_PIN, OUTPUT);
    digitalWrite(RF_INT_PIN, LOW);
    
    initialized = true;
    return true;
}

void WatersnakeRFController::sendPwmBit(bool bit) {
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

void WatersnakeRFController::sendSyncPulse() {
    digitalWrite(RF_INT_PIN, HIGH);
    delayMicroseconds(SYNC_PULSE_US);
    digitalWrite(RF_INT_PIN, LOW);
    delayMicroseconds(GAP_US);
}

void WatersnakeRFController::transmitCode(uint64_t codeHigh, uint64_t codeLow) {
    rf69.setModeTx();
    delay(1);
    
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
    rf69.setModeIdle();
}

void WatersnakeRFController::transmitRight(uint8_t repeatCount) {
    if (!initialized) {
        return;
    }
    
    for (uint8_t i = 0; i < repeatCount; i++) {
        transmitCode(RIGHT_CODE_HIGH, RIGHT_CODE_LOW);
        delay(50);
    }
}

void WatersnakeRFController::transmitLeft(uint8_t repeatCount) {
    if (!initialized) {
        return;
    }
    
    for (uint8_t i = 0; i < repeatCount; i++) {
        transmitCode(LEFT_CODE_HIGH, LEFT_CODE_LOW);
        delay(50);
    }
}

bool WatersnakeRFController::isInitialized() const {
    return initialized;
}