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

    return true;
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