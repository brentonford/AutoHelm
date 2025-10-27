#ifndef RF_CONTROLLER_H
#define RF_CONTROLLER_H

#include <Arduino.h>
#include <SPI.h>

class RfController {
public:
    RfController(uint8_t csPin, uint8_t rstPin);
    
    bool begin();
    void transmitRightButton();
    void transmitLeftButton();
    void transmitSimpleBurst();
    bool isInitialized();
    void printDebugInfo();
    
private:
    uint8_t csPin;
    uint8_t rstPin;
    bool initialized;
    
    void writeRegister(uint8_t addr, uint8_t value);
    uint8_t readRegister(uint8_t addr);
    void configureFskMode();
    void transmitBurstPattern(uint8_t repeatCount);
};

#endif