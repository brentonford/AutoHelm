#include "WatersnakeRFController.h"

WatersnakeRFController remote(7);

void setup() {
    Serial.begin(9600);
    delay(2000);
    Serial.println("Starting RF Test");
}

void loop() {
    Serial.println("Sending RIGHT");
    remote.sendRight(1);
    delay(3000);
    
    Serial.println("Sending LEFT");
    remote.sendLeft(1);
    delay(3000);
}