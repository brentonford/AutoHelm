/*
 * DeviceRFController.h
 * 
 * Library for controlling remote devices via 433MHz RF transmission
 * using RFM69HCW radio module with direct GPIO modulation for precise PWM timing
 * 
 * Signal Parameters (from RTL-SDR analysis):
 * - Frequency: 433.032 MHz
 * - Modulation: OOK with PWM encoding
 * - Bit rate: 6400 bps
 * 
 * Hardware Requirements:
 * - Arduino UNO R4 (or compatible)
 * - Adafruit RFM69HCW 433MHz Breakout
 * - LowPowerLab RFM69 library
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
 * G2/DIO2  -> D7 (NEW - for direct modulation)
 * ANT      -> 433MHz spring antenna
 */

#ifndef DEVICE_RF_CONTROLLER_H
#define DEVICE_RF_CONTROLLER_H

#include <Arduino.h>
#include <RFM69.h>
#include <SPI.h>
#include <RCSwitch.h>

class DeviceRFController {
public:
    DeviceRFController();
    
    bool begin();
    void transmitRight(uint8_t repeatCount = 3);
    void transmitLeft(uint8_t repeatCount = 3);
    bool isInitialized() const;
    void verifyTransmission();
    void testContinuousCarrier();
    void captureRawSignal();
    void testRcSwitch();
    void compareProtocols();

private:
    static const uint8_t RF_CS_PIN = 10;
    static const uint8_t RF_RST_PIN = 9;
    static const uint8_t RF_INT_PIN = 8;
    static const uint8_t RF_DATA_PIN = 7;
    static const uint8_t RF_POWER_LEVEL = 20;
    static const uint8_t RF_NETWORK_ID = 100;
    static const uint8_t RF_NODE_ID = 1;
    
    static constexpr float FREQUENCY_MHZ = 433.032;
    
    // Exact PWM timing constants from specification
    static const uint16_t SHORT_PULSE_HIGH_US = 50;
    static const uint16_t SHORT_PULSE_LOW_US = 52;
    static const uint16_t LONG_PULSE_HIGH_US = 102;
    static const uint16_t LONG_PULSE_LOW_US = 52;
    static const uint16_t SYNC_PULSE_HIGH_US = 170;
    static const uint16_t SYNC_PULSE_LOW_US = 114;
    static const uint16_t FRAME_GAP_US = 114;
    
    // 90-bit control codes from specification
    static const uint64_t RIGHT_CODE_HIGH = 0x8000576d76ULL;
    static const uint64_t RIGHT_CODE_LOW = 0xf7e077723ba90ULL;
    static const uint64_t LEFT_CODE_HIGH = 0x8000576d76ULL;
    static const uint64_t LEFT_CODE_LOW = 0xf7e077723ea84ULL;
    
    RFM69 radio;
    RCSwitch rcSwitch;
    bool initialized;
    bool useRcSwitch;
    
    bool configureRadio();
    void configureDirectMode();
    void transmit90BitCommand(uint64_t codeHigh, uint64_t codeLow, uint8_t repeatCount);
    void sendBit(bool bitValue);
    void sendSyncPulse();
    bool validateTransmission();
    void writeReg(uint8_t addr, uint8_t value);
    uint8_t readReg(uint8_t addr);
};

#endif