#include "CC1101.h"

CC1101::CC1101(uint8_t csPin, uint8_t sckPin, uint8_t misoPin, uint8_t mosiPin)
    : _csPin(csPin)
    , _sckPin(sckPin)
    , _misoPin(misoPin)
    , _mosiPin(mosiPin)
    , _spiSettings(CC1101Config::spiFrequency, MSBFIRST, SPI_MODE0) {
}

void CC1101::select() {
    digitalWrite(_csPin, LOW);
    delayMicroseconds(1);
}

void CC1101::deselect() {
    digitalWrite(_csPin, HIGH);
    delayMicroseconds(1);
}

bool CC1101::waitMiso(uint32_t timeoutUs) const {
    uint32_t startTime = micros();
    while (digitalRead(_misoPin)) {
        delayMicroseconds(1);
        if ((micros() - startTime) > timeoutUs) {
            Serial.println("[CC1101] ERROR: MISO wait timeout");
            return false;
        }
    }
    return true;
}

bool CC1101::reset() {
    deselect();
    delayMicroseconds(5);
    select();
    delayMicroseconds(10);
    deselect();
    delayMicroseconds(45);

    SPI.beginTransaction(_spiSettings);
    select();
    if (!waitMiso()) {
        deselect();
        SPI.endTransaction();
        return false;
    }
    SPI.transfer(CC1101Reg::sres);
    deselect();
    SPI.endTransaction();

    delay(10);
    return true;
}

bool CC1101::begin() {
    pinMode(_csPin, OUTPUT);
    digitalWrite(_csPin, HIGH);

    SPI.begin(_sckPin, _misoPin, _mosiPin, _csPin);
    delay(100);

    if (!reset()) {
        Serial.println("[CC1101] Reset failed - MISO timeout");
        return false;
    }

    uint8_t version = readStatusReg(CC1101Reg::version);
    Serial.printf("[CC1101] Version: 0x%02X\n", version);

    if (version != CC1101Config::versionPrimary && version != CC1101Config::versionAlternate)
        return false;

    if (!configure()) {
        Serial.println("[CC1101] Configuration failed");
        return false;
    }
    return true;
}

bool CC1101::configure() {
    // Frequency: 433.017 MHz
    if (!writeReg(CC1101Reg::freq2, CC1101Config::freq2Val)) return false;
    if (!writeReg(CC1101Reg::freq1, CC1101Config::freq1Val)) return false;
    if (!writeReg(CC1101Reg::freq0, CC1101Config::freq0Val)) return false;

    // Modem config: 2-FSK, async serial mode
    if (!writeReg(CC1101Reg::mdmcfg4, CC1101Config::mdmcfg4Val)) return false;
    if (!writeReg(CC1101Reg::mdmcfg3, CC1101Config::mdmcfg3Val)) return false;
    if (!writeReg(CC1101Reg::mdmcfg2, CC1101Config::mdmcfg2Val)) return false;
    if (!writeReg(CC1101Reg::mdmcfg1, CC1101Config::mdmcfg1Val)) return false;
    if (!writeReg(CC1101Reg::mdmcfg0, CC1101Config::mdmcfg0Val)) return false;

    // Deviation: ~25 kHz
    if (!writeReg(CC1101Reg::deviatn, CC1101Config::deviatnVal)) return false;

    // Front-end config
    if (!writeReg(CC1101Reg::frend0, CC1101Config::frend0Val)) return false;
    if (!writeReg(CC1101Reg::frend1, CC1101Config::frend1Val)) return false;

    // Main radio control
    if (!writeReg(CC1101Reg::mcsm0, CC1101Config::mcsm0Val)) return false;

    // Frequency offset compensation
    if (!writeReg(CC1101Reg::foccfg, CC1101Config::foccfgVal)) return false;

    // AGC control
    if (!writeReg(CC1101Reg::agcctrl2, CC1101Config::agcctrl2Val)) return false;
    if (!writeReg(CC1101Reg::agcctrl1, CC1101Config::agcctrl1Val)) return false;
    if (!writeReg(CC1101Reg::agcctrl0, CC1101Config::agcctrl0Val)) return false;

    // Frequency synthesizer calibration
    if (!writeReg(CC1101Reg::fscal3, CC1101Config::fscal3Val)) return false;
    if (!writeReg(CC1101Reg::fscal2, CC1101Config::fscal2Val)) return false;
    if (!writeReg(CC1101Reg::fscal1, CC1101Config::fscal1Val)) return false;
    if (!writeReg(CC1101Reg::fscal0, CC1101Config::fscal0Val)) return false;

    // Test registers
    if (!writeReg(CC1101Reg::test2, CC1101Config::test2Val)) return false;
    if (!writeReg(CC1101Reg::test1, CC1101Config::test1Val)) return false;
    if (!writeReg(CC1101Reg::test0, CC1101Config::test0Val)) return false;

    // GDO0: High-Z for async TX input
    if (!writeReg(CC1101Reg::iocfg0, CC1101Config::iocfg0Val)) return false;

    // Packet control: Async serial mode
    if (!writeReg(CC1101Reg::pktctrl0, CC1101Config::pktctrl0Val)) return false;

    // Frequency synthesizer control
    if (!writeReg(CC1101Reg::fsctrl1, CC1101Config::fsctrl1Val)) return false;

    // FIFO threshold
    if (!writeReg(CC1101Reg::fifothr, CC1101Config::fifothrVal)) return false;

    // PATABLE: Max TX power
    SPI.beginTransaction(_spiSettings);
    select();
    if (!waitMiso()) {
        deselect();
        SPI.endTransaction();
        return false;
    }
    SPI.transfer(CC1101Reg::patable | CC1101Config::burstBit);
    SPI.transfer(CC1101Config::patableVal);
    deselect();
    SPI.endTransaction();

    // Enter idle state
    if (!strobe(CC1101Reg::sidle)) return false;
    delay(1);

    Serial.println("[CC1101] Configured for 433.017 MHz 2-FSK");
    return true;
}

void CC1101::startTx() {
    strobe(CC1101Reg::sidle);
    delayMicroseconds(100);
    strobe(CC1101Reg::scal);
    delay(1);
    strobe(CC1101Reg::stx);
    delayMicroseconds(500);
}

void CC1101::stopTx() {
    strobe(CC1101Reg::sidle);
}

bool CC1101::writeReg(uint8_t addr, uint8_t value) {
    SPI.beginTransaction(_spiSettings);
    select();
    if (!waitMiso()) {
        deselect();
        SPI.endTransaction();
        return false;
    }
    SPI.transfer(addr);
    SPI.transfer(value);
    deselect();
    SPI.endTransaction();
    return true;
}

uint8_t CC1101::readStatusReg(uint8_t addr) const {
    SPI.beginTransaction(_spiSettings);
    const_cast<CC1101*>(this)->select();
    if (!waitMiso()) {
        const_cast<CC1101*>(this)->deselect();
        SPI.endTransaction();
        return 0xFF;  // Return error value
    }
    SPI.transfer(addr | CC1101Config::statusBit);
    uint8_t value = SPI.transfer(0x00);
    const_cast<CC1101*>(this)->deselect();
    SPI.endTransaction();
    return value;
}

bool CC1101::strobe(uint8_t cmd) {
    SPI.beginTransaction(_spiSettings);
    select();
    if (!waitMiso()) {
        deselect();
        SPI.endTransaction();
        return false;
    }
    SPI.transfer(cmd);
    deselect();
    SPI.endTransaction();
    return true;
}