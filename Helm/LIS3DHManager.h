#pragma once
#include <Arduino.h>
#include <Wire.h>

// -------------------------------------------------------
// LIS3DH I2C driver – used for compass tilt compensation.
// The sensor shares the existing I2C bus with the MMC5603;
// Wire.begin() must have been called before begin() is invoked.
//
// Default I2C address: 0x18 (SDO/SA0 pin low, PiicoDev default).
// Use 0x19 if SDO/SA0 is pulled high.
// -------------------------------------------------------

namespace LIS3DHConfig {
    constexpr uint8_t  address      = 0x19;  // PiicoDev board pulls SA0 high
    // CTRL_REG1: ODR=10 Hz, normal mode, XYZ axes enabled
    constexpr uint8_t  CTRL_REG1    = 0x27;
    // CTRL_REG4: ±2 g, high-resolution mode (12-bit output, left-justified in 16 bits)
    constexpr uint8_t  CTRL_REG4    = 0x08;
}

class LIS3DHManager {
public:
    explicit LIS3DHManager(uint8_t address = LIS3DHConfig::address);

    // Initialise the sensor.  Wire.begin() must already have been called.
    // Returns true on success.
    bool begin();

    // Reads the three acceleration axes in g units.
    // With the sensor flat and Z pointing up: ax≈0, ay≈0, az≈+1 g.
    // Returns false if I2C communication fails.
    bool readAccel(float& ax, float& ay, float& az);

    bool isAvailable() const { return _initialized; }

private:
    uint8_t _address;
    bool    _initialized;

    bool writeRegister(uint8_t reg, uint8_t value);
    bool readBytes(uint8_t reg, uint8_t* buf, uint8_t len);
};
