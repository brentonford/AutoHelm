/*
 * DeviceRFController.cpp
 * 
 * Implementation of device RF control library for 433MHz remote control
 */

#include "DeviceRFController.h"
#include <SPI.h>

DeviceRFController::DeviceRFController() 
    : rf69(RF_CS_PIN, RF_INT_PIN), initialized(false) {
}

void DeviceRFController::testSPIPins() {
    Serial.println("=== SPI Pin Diagnostics ===");
    
    pinMode(RF_CS_PIN, OUTPUT);
    digitalWrite(RF_CS_PIN, HIGH);
    delay(10);
    Serial.print("CS pin (D");
    Serial.print(RF_CS_PIN);
    Serial.print(") state: ");
    Serial.print(digitalRead(RF_CS_PIN));
    Serial.println(" (should be 1)");
    
    pinMode(RF_RST_PIN, OUTPUT);
    digitalWrite(RF_RST_PIN, HIGH);
    delay(10);
    Serial.print("RST pin (D");
    Serial.print(RF_RST_PIN);
    Serial.print(") state: ");
    Serial.print(digitalRead(RF_RST_PIN));
    Serial.println(" (should be 1)");
    
    pinMode(RF_INT_PIN, INPUT);
    Serial.print("INT pin (D");
    Serial.print(RF_INT_PIN);
    Serial.print(") state: ");
    Serial.println(digitalRead(RF_INT_PIN));
    
    SPI.begin();
    Serial.print("SPI initialized - SCK:");
    Serial.print(SCK_PIN);
    Serial.print(", MISO:");
    Serial.print(MISO_PIN);
    Serial.print(", MOSI:");
    Serial.print(MOSI_PIN);
    Serial.print(", CS:");
    Serial.println(RF_CS_PIN);
    
    digitalWrite(RF_CS_PIN, LOW);
    uint8_t testByte = SPI.transfer(0x00);
    digitalWrite(RF_CS_PIN, HIGH);
    
    Serial.print("SPI test transfer result: 0x");
    Serial.println(testByte, HEX);
    Serial.println("=== End SPI Pin Diagnostics ===\n");
}

uint8_t DeviceRFController::readRegisterDirect(uint8_t addr) {
    digitalWrite(RF_CS_PIN, LOW);
    delayMicroseconds(10);
    
    SPI.transfer(addr & 0x7F);
    uint8_t value = SPI.transfer(0x00);
    
    delayMicroseconds(10);
    digitalWrite(RF_CS_PIN, HIGH);
    
    Serial.print("Read register 0x");
    Serial.print(addr, HEX);
    Serial.print(": 0x");
    Serial.println(value, HEX);
    return value;
}

void DeviceRFController::writeRegisterDirect(uint8_t addr, uint8_t value) {
    digitalWrite(RF_CS_PIN, LOW);
    delayMicroseconds(10);
    
    SPI.transfer(addr | 0x80);
    SPI.transfer(value);
    
    delayMicroseconds(10);
    digitalWrite(RF_CS_PIN, HIGH);
    
    Serial.print("Write register 0x");
    Serial.print(addr, HEX);
    Serial.print(": 0x");
    Serial.println(value, HEX);
}

void DeviceRFController::performModuleHealthCheck() {
    Serial.println("=== Module Health Check ===");
    
    uint8_t version = readRegisterDirect(0x10);
    uint8_t opMode = readRegisterDirect(0x01);
    uint8_t dataModul = readRegisterDirect(0x02);
    uint8_t bitRate1 = readRegisterDirect(0x03);
    uint8_t bitRate2 = readRegisterDirect(0x04);
    
    Serial.print("RegVersion (0x10): 0x");
    Serial.print(version, HEX);
    Serial.println(" (expect 0x24 for RFM69HCW)");
    Serial.print("RegOpMode (0x01): 0x");
    Serial.print(opMode, HEX);
    Serial.println(" (expect 0x04 power-on default)");
    Serial.print("RegDataModul (0x02): 0x");
    Serial.println(dataModul, HEX);
    Serial.print("RegBitRateMsb (0x03): 0x");
    Serial.println(bitRate1, HEX);
    Serial.print("RegBitRateLsb (0x04): 0x");
    Serial.println(bitRate2, HEX);
    
    if (version == 0x00 && opMode == 0x00 && dataModul == 0x00) {
        Serial.println("ERROR: All registers read 0x00 - SPI bus problem or module not powered");
        Serial.println("Check: VCC=3.3V, GND connected, SPI wiring correct");
    } else if (version == 0xFF && opMode == 0xFF && dataModul == 0xFF) {
        Serial.println("ERROR: All registers read 0xFF - CS not working or module not responding");
        Serial.println("Check: CS pin connection, CS pulled HIGH when idle");
    } else if (version != 0x24) {
        Serial.print("WARNING: Version register 0x");
        Serial.print(version, HEX);
        Serial.println(" != 0x24, may not be RFM69HCW");
    } else {
        Serial.println("SUCCESS: Module responding correctly");
    }
    
    Serial.println("=== End Module Health Check ===\n");
}

bool DeviceRFController::begin() {
    Serial.println("=== RF Controller Initialization ===");
    
    // Step 1: Test SPI pins and basic communication
    testSPIPins();
    
    // Step 2: Hardware reset sequence with extended timing
    Serial.println("Performing hardware reset sequence...");
    pinMode(RF_RST_PIN, OUTPUT);
    pinMode(RF_CS_PIN, OUTPUT);
    pinMode(RF_INT_PIN, INPUT);
    
    digitalWrite(RF_CS_PIN, HIGH);
    digitalWrite(RF_RST_PIN, LOW);
    delay(100);
    digitalWrite(RF_RST_PIN, HIGH);
    delay(200);
    
    Serial.println("Reset complete, module stabilizing...");
    
    // Step 3: Initialize SPI with conservative settings
    SPI.begin();
    SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
    Serial.println("SPI initialized at 1MHz for testing");
    
    // Step 4: Comprehensive module health check
    performModuleHealthCheck();
    
    // Step 5: Check if basic communication is working
    uint8_t version = readRegisterDirect(0x10);
    if (version == 0x00 || version == 0xFF) {
        Serial.println("CRITICAL ERROR: Cannot communicate with RFM69HCW module");
        Serial.println("Hardware troubleshooting required:");
        Serial.println("1. Verify 3.3V power (NOT 5V - will damage module)");
        Serial.println("2. Check all SPI connections:");
        Serial.print("   CS -> D");
        Serial.print(RF_CS_PIN);
        Serial.print(", RST -> D");
        Serial.print(RF_RST_PIN);
        Serial.print(", INT -> D");
        Serial.println(RF_INT_PIN);
        Serial.print("   SCK -> D");
        Serial.print(SCK_PIN);
        Serial.print(", MISO -> D");
        Serial.print(MISO_PIN);
        Serial.print(", MOSI -> D");
        Serial.println(MOSI_PIN);
        Serial.println("3. Verify GND connections");
        Serial.println("4. Check antenna connection (some modules need antenna to respond)");
        Serial.println("5. Ensure CS is HIGH when module not selected");
        return false;
    }
    
    // Step 6: Prepare for RadioHead initialization with proper SPI cleanup
    Serial.println("Preparing for RadioHead library initialization...");
    Serial.flush();
    
    // End current SPI transaction and reset SPI state
    SPI.endTransaction();
    delay(10);
    
    // Ensure pins are in correct state for RadioHead
    digitalWrite(RF_CS_PIN, HIGH);
    digitalWrite(RF_RST_PIN, HIGH);
    pinMode(RF_INT_PIN, INPUT);
    delay(50);
    
    // Test write functionality before RadioHead init
    Serial.println("Testing register write functionality...");
    Serial.flush();
    
    uint8_t originalOpMode = readRegisterDirect(0x01);
    Serial.print("Original OpMode: 0x");
    Serial.println(originalOpMode, HEX);
    
    writeRegisterDirect(0x01, 0x04);
    delay(10);
    uint8_t newOpMode = readRegisterDirect(0x01);
    Serial.print("After writing 0x04 to OpMode: 0x");
    Serial.println(newOpMode, HEX);
    
    if (newOpMode != 0x04) {
        Serial.println("ERROR: Write operation failed - register did not update");
        Serial.println("This will cause RadioHead init to fail");
        return false;
    } else {
        Serial.println("SUCCESS: Write operation working correctly");
    }
    Serial.flush();
    
    Serial.println("About to call rf69.init()...");
    Serial.flush();
    
    // Add timeout mechanism around rf69.init() call
    unsigned long initStartTime = millis();
    bool initResult = false;
    bool initCompleted = false;
    
    // Attempt initialization with 5 second timeout
    while (millis() - initStartTime < 5000 && !initCompleted) {
        Serial.print("RadioHead init attempt... ");
        Serial.flush();
        
        initResult = rf69.init();
        initCompleted = true;
        
        Serial.print("returned: ");
        Serial.println(initResult ? "true" : "false");
        Serial.flush();
    }
    
    if (!initCompleted) {
        Serial.println("TIMEOUT: rf69.init() did not complete within 5 seconds");
        Serial.println("This indicates a serious hardware or library issue");
        Serial.flush();
        return false;
    }
    
    if (!initResult) {
        Serial.println("RadioHead init failed despite SPI communication working");
        Serial.println("This suggests register-level communication issues");
        Serial.flush();
        return false;
    }
    
    Serial.println("RadioHead initialization successful");
    Serial.flush();
    
    // Step 7: Configure radio parameters
    Serial.println("Configuring radio parameters...");
    Serial.flush();
    
    Serial.println("Setting frequency...");
    Serial.flush();
    
    if (!rf69.setFrequency(FREQUENCY)) {
        Serial.println("ERROR: Frequency setting failed");
        Serial.flush();
        return false;
    }
    Serial.print("Frequency set to ");
    Serial.print(FREQUENCY, 3);
    Serial.println(" MHz");
    Serial.flush();
    
    rf69.setModemConfig(RH_RF69::FSK_Rb2Fd5);
    Serial.println("Modem config set");
    
    uint16_t fdevReg = (uint16_t)((FREQ_DEVIATION * 1000.0) / 61.035);
    rf69.spiWrite(RH_RF69_REG_05_FDEVMSB, fdevReg >> 8);
    rf69.spiWrite(RH_RF69_REG_06_FDEVLSB, fdevReg & 0xFF);
    Serial.print("Frequency deviation set to ");
    Serial.print(FREQ_DEVIATION, 1);
    Serial.println(" kHz");
    
    uint16_t bitrateReg = (uint16_t)(32000000.0 / BITRATE);
    rf69.spiWrite(RH_RF69_REG_03_BITRATEMSB, bitrateReg >> 8);
    rf69.spiWrite(RH_RF69_REG_04_BITRATELSB, bitrateReg & 0xFF);
    Serial.print("Bitrate set to ");
    Serial.print(BITRATE);
    Serial.println(" bps");
    
    rf69.setTxPower(20, true);
    Serial.println("TX power set to 20dBm");
    
    rf69.spiWrite(RH_RF69_REG_37_PACKETCONFIG1, 0x00);
    rf69.spiWrite(RH_RF69_REG_6F_TESTDAGC, 0x30);
    Serial.println("Additional registers configured");
    
    pinMode(RF_INT_PIN, OUTPUT);
    digitalWrite(RF_INT_PIN, LOW);
    
    initialized = true;
    
    Serial.println("=== RF Controller Ready ===");
    Serial.println("Module successfully initialized and configured");
    Serial.println("Ready for transmission commands");
    
    return true;
}

void DeviceRFController::sendPwmBit(bool bit) {
    if (bit) {
        digitalWrite(RF_INT_PIN, HIGH);
        delayMicroseconds(LONG_PULSE_US);
        digitalWrite(RF_INT_PIN, LOW);
        delayMicroseconds(SHORT_PULSE_US);
    } else {
        digitalWrite(RF_INT_PIN, HIGH);
        delayMicroseconds(SHORT_PULSE_US);
        digitalWrite(RF_INT_PIN, LOW);
        delayMicroseconds(LONG_PULSE_US);
    }
}

void DeviceRFController::sendSyncPulse() {
    digitalWrite(RF_INT_PIN, HIGH);
    delayMicroseconds(SYNC_PULSE_US);
    digitalWrite(RF_INT_PIN, LOW);
    delayMicroseconds(GAP_US);
}

void DeviceRFController::transmitCode(uint64_t codeHigh, uint64_t codeLow) {
    rf69.setModeTx();
    delay(1);
    
    sendSyncPulse();
    
    for (int8_t i = 39; i >= 0; i--) {
        bool bit = (codeHigh >> i) & 1;
        sendPwmBit(bit);
    }
    
    for (int8_t i = 49; i >= 0; i--) {
        bool bit = (codeLow >> i) & 1;
        sendPwmBit(bit);
    }
    
    delay(2);
    rf69.setModeIdle();
}

void DeviceRFController::transmitRight(uint8_t repeatCount) {
    if (!initialized) {
        Serial.println("Cannot transmit - RF controller not initialized");
        return;
    }
    
    Serial.print("Transmitting RIGHT command (");
    Serial.print(repeatCount);
    Serial.println(" repeats)");
    for (uint8_t i = 0; i < repeatCount; i++) {
        transmitCode(RIGHT_CODE_HIGH, RIGHT_CODE_LOW);
        delay(50);
    }
}

void DeviceRFController::transmitLeft(uint8_t repeatCount) {
    if (!initialized) {
        Serial.println("Cannot transmit - RF controller not initialized");
        return;
    }
    
    Serial.print("Transmitting LEFT command (");
    Serial.print(repeatCount);
    Serial.println(" repeats)");
    for (uint8_t i = 0; i < repeatCount; i++) {
        transmitCode(LEFT_CODE_HIGH, LEFT_CODE_LOW);
        delay(50);
    }
}

bool DeviceRFController::isInitialized() const {
    return initialized;
}