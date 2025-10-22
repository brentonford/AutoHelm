/*
 * WatersnakeRFController.h
 * 
 * Library for controlling Watersnake Fierce 2 electric motor
 * via RFM69HCW 433MHz radio module
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
 * - RadioHead library by Mike McCauley
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
 * G0/DIO0  -> D2
 * ANT      -> 433MHz spring antenna
 * 
 * Serial Commands:
 * 'R' or 'r' - Transmit RIGHT command
 * 'L' or 'l' - Transmit LEFT command
 */

#ifndef WATERSNAKE_RF_CONTROLLER_H
#define WATERSNAKE_RF_CONTROLLER_H

#include <Arduino.h>
#include <RH_RF69.h>

class WatersnakeRFController {
public:
    WatersnakeRFController();
    
    bool begin();
    void transmitRight(uint8_t repeatCount = 3);
    void transmitLeft(uint8_t repeatCount = 3);
    bool isInitialized() const;

private:
    static const uint8_t RF_CS_PIN = 10;
    static const uint8_t RF_RST_PIN = 9;
    static const uint8_t RF_INT_PIN = 2;
    
    static constexpr float FREQUENCY = 433.032;
    static constexpr float FREQ_DEVIATION = 22.5;
    static const uint16_t BITRATE = 6400;
    
    static const uint8_t SHORT_PULSE_US = 50;
    static const uint8_t LONG_PULSE_US = 102;
    static const uint8_t SYNC_PULSE_US = 170;
    static const uint8_t GAP_US = 114;
    
    static const uint8_t DATA_BITS = 90;
    
    static const uint64_t RIGHT_CODE_HIGH = 0x8000576d76ULL;
    static const uint64_t RIGHT_CODE_LOW = 0xf7e077723ba90ULL;
    
    static const uint64_t LEFT_CODE_HIGH = 0x8000576d76ULL;
    static const uint64_t LEFT_CODE_LOW = 0xf7e077723ea84ULL;
    
    RH_RF69 rf69;
    bool initialized;
    
    void sendPwmBit(bool bit);
    void sendSyncPulse();
    void transmitCode(uint64_t codeHigh, uint64_t codeLow);
};

#endif