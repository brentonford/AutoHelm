#include "WatersnakeRFController.h"

WatersnakeRFController::WatersnakeRFController(int transmitPin) {
    txPin = transmitPin;
    pinMode(txPin, OUTPUT);
    digitalWrite(txPin, LOW);
    delay(100);
}

void WatersnakeRFController::sendBit(bool bit) {
    int pulseWidth = bit ? LONG_PULSE : SHORT_PULSE;
    
    digitalWrite(txPin, HIGH);
    delayMicroseconds(pulseWidth);
    digitalWrite(txPin, LOW);
    delayMicroseconds(GAP);
}

void WatersnakeRFController::sendCode(const char* hexCode) {
    if (hexCode == nullptr) return;
    
    digitalWrite(txPin, HIGH);
    delayMicroseconds(SYNC_PULSE);
    digitalWrite(txPin, LOW);
    delayMicroseconds(GAP);
    
    int hexLen = 0;
    while (hexCode[hexLen] != '\0' && hexLen < 100) {
        hexLen++;
    }
    
    for (int i = 0; i < hexLen; i++) {
        char c = hexCode[i];
        uint8_t nibble;
        
        if (c >= '0' && c <= '9') {
            nibble = c - '0';
        } else if (c >= 'a' && c <= 'f') {
            nibble = c - 'a' + 10;
        } else if (c >= 'A' && c <= 'F') {
            nibble = c - 'A' + 10;
        } else {
            continue;
        }
        
        for (int bit = 3; bit >= 0; bit--) {
            sendBit((nibble >> bit) & 1);
        }
    }
}

void WatersnakeRFController::sendRight(int repetitions) {
    const char* rightCode = "8000576d76f7e077723ba90";
    
    for (int i = 0; i < repetitions; i++) {
        sendCode(rightCode);
        delay(50);
    }
}

void WatersnakeRFController::sendLeft(int repetitions) {
    const char* leftCode = "8000576d76f7e077723ea84";
    
    for (int i = 0; i < repetitions; i++) {
        sendCode(leftCode);
        delay(50);
    }
}