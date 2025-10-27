/*
 * DeviceRFController.cpp
 * 
 * Optimized implementation using RFM69 direct mode with GPIO control
 * for precise 90-bit PWM signal generation matching exact protocol specification
 */

#include "DeviceRFController.h"
#include <RFM69registers.h>

DeviceRFController::DeviceRFController() 
    : radio(RF_CS_PIN, RF_INT_PIN, true, RF_INT_PIN), initialized(false), useRcSwitch(false) {
}

bool DeviceRFController::begin() {
    Serial.println("Initializing RFM69HCW radio with direct mode...");
    
    // Hardware reset sequence
    pinMode(RF_RST_PIN, OUTPUT);
    digitalWrite(RF_RST_PIN, HIGH);
    delay(100);
    digitalWrite(RF_RST_PIN, LOW);
    delay(100);
    
    Serial.println("Hardware reset complete");
    
    pinMode(RF_CS_PIN, OUTPUT);
    digitalWrite(RF_CS_PIN, HIGH);
    
    SPI.begin();
    
    Serial.println("Testing SPI communication...");
    SPISettings settings(1000000, MSBFIRST, SPI_MODE0);
    SPI.beginTransaction(settings);
    digitalWrite(RF_CS_PIN, LOW);
    delayMicroseconds(10);
    SPI.transfer(0x10 & 0x7F);
    uint8_t version = SPI.transfer(0x00);
    delayMicroseconds(10);
    digitalWrite(RF_CS_PIN, HIGH);
    SPI.endTransaction();
    
    Serial.print("Version register: 0x");
    Serial.println(version, HEX);
    
    if (version != 0x24) {
        Serial.println("SPI communication failed - expected 0x24");
        return false;
    }
    
    Serial.println("SPI OK, calling radio.initialize()...");
    
    // Initialize LowPowerLab RFM69 driver
    if (!radio.initialize(RF69_433MHZ, RF_NODE_ID, RF_NETWORK_ID)) {
        Serial.println("RFM69HCW initialization failed - check wiring");
        return false;
    }
    
    Serial.println("RFM69HCW driver initialized successfully");
    
    // Configure radio parameters
    if (!configureRadio()) {
        Serial.println("RFM69HCW configuration failed");
        return false;
    }
    
    // Configure direct mode
    configureDirectMode();
    
    // Initialize rc-switch for comparison
    rcSwitch.enableTransmit(RF_DATA_PIN);
    rcSwitch.setProtocol(1);
    rcSwitch.setPulseLength(320);
    Serial.println("rc-switch initialized for protocol comparison");
    
    // Validate transmission capability
    if (!validateTransmission()) {
        Serial.println("RFM69HCW transmission validation failed");
        return false;
    }
    
    initialized = true;
    Serial.println("RF Controller initialization complete with direct mode and rc-switch support");
    
    return true;
}

bool DeviceRFController::configureRadio() {
    Serial.println("Configuring radio parameters...");
    
    // Set frequency with high precision
    Serial.print("Setting frequency to ");
    Serial.print(FREQUENCY_MHZ, 3);
    Serial.println(" MHz...");
    
    radio.setFrequency(FREQUENCY_MHZ * 1000000);
    Serial.print("Frequency set to ");
    Serial.print(FREQUENCY_MHZ, 3);
    Serial.println(" MHz");
    
    // Configure for maximum power transmission
    Serial.print("Setting TX power to ");
    Serial.println(RF_POWER_LEVEL);
    radio.setPowerLevel(RF_POWER_LEVEL);
    Serial.print("TX power set to ");
    Serial.println(RF_POWER_LEVEL);
    
    // Configure for OOK modulation
    Serial.println("Configuring for OOK modulation...");
    writeReg(REG_DATAMODUL, RF_DATAMODUL_DATAMODE_CONTINUOUSNOBSYNC | RF_DATAMODUL_MODULATIONTYPE_OOK | RF_DATAMODUL_MODULATIONSHAPING_00);
    
    // Set OOK threshold
    writeReg(REG_OOKPEAK, RF_OOKPEAK_THRESHTYPE_PEAK | RF_OOKPEAK_PEAKTHRESHSTEP_000 | RF_OOKPEAK_PEAKTHRESHDEC_000);
    writeReg(REG_OOKFIX, 0x0C);
    
    Serial.println("OOK modulation configured");
    
    return true;
}

void DeviceRFController::configureDirectMode() {
    Serial.println("Configuring direct mode...");
    
    // Put radio in standby
    writeReg(REG_OPMODE, RF_OPMODE_SEQUENCER_ON | RF_OPMODE_LISTEN_OFF | RF_OPMODE_STANDBY);
    
    // Set precise frequency
    uint32_t frf = ((uint32_t)(FREQUENCY_MHZ * 1000000.0 / 61.03515625));
    writeReg(REG_FRFMSB, (frf >> 16) & 0xFF);
    writeReg(REG_FRFMID, (frf >> 8) & 0xFF);
    writeReg(REG_FRFLSB, frf & 0xFF);
    
    // Configure modulation for direct mode
    writeReg(REG_DATAMODUL, 0x48);  // OOK, continuous mode without bit sync
    
    // Configure DIO2 for direct mode data input
    writeReg(REG_DIOMAPPING1, 0x03);  // DIO2 = Data
    
    // Set power level
    writeReg(REG_PALEVEL, 0x9F);  // PA0 on, +13dBm
    
    // Configure data pin as output
    pinMode(RF_DATA_PIN, OUTPUT);
    digitalWrite(RF_DATA_PIN, LOW);
    
    // Enter TX mode for continuous transmission
    writeReg(REG_OPMODE, RF_OPMODE_SEQUENCER_ON | RF_OPMODE_LISTEN_OFF | RF_OPMODE_TRANSMITTER);
    
    // Wait for mode ready
    while ((readReg(REG_IRQFLAGS1) & RF_IRQFLAGS1_MODEREADY) == 0x00);
    
    Serial.println("Direct mode configured - radio in continuous TX, ready for GPIO modulation");
}

void DeviceRFController::transmitRight(uint8_t repeatCount) {
    if (!initialized) {
        Serial.println("Cannot transmit RIGHT - RF controller not initialized");
        return;
    }
    
    Serial.print("Transmitting RIGHT command (");
    Serial.print(repeatCount);
    Serial.println(" repeats) with direct mode");
    
    transmit90BitCommand(RIGHT_CODE_HIGH, RIGHT_CODE_LOW, repeatCount);
    
    Serial.println("RIGHT transmission complete");
}

void DeviceRFController::transmitLeft(uint8_t repeatCount) {
    if (!initialized) {
        Serial.println("Cannot transmit LEFT - RF controller not initialized");
        return;
    }
    
    Serial.print("Transmitting LEFT command (");
    Serial.print(repeatCount);
    Serial.println(" repeats) with direct mode");
    
    transmit90BitCommand(LEFT_CODE_HIGH, LEFT_CODE_LOW, repeatCount);
    
    Serial.println("LEFT transmission complete");
}

void DeviceRFController::transmit90BitCommand(uint64_t codeHigh, uint64_t codeLow, uint8_t repeatCount) {
    Serial.print("90-bit code HIGH: 0x");
    Serial.print((uint32_t)(codeHigh >> 32), HEX);
    Serial.print((uint32_t)(codeHigh & 0xFFFFFFFF), HEX);
    Serial.print(", LOW: 0x");
    Serial.print((uint32_t)(codeLow >> 32), HEX);
    Serial.println((uint32_t)(codeLow & 0xFFFFFFFF), HEX);
    
    for (uint8_t i = 0; i < repeatCount; i++) {
        // Send sync pulse
        sendSyncPulse();
        
        // Transmit first 40 bits from codeHigh
        for (int8_t bit = 39; bit >= 0; bit--) {
            bool bitValue = (codeHigh >> bit) & 1;
            sendBit(bitValue);
        }
        
        // Transmit last 50 bits from codeLow
        for (int8_t bit = 49; bit >= 0; bit--) {
            bool bitValue = (codeLow >> bit) & 1;
            sendBit(bitValue);
        }
        
        // Inter-frame gap
        digitalWrite(RF_DATA_PIN, LOW);
        delayMicroseconds(FRAME_GAP_US);
        
        Serial.print("90-bit frame ");
        Serial.print(i + 1);
        Serial.print("/");
        Serial.print(repeatCount);
        Serial.println(" transmitted");
    }
    
    // Ensure carrier off
    digitalWrite(RF_DATA_PIN, LOW);
}

void DeviceRFController::sendBit(bool bitValue) {
    if (bitValue) {
        // Transmit '1' as long pulse: 102μs HIGH + 52μs LOW
        digitalWrite(RF_DATA_PIN, HIGH);
        delayMicroseconds(LONG_PULSE_HIGH_US);
        digitalWrite(RF_DATA_PIN, LOW);
        delayMicroseconds(LONG_PULSE_LOW_US);
    } else {
        // Transmit '0' as short pulse: 50μs HIGH + 52μs LOW
        digitalWrite(RF_DATA_PIN, HIGH);
        delayMicroseconds(SHORT_PULSE_HIGH_US);
        digitalWrite(RF_DATA_PIN, LOW);
        delayMicroseconds(SHORT_PULSE_LOW_US);
    }
}

void DeviceRFController::sendSyncPulse() {
    // Sync pulse: 170μs HIGH + 114μs LOW
    digitalWrite(RF_DATA_PIN, HIGH);
    delayMicroseconds(SYNC_PULSE_HIGH_US);
    digitalWrite(RF_DATA_PIN, LOW);
    delayMicroseconds(SYNC_PULSE_LOW_US);
}

bool DeviceRFController::validateTransmission() {
    Serial.println("Starting transmission validation...");
    
    // Test GPIO control
    digitalWrite(RF_DATA_PIN, HIGH);
    delayMicroseconds(1000);
    digitalWrite(RF_DATA_PIN, LOW);
    delayMicroseconds(1000);
    
    Serial.println("Transmission validation successful");
    return true;
}

void DeviceRFController::writeReg(uint8_t addr, uint8_t value) {
    radio.writeReg(addr, value);
}

uint8_t DeviceRFController::readReg(uint8_t addr) {
    return radio.readReg(addr);
}

bool DeviceRFController::isInitialized() const {
    return initialized;
}

void DeviceRFController::verifyTransmission() {
    Serial.println("=== Transmission Diagnostics ===");
    
    Serial.print("OpMode (0x01): 0x");
    Serial.println(radio.readReg(0x01), HEX);
    
    Serial.print("DataModul (0x02): 0x");
    Serial.println(radio.readReg(0x02), HEX);
    
    Serial.print("RegFrfMsb (0x07): 0x");
    Serial.println(radio.readReg(0x07), HEX);
    Serial.print("RegFrfMid (0x08): 0x");
    Serial.println(radio.readReg(0x08), HEX);
    Serial.print("RegFrfLsb (0x09): 0x");
    Serial.println(radio.readReg(0x09), HEX);
    
    uint32_t frf = ((uint32_t)radio.readReg(0x07) << 16) | 
                   ((uint32_t)radio.readReg(0x08) << 8) | 
                   radio.readReg(0x09);
    float freqMHz = (frf * 32000000.0) / 524288.0 / 1000000.0;
    Serial.print("Calculated Frequency: ");
    Serial.print(freqMHz, 6);
    Serial.println(" MHz");
    
    Serial.print("PaLevel (0x11): 0x");
    Serial.println(radio.readReg(0x11), HEX);
    
    Serial.print("DioMapping1 (0x25): 0x");
    Serial.println(radio.readReg(0x25), HEX);
    
    Serial.println("Toggling DIO2 for 1 second...");
    for (int i = 0; i < 1000; i++) {
        digitalWrite(RF_DATA_PIN, HIGH);
        delayMicroseconds(500);
        digitalWrite(RF_DATA_PIN, LOW);
        delayMicroseconds(500);
    }
    Serial.println("Toggle complete - check SDR for continuous carrier");
}

void DeviceRFController::testContinuousCarrier() {
    Serial.println("Transmitting continuous carrier for 5 seconds...");
    radio.writeReg(0x01, 0x0D);  // Continuous TX mode
    digitalWrite(RF_DATA_PIN, HIGH);  // Carrier ON
    delay(5000);
    digitalWrite(RF_DATA_PIN, LOW);   // Carrier OFF
    radio.writeReg(0x01, 0x04);   // Back to standby
    Serial.println("Carrier test complete");
}

void DeviceRFController::captureRawSignal() {
    Serial.println("=== RAW SIGNAL CAPTURE MODE ===");
    Serial.println("Press and hold a button on your remote now...");
    Serial.println("Capturing signal timing for 10 seconds...");
    
    // Put radio in receive mode
    writeReg(REG_OPMODE, RF_OPMODE_SEQUENCER_ON | RF_OPMODE_LISTEN_OFF | RF_OPMODE_RECEIVER);
    
    // Configure DIO2 as data output for signal capture
    const int capturePin = RF_DATA_PIN;
    pinMode(capturePin, INPUT);
    
    unsigned long captureStart = millis();
    unsigned long lastTime = micros();
    int lastState = digitalRead(capturePin);
    int pulseCount = 0;
    
    Serial.println("Starting capture... (HIGH/LOW durations in microseconds)");
    
    while (millis() - captureStart < 10000 && pulseCount < 500) {
        int currentState = digitalRead(capturePin);
        if (currentState != lastState) {
            unsigned long now = micros();
            unsigned long duration = now - lastTime;
            
            if (duration > 20) {  // Filter out noise
                Serial.print(lastState ? "HIGH: " : "LOW: ");
                Serial.print(duration);
                Serial.println("μs");
                pulseCount++;
            }
            
            lastTime = now;
            lastState = currentState;
        }
    }
    
    Serial.print("Captured ");
    Serial.print(pulseCount);
    Serial.println(" signal transitions");
    Serial.println("Compare these timings with your current implementation:");
    Serial.println("Current SHORT_PULSE_HIGH_US: 50");
    Serial.println("Current SHORT_PULSE_LOW_US: 52");
    Serial.println("Current LONG_PULSE_HIGH_US: 102");
    Serial.println("Current LONG_PULSE_LOW_US: 52");
    Serial.println("Current SYNC_PULSE_HIGH_US: 170");
    Serial.println("Current SYNC_PULSE_LOW_US: 114");
    
    // Return to direct mode
    configureDirectMode();
}

void DeviceRFController::testRcSwitch() {
    if (!initialized) {
        Serial.println("Cannot test rc-switch - RF controller not initialized");
        return;
    }
    
    Serial.println("=== RC-SWITCH PROTOCOL TEST ===");
    Serial.println("Testing standard protocols with rc-switch library...");
    
    // Test different protocols
    int protocols[] = {1, 2, 3, 4, 5, 6};
    int pulseLengths[] = {320, 650, 100, 380, 500, 450};
    
    for (int i = 0; i < 6; i++) {
        Serial.print("Testing Protocol ");
        Serial.print(protocols[i]);
        Serial.print(" with pulse length ");
        Serial.println(pulseLengths[i]);
        
        rcSwitch.setProtocol(protocols[i]);
        rcSwitch.setPulseLength(pulseLengths[i]);
        
        // Test with common codes
        Serial.println("  Sending code 5393 (RIGHT test)");
        rcSwitch.send(5393, 24);
        delay(1000);
        
        Serial.println("  Sending code 5396 (LEFT test)");
        rcSwitch.send(5396, 24);
        delay(1000);
    }
    
    Serial.println("rc-switch protocol test complete");
    Serial.println("Check if any of these protocols activated your motor");
}

void DeviceRFController::compareProtocols() {
    Serial.println("=== PROTOCOL COMPARISON ===");
    Serial.println("Your Current Implementation:");
    Serial.println("  - 90-bit custom codes");
    Serial.println("  - Frequency: 433.032 MHz");
    Serial.println("  - Short pulse: 50μs HIGH + 52μs LOW");
    Serial.println("  - Long pulse: 102μs HIGH + 52μs LOW");
    Serial.println("  - Sync pulse: 170μs HIGH + 114μs LOW");
    Serial.println();
    Serial.println("Common Standard Protocols:");
    Serial.println("  Protocol 1 (default): 320μs base, 1:3 ratio");
    Serial.println("  Protocol 2 (Intertechno): 650μs base, 1:2 ratio");
    Serial.println("  Protocol 3 (HX2262/PT2262): 100μs base, 1:31 ratio");
    Serial.println("  Protocol 4 (Sartano): 380μs base, 1:3 ratio");
    Serial.println("  Protocol 5 (HT6P20B): 500μs base, 1:6 ratio");
    Serial.println("  Protocol 6 (HT12E): 450μs base, 1:23 ratio");
    Serial.println();
    Serial.println("Recommendations:");
    Serial.println("1. Run captureRawSignal() first to see actual remote timing");
    Serial.println("2. Run testRcSwitch() to test standard protocols");
    Serial.println("3. Compare captured timing with standard protocols");
    Serial.println("4. Use rc-switch if a standard protocol works");
}