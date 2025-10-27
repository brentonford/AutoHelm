/*
 * DeviceRFController.h
 * 
 * Library for controlling remote devices via 433MHz RF transmission
 * using RFM69HCW radio module
 * 
 * Signal Parameters (from RTL-SDR analysis):
 * - Frequency: 433.032 MHz
 * - Modulation: FSK with PWM encoding
 * - Deviation: 22.5 kHz
 * - Bit rate: 6400 bps
 * 
 * Hardware Requirements:
 * - Arduino UNO R4 (or compatible)
 * - Adafruit RFM69HCW 433MHz Breakout
 * - RFM69 library by Felix Rusu
  * 
 * Wiring:
 * RFM69HCW -> Arduino UNO R4
 * VIN      -> 5V
 * GND      -> GND
 * SCK      -> D13 (SCK)
 * MISO     -> D12 (MISO)
 * MOSI     -> D11 (MOSI)
 * CS       -> D10
 * RST      -> D9
 * G0/DIO0  -> D8
 * ANT      -> 433MHz spring antenna
 * 
 * Serial Commands:
 * 'R' or 'r' - Transmit RIGHT command
 * 'L' or 'l' - Transmit LEFT command
 */

#ifndef DEVICE_RF_CONTROLLER_H
#define DEVICE_RF_CONTROLLER_H

#include <Arduino.h>
#include <RFM69.h>

class DeviceRFController {
public:
    DeviceRFController();
    
    bool begin();
    void transmitRight(uint8_t repeatCount = 3);
    void transmitLeft(uint8_t repeatCount = 3);
    bool isInitialized() const;
    void testSPIPins();
    void performModuleHealthCheck();

private:
    static const uint8_t RF_CS_PIN = 10;
    static const uint8_t RF_RST_PIN = 9;
    static const uint8_t RF_INT_PIN = 8;
    static const uint8_t SCK_PIN = 13;
    static const uint8_t MISO_PIN = 12;
    static const uint8_t MOSI_PIN = 11;
    
    static const uint8_t NODEID = 2;
    static const uint8_t NETWORKID = 100;
    static const uint8_t FREQUENCY = RF69_433MHZ;
    static const char* ENCRYPT_KEY;
    static const bool IS_RFM69HCW = true;
    
    static const uint8_t SHORT_PULSE_US = 50;
    static const uint8_t LONG_PULSE_US = 102;
    static const uint8_t SYNC_PULSE_US = 170;
    static const uint8_t GAP_US = 114;
    
    static const uint8_t DATA_BITS = 90;
    
    static const uint64_t RIGHT_CODE_HIGH = 0x8000576d76ULL;
    static const uint64_t RIGHT_CODE_LOW = 0xf7e077723ba90ULL;
    
    static const uint64_t LEFT_CODE_HIGH = 0x8000576d76ULL;
    static const uint64_t LEFT_CODE_LOW = 0xf7e077723ea84ULL;
    
    RFM69 radio;
    bool initialized;
    
    void sendPwmBit(bool bit);
    void sendSyncPulse();
    void transmitCode(uint64_t codeHigh, uint64_t codeLow);
    uint8_t readRegisterDirect(uint8_t addr);
    void writeRegisterDirect(uint8_t addr, uint8_t value);
};

#endif