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

class CC1101 {
public:
    CC1101(uint8_t csPin, uint8_t sckPin, uint8_t misoPin, uint8_t mosiPin);

    bool begin();
    void configure();
    void startTx();
    void stopTx();
    void writeReg(uint8_t addr, uint8_t value);
    uint8_t readStatusReg(uint8_t addr);
    void strobe(uint8_t cmd);

private:
    uint8_t _csPin;
    uint8_t _sckPin;
    uint8_t _misoPin;
    uint8_t _mosiPin;
    SPISettings _spiSettings;

    void select();
    void deselect();
    void waitMiso();
    void reset();
};