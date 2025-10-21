#include "WatersnakeRFController.h"

WatersnakeRFController::WatersnakeRFController(int transmitPin) {
    txPin = transmitPin;
    pinMode(txPin, OUTPUT);
    digitalWrite(txPin, LOW);
}

void WatersnakeRFController::sendPulse(int highMicros, int lowMicros) {
    digitalWrite(txPin, HIGH);
    delayMicroseconds(highMicros);
    digitalWrite(txPin, LOW);
    delayMicroseconds(lowMicros);
}

void WatersnakeRFController::sendPattern1() {
    for (int i = 0; i < 11; i++) sendPulse(408, 48);
    for (int i = 0; i < 5; i++) sendPulse(608, 64);
    for (int i = 0; i < 15; i++) sendPulse(144, 64);
    for (int i = 0; i < 6; i++) sendPulse(252, 48);
    sendPulse(776, 10000);
}

void WatersnakeRFController::sendPattern2() {
    for (int i = 0; i < 9; i++) sendPulse(232, 68);
    for (int i = 0; i < 24; i++) sendPulse(140, 68);
    for (int i = 0; i < 4; i++) sendPulse(348, 68);
    for (int i = 0; i < 5; i++) sendPulse(448, 68);
    sendPulse(1384, 68);
    sendPulse(660, 68);
    sendPulse(64, 13844);
}

void WatersnakeRFController::sendRight(int repetitions) {
    for (int i = 0; i < repetitions; i++) {
        sendPattern1();
        delay(50);
    }
}

void WatersnakeRFController::sendLeft(int repetitions) {
    for (int i = 0; i < repetitions; i++) {
        sendPattern2();
        delay(50);
    }
}