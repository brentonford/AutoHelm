#pragma once

#include <Arduino.h>
#include <SPI.h>

namespace CC1101Reg {
    // Configuration registers
    constexpr uint8_t iocfg0   = 0x02;
    constexpr uint8_t fifothr  = 0x03;
    constexpr uint8_t pktctrl0 = 0x08;
    constexpr uint8_t fsctrl1  = 0x0B;
    constexpr uint8_t freq2    = 0x0D;
    constexpr uint8_t freq1    = 0x0E;
    constexpr uint8_t freq0    = 0x0F;
    constexpr uint8_t mdmcfg4  = 0x10;
    constexpr uint8_t mdmcfg3  = 0x11;
    constexpr uint8_t mdmcfg2  = 0x12;
    constexpr uint8_t mdmcfg1  = 0x13;
    constexpr uint8_t mdmcfg0  = 0x14;
    constexpr uint8_t deviatn  = 0x15;
    constexpr uint8_t mcsm0    = 0x18;
    constexpr uint8_t foccfg   = 0x19;
    constexpr uint8_t agcctrl2 = 0x1B;
    constexpr uint8_t agcctrl1 = 0x1C;
    constexpr uint8_t agcctrl0 = 0x1D;
    constexpr uint8_t frend1   = 0x21;
    constexpr uint8_t frend0   = 0x22;
    constexpr uint8_t fscal3   = 0x23;
    constexpr uint8_t fscal2   = 0x24;
    constexpr uint8_t fscal1   = 0x25;
    constexpr uint8_t fscal0   = 0x26;
    constexpr uint8_t test2    = 0x2C;
    constexpr uint8_t test1    = 0x2D;
    constexpr uint8_t test0    = 0x2E;

    // Status registers (read with 0xC0 burst bit)
    constexpr uint8_t version  = 0x31;

    // Command strobes
    constexpr uint8_t sres     = 0x30;
    constexpr uint8_t scal     = 0x33;
    constexpr uint8_t stx      = 0x35;
    constexpr uint8_t sidle    = 0x36;

    // PATABLE
    constexpr uint8_t patable  = 0x3E;
}

namespace CC1101Config {
    // SPI
    constexpr uint32_t spiFrequency = 4000000;
    
    // Frequency: 433.017 MHz registers
    constexpr uint8_t freq2Val = 0x10;
    constexpr uint8_t freq1Val = 0xA7;
    constexpr uint8_t freq0Val = 0x6C;
    
    // Modem configuration for 2-FSK
    constexpr uint8_t mdmcfg4Val = 0xC9;
    constexpr uint8_t mdmcfg3Val = 0x30;
    constexpr uint8_t mdmcfg2Val = 0x00;  // 2-FSK, async serial
    constexpr uint8_t mdmcfg1Val = 0x00;
    constexpr uint8_t mdmcfg0Val = 0x00;
    
    // Deviation ~25 kHz
    constexpr uint8_t deviatnVal = 0x40;
    
    // Front-end config
    constexpr uint8_t frend0Val = 0x10;
    constexpr uint8_t frend1Val = 0x56;
    
    // Main radio control
    constexpr uint8_t mcsm0Val = 0x18;
    
    // Frequency offset compensation
    constexpr uint8_t foccfgVal = 0x16;
    
    // AGC control
    constexpr uint8_t agcctrl2Val = 0x43;
    constexpr uint8_t agcctrl1Val = 0x40;
    constexpr uint8_t agcctrl0Val = 0x91;
    
    // Frequency synthesizer calibration
    constexpr uint8_t fscal3Val = 0xE9;
    constexpr uint8_t fscal2Val = 0x2A;
    constexpr uint8_t fscal1Val = 0x00;
    constexpr uint8_t fscal0Val = 0x1F;
    
    // Test registers
    constexpr uint8_t test2Val = 0x81;
    constexpr uint8_t test1Val = 0x35;
    constexpr uint8_t test0Val = 0x09;
    
    // GDO0: High-Z for async TX input
    constexpr uint8_t iocfg0Val = 0x2E;
    
    // Packet control: Async serial mode
    constexpr uint8_t pktctrl0Val = 0x32;
    
    // Frequency synthesizer control
    constexpr uint8_t fsctrl1Val = 0x06;
    
    // FIFO threshold
    constexpr uint8_t fifothrVal = 0x47;
    
    // Max TX power
    constexpr uint8_t patableVal = 0xC0;
    
    // Version identifiers
    constexpr uint8_t versionPrimary = 0x14;
    constexpr uint8_t versionAlternate = 0x04;
    
    // SPI burst bit
    constexpr uint8_t burstBit = 0x40;
    constexpr uint8_t statusBit = 0xC0;
}

class CC1101 {
public:
    CC1101(uint8_t csPin, uint8_t sckPin, uint8_t misoPin, uint8_t mosiPin);

    bool begin();
    void configure();
    void startTx();
    void stopTx();
    void writeReg(uint8_t addr, uint8_t value);
    uint8_t readStatusReg(uint8_t addr) const;
    void strobe(uint8_t cmd);

private:
    uint8_t _csPin;
    uint8_t _sckPin;
    uint8_t _misoPin;
    uint8_t _mosiPin;
    SPISettings _spiSettings;

    void select();
    void deselect();
    void waitMiso() const;
    void reset();
};