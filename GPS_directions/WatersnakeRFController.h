#ifndef WATERSNAKE_RF_CONTROLLER_H
#define WATERSNAKE_RF_CONTROLLER_H

#include <Arduino.h>

class WatersnakeRFController {
private:
    int txPin;
    
    void sendPulse(int highMicros, int lowMicros);
    void sendPattern1();
    void sendPattern2();

public:
    WatersnakeRFController(int transmitPin = D4);
    void sendRight(int repetitions = 3);
    void sendLeft(int repetitions = 3);
};

#endif