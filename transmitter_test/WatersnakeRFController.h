#ifndef WATERSNAKE_RF_CONTROLLER_H
#define WATERSNAKE_RF_CONTROLLER_H

#include <Arduino.h>

class WatersnakeRFController {
private:
    int txPin;
    static const int SHORT_PULSE = 52;
    static const int LONG_PULSE = 104;
    static const int GAP = 52;
    static const int SYNC_PULSE = 172;
    
    void sendBit(bool bit);
    void sendCode(const char* hexCode);

public:
    WatersnakeRFController(int transmitPin = 4);
    void sendRight(int repetitions = 3);
    void sendLeft(int repetitions = 3);
};

#endif