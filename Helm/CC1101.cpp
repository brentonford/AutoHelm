#include "CC1101.h"

CC1101::CC1101(uint8_t csPin, uint8_t sckPin, uint8_t misoPin, uint8_t mosiPin)
    : _csPin(csPin)
    , _sckPin(sckPin)
    , _misoPin(misoPin)
    , _mosiPin(mosiPin)
    , _spiSettings(4000000, MSBFIRST, SPI_MODE0) {
}

void CC1101::select() {
    digitalWrite(_csPin, LOW);
    delayMicroseconds(1);
}

void CC1101::deselect() {
    digitalWrite(_csPin, HIGH);
    delayMicroseconds(1);
}

void CC1101::waitMiso() {
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

    if (version != 0x14 && version != 0x04)
        return false;

    configure();
    return true;
}

void CC1101::configure() {
    // Frequency: 433.017 MHz
    writeReg(CC1101Reg::freq2, 0x10);
    writeReg(CC1101Reg::freq1, 0xA7);
    writeReg(CC1101Reg::freq0, 0x6C);

    // Modem config: 2-FSK, async serial mode
    writeReg(CC1101Reg::mdmcfg4, 0xC9);
    writeReg(CC1101Reg::mdmcfg3, 0x30);
    writeReg(CC1101Reg::mdmcfg2, 0x00);
    writeReg(CC1101Reg::mdmcfg1, 0x00);
    writeReg(CC1101Reg::mdmcfg0, 0x00);

    // Deviation: ~25 kHz
    writeReg(CC1101Reg::deviatn, 0x40);

    // Front-end config
    writeReg(CC1101Reg::frend0, 0x10);
    writeReg(CC1101Reg::frend1, 0x56);

    // Main radio control
    writeReg(CC1101Reg::mcsm0, 0x18);

    // Frequency offset compensation
    writeReg(CC1101Reg::foccfg, 0x16);

    // AGC control
    writeReg(CC1101Reg::agcctrl2, 0x43);
    writeReg(CC1101Reg::agcctrl1, 0x40);
    writeReg(CC1101Reg::agcctrl0, 0x91);

    // Frequency synthesizer calibration
    writeReg(CC1101Reg::fscal3, 0xE9);
    writeReg(CC1101Reg::fscal2, 0x2A);
    writeReg(CC1101Reg::fscal1, 0x00);
    writeReg(CC1101Reg::fscal0, 0x1F);

    // Test registers
    writeReg(CC1101Reg::test2, 0x81);
    writeReg(CC1101Reg::test1, 0x35);
    writeReg(CC1101Reg::test0, 0x09);

    // GDO0: High-Z for async TX input
    writeReg(CC1101Reg::iocfg0, 0x2E);

    // Packet control: Async serial mode
    writeReg(CC1101Reg::pktctrl0, 0x32);

    // Frequency synthesizer control
    writeReg(CC1101Reg::fsctrl1, 0x06);

    // FIFO threshold
    writeReg(CC1101Reg::fifothr, 0x47);

    // PATABLE: Max TX power
    SPI.beginTransaction(_spiSettings);
    select();
    waitMiso();
    SPI.transfer(CC1101Reg::patable | 0x40);
    SPI.transfer(0xC0);
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

uint8_t CC1101::readStatusReg(uint8_t addr) {
    SPI.beginTransaction(_spiSettings);
    select();
    waitMiso();
    SPI.transfer(addr | 0xC0);
    uint8_t value = SPI.transfer(0x00);
    deselect();
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