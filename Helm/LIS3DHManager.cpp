#include "LIS3DHManager.h"

// LIS3DH register addresses
static constexpr uint8_t REG_WHO_AM_I  = 0x0F;
static constexpr uint8_t REG_CTRL_REG1 = 0x20;
static constexpr uint8_t REG_CTRL_REG4 = 0x23;
static constexpr uint8_t REG_OUT_X_L   = 0x28;
static constexpr uint8_t WHO_AM_I_ID   = 0x33;

// Setting bit 7 of a register address enables auto-increment for multi-byte reads
static constexpr uint8_t AUTO_INC = 0x80;

LIS3DHManager::LIS3DHManager(uint8_t address)
    : _address(address)
    , _initialized(false) {}

bool LIS3DHManager::writeRegister(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(_address);
    Wire.write(reg);
    Wire.write(value);
    return Wire.endTransmission() == 0;
}

bool LIS3DHManager::readBytes(uint8_t reg, uint8_t* buf, uint8_t len) {
    Wire.beginTransmission(_address);
    Wire.write(reg | AUTO_INC);
    if (Wire.endTransmission(true) != 0) return false;
    Wire.requestFrom(_address, len);
    if (Wire.available() < len) return false;
    for (uint8_t i = 0; i < len; i++) buf[i] = Wire.read();
    return true;
}

bool LIS3DHManager::begin() {
    // Give the LIS3DH time to complete its power-on reset before the first I2C
    // transaction.  Without this, the bus can be ready before the chip is.
    delay(10);

    // Verify device identity.
    // Use endTransmission(true) (STOP bit) then a fresh requestFrom rather than
    // a repeated-start (false).  The ESP32 I2C peripheral can drop the read
    // address byte on some bus configurations when repeated-start is used for
    // a single-register read, causing Wire.available() to return 0.
    Wire.beginTransmission(_address);
    Wire.write(REG_WHO_AM_I);
    if (Wire.endTransmission(true) != 0) {
        Serial.printf("[LIS3DH] Not found at 0x%02X\n", _address);
        return false;
    }
    Wire.requestFrom(_address, (uint8_t)1);
    if (!Wire.available()) {
        Serial.println("[LIS3DH] WHO_AM_I read failed");
        return false;
    }
    uint8_t id = Wire.read();
    if (id != WHO_AM_I_ID) {
        Serial.printf("[LIS3DH] Unexpected WHO_AM_I 0x%02X (expected 0x33)\n", id);
        return false;
    }

    // ODR=10 Hz, normal mode, XYZ enabled
    if (!writeRegister(REG_CTRL_REG1, LIS3DHConfig::CTRL_REG1)) {
        Serial.println("[LIS3DH] CTRL_REG1 write failed");
        return false;
    }
    // ±2 g, high-resolution mode (12-bit)
    if (!writeRegister(REG_CTRL_REG4, LIS3DHConfig::CTRL_REG4)) {
        Serial.println("[LIS3DH] CTRL_REG4 write failed");
        return false;
    }

    _initialized = true;
    Serial.println("[LIS3DH] Initialized – tilt compensation active");
    return true;
}

bool LIS3DHManager::readAccel(float& ax, float& ay, float& az) {
    if (!_initialized) return false;

    // Read 6 bytes: OUT_X_L, OUT_X_H, OUT_Y_L, OUT_Y_H, OUT_Z_L, OUT_Z_H
    uint8_t buf[6];
    if (!readBytes(REG_OUT_X_L, buf, 6)) return false;

    // Reconstruct signed 16-bit values (little-endian, left-justified)
    int16_t rawX = (int16_t)((uint16_t)(buf[1] << 8) | buf[0]);
    int16_t rawY = (int16_t)((uint16_t)(buf[3] << 8) | buf[2]);
    int16_t rawZ = (int16_t)((uint16_t)(buf[5] << 8) | buf[4]);

    // Convert to g: ±2 g full scale → 1 g ≈ 16384 counts at 16-bit resolution.
    // Only the direction of the gravity vector matters for tilt compensation,
    // so absolute calibration of magnitude is not required.
    constexpr float SCALE = 1.0f / 16384.0f;
    ax = rawX * SCALE;
    ay = rawY * SCALE;
    az = rawZ * SCALE;

    return true;
}
