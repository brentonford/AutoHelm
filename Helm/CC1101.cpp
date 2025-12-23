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

void CC1101::waitMiso() const {
    while (digitalRead(_misoPin))
        delayMicroseconds(1);
}

void CC1101::reset() {
    deselect();
    delayMicroseconds(5);
    select();
    delayMicroseconds(10);
    deselect();
    delayMicroseconds(45);

    SPI.beginTransaction(_spiSettings);
    select();
    waitMiso();
    SPI.transfer(CC1101Reg::sres);
    deselect();
    SPI.endTransaction();

    delay(10);
}

bool CC1101::begin() {
    pinMode(_csPin, OUTPUT);
    digitalWrite(_csPin, HIGH);

    SPI.begin(_sckPin, _misoPin, _mosiPin, _csPin);
    delay(100);

    reset();

    uint8_t version = readStatusReg(CC1101Reg::version);
    Serial.printf("[CC1101] Version: 0x%02X\n", version);

    if (version != CC1101Config::versionPrimary && version != CC1101Config::versionAlternate)
        return false;

    configure();
    return true;
}

void CC1101::configure() {
    // Frequency: 433.017 MHz
    writeReg(CC1101Reg::freq2, CC1101Config::freq2Val);
    writeReg(CC1101Reg::freq1, CC1101Config::freq1Val);
    writeReg(CC1101Reg::freq0, CC1101Config::freq0Val);

    // Modem config: 2-FSK, async serial mode
    writeReg(CC1101Reg::mdmcfg4, CC1101Config::mdmcfg4Val);
    writeReg(CC1101Reg::mdmcfg3, CC1101Config::mdmcfg3Val);
    writeReg(CC1101Reg::mdmcfg2, CC1101Config::mdmcfg2Val);
    writeReg(CC1101Reg::mdmcfg1, CC1101Config::mdmcfg1Val);
    writeReg(CC1101Reg::mdmcfg0, CC1101Config::mdmcfg0Val);

    // Deviation: ~25 kHz
    writeReg(CC1101Reg::deviatn, CC1101Config::deviatnVal);

    // Front-end config
    writeReg(CC1101Reg::frend0, CC1101Config::frend0Val);
    writeReg(CC1101Reg::frend1, CC1101Config::frend1Val);

    // Main radio control
    writeReg(CC1101Reg::mcsm0, CC1101Config::mcsm0Val);

    // Frequency offset compensation
    writeReg(CC1101Reg::foccfg, CC1101Config::foccfgVal);

    // AGC control
    writeReg(CC1101Reg::agcctrl2, CC1101Config::agcctrl2Val);
    writeReg(CC1101Reg::agcctrl1, CC1101Config::agcctrl1Val);
    writeReg(CC1101Reg::agcctrl0, CC1101Config::agcctrl0Val);

    // Frequency synthesizer calibration
    writeReg(CC1101Reg::fscal3, CC1101Config::fscal3Val);
    writeReg(CC1101Reg::fscal2, CC1101Config::fscal2Val);
    writeReg(CC1101Reg::fscal1, CC1101Config::fscal1Val);
    writeReg(CC1101Reg::fscal0, CC1101Config::fscal0Val);

    // Test registers
    writeReg(CC1101Reg::test2, CC1101Config::test2Val);
    writeReg(CC1101Reg::test1, CC1101Config::test1Val);
    writeReg(CC1101Reg::test0, CC1101Config::test0Val);

    // GDO0: High-Z for async TX input
    writeReg(CC1101Reg::iocfg0, CC1101Config::iocfg0Val);

    // Packet control: Async serial mode
    writeReg(CC1101Reg::pktctrl0, CC1101Config::pktctrl0Val);

    // Frequency synthesizer control
    writeReg(CC1101Reg::fsctrl1, CC1101Config::fsctrl1Val);

    // FIFO threshold
    writeReg(CC1101Reg::fifothr, CC1101Config::fifothrVal);

    // PATABLE: Max TX power
    SPI.beginTransaction(_spiSettings);
    select();
    waitMiso();
    SPI.transfer(CC1101Reg::patable | CC1101Config::burstBit);
    SPI.transfer(CC1101Config::patableVal);
    deselect();
    SPI.endTransaction();

    // Enter idle state
    strobe(CC1101Reg::sidle);
    delay(1);

    Serial.println("[CC1101] Configured for 433.017 MHz 2-FSK");
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

void CC1101::writeReg(uint8_t addr, uint8_t value) {
    SPI.beginTransaction(_spiSettings);
    select();
    waitMiso();
    SPI.transfer(addr);
    SPI.transfer(value);
    deselect();
    SPI.endTransaction();
}

uint8_t CC1101::readStatusReg(uint8_t addr) const {
    SPI.beginTransaction(_spiSettings);
    const_cast<CC1101*>(this)->select();
    waitMiso();
    SPI.transfer(addr | CC1101Config::statusBit);
    uint8_t value = SPI.transfer(0x00);
    const_cast<CC1101*>(this)->deselect();
    SPI.endTransaction();
    return value;
}

void CC1101::strobe(uint8_t cmd) {
    SPI.beginTransaction(_spiSettings);
    select();
    waitMiso();
    SPI.transfer(cmd);
    deselect();
    SPI.endTransaction();
}