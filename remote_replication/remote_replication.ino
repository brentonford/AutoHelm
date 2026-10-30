/*
 * Remote - ESP32 + CC1101
 * 
 * Protocol: 2-FSK with Manchester Code encoding
 * Frequency: 433.017 MHz
 * Bit timing: 104µs per bit (two 52µs half-bits)
 */

#include <SPI.h>
#include <driver/rmt.h>
#include <esp_pm.h>

// Pin Configuration
constexpr uint8_t PIN_CS   = 5;
constexpr uint8_t PIN_GDO0 = 4;
constexpr uint8_t PIN_SCK  = 18;
constexpr uint8_t PIN_MISO = 19;
constexpr uint8_t PIN_MOSI = 23;

// RMT Configuration
constexpr rmt_channel_t RMT_TX_CHANNEL = RMT_CHANNEL_0;
constexpr uint8_t RMT_CLK_DIV = 80;  // 1µs resolution

// Manchester Timing
constexpr uint16_t HALF_BIT_US = 52;
constexpr uint16_t PACKET_BITS = 137;

namespace CC1101Reg {
    constexpr uint8_t IOCFG0   = 0x02;
    constexpr uint8_t FIFOTHR  = 0x03;
    constexpr uint8_t PKTCTRL0 = 0x08;
    constexpr uint8_t FSCTRL1  = 0x0B;
    constexpr uint8_t FREQ2    = 0x0D;
    constexpr uint8_t FREQ1    = 0x0E;
    constexpr uint8_t FREQ0    = 0x0F;
    constexpr uint8_t MDMCFG4  = 0x10;
    constexpr uint8_t MDMCFG3  = 0x11;
    constexpr uint8_t MDMCFG2  = 0x12;
    constexpr uint8_t MDMCFG1  = 0x13;
    constexpr uint8_t MDMCFG0  = 0x14;
    constexpr uint8_t DEVIATN  = 0x15;
    constexpr uint8_t MCSM0    = 0x18;
    constexpr uint8_t FOCCFG   = 0x19;
    constexpr uint8_t AGCCTRL2 = 0x1B;
    constexpr uint8_t AGCCTRL1 = 0x1C;
    constexpr uint8_t AGCCTRL0 = 0x1D;
    constexpr uint8_t FREND1   = 0x21;
    constexpr uint8_t FREND0   = 0x22;
    constexpr uint8_t FSCAL3   = 0x23;
    constexpr uint8_t FSCAL2   = 0x24;
    constexpr uint8_t FSCAL1   = 0x25;
    constexpr uint8_t FSCAL0   = 0x26;
    constexpr uint8_t TEST2    = 0x2C;
    constexpr uint8_t TEST1    = 0x2D;
    constexpr uint8_t TEST0    = 0x2E;
    constexpr uint8_t VERSION  = 0x31;
    constexpr uint8_t SRES     = 0x30;
    constexpr uint8_t SCAL     = 0x33;
    constexpr uint8_t STX      = 0x35;
    constexpr uint8_t SIDLE    = 0x36;
    constexpr uint8_t PATABLE  = 0x3E;
}

enum class Button : uint8_t {
    RIGHT,
    LEFT,
    UP,
    DOWN,
    MOTOR,
    MOMENTARY,
    RELEASE,
    COUNT
};

struct ButtonCode {
    const char* name;
    const char* payload;
};

const ButtonCode BUTTONS[] = {
    {"RIGHT",     "2aaaaaaad391d391" DEVICE_ID "08696a8"},
    {"LEFT",      "2aaaaaaad391d391" DEVICE_ID "0269568"},
    {"UP",        "2aaaaaaad391d391" DEVICE_ID "0469428"},
    {"DOWN",      "2aaaaaaad391d391" DEVICE_ID "806a5a8"},
    {"MOTOR",     "2aaaaaaad391d391" DEVICE_ID "4068da8"},
    {"MOMENTARY", "2aaaaaaad391d391" DEVICE_ID "10693a8"},
    {"RELEASE",   "2aaaaaaad391d391" DEVICE_ID "00e9590"},
};

class CC1101 {
private:
    SPISettings spiSettings{4000000, MSBFIRST, SPI_MODE0};
    
    void select() { digitalWrite(PIN_CS, LOW); delayMicroseconds(1); }
    void deselect() { digitalWrite(PIN_CS, HIGH); delayMicroseconds(1); }
    void waitMiso() { while (digitalRead(PIN_MISO)) delayMicroseconds(1); }

public:
    void writeReg(uint8_t addr, uint8_t value) {
        SPI.beginTransaction(spiSettings);
        select();
        waitMiso();
        SPI.transfer(addr);
        SPI.transfer(value);
        deselect();
        SPI.endTransaction();
    }
    
    uint8_t readStatusReg(uint8_t addr) {
        SPI.beginTransaction(spiSettings);
        select();
        waitMiso();
        SPI.transfer(addr | 0xC0);
        uint8_t value = SPI.transfer(0x00);
        deselect();
        SPI.endTransaction();
        return value;
    }
    
    void strobe(uint8_t cmd) {
        SPI.beginTransaction(spiSettings);
        select();
        waitMiso();
        SPI.transfer(cmd);
        deselect();
        SPI.endTransaction();
    }
    
    void reset() {
        deselect();
        delayMicroseconds(5);
        select();
        delayMicroseconds(10);
        deselect();
        delayMicroseconds(45);
        
        SPI.beginTransaction(spiSettings);
        select();
        waitMiso();
        SPI.transfer(CC1101Reg::SRES);
        deselect();
        SPI.endTransaction();
        delay(10);
    }
    
    bool init() {
        pinMode(PIN_CS, OUTPUT);
        digitalWrite(PIN_CS, HIGH);
        SPI.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
        delay(100);
        
        reset();
        
        uint8_t version = readStatusReg(CC1101Reg::VERSION);
        Serial.printf("[CC1101] Version: 0x%02X\n", version);
        if (version != 0x14 && version != 0x04)
            return false;
        
        // 433.017 MHz
        writeReg(CC1101Reg::FREQ2, 0x10);
        writeReg(CC1101Reg::FREQ1, 0xA7);
        writeReg(CC1101Reg::FREQ0, 0x6C);
        
        // 2-FSK, async serial mode
        writeReg(CC1101Reg::MDMCFG4, 0xC9);
        writeReg(CC1101Reg::MDMCFG3, 0x30);
        writeReg(CC1101Reg::MDMCFG2, 0x00);
        writeReg(CC1101Reg::MDMCFG1, 0x00);
        writeReg(CC1101Reg::MDMCFG0, 0x00);
        writeReg(CC1101Reg::DEVIATN, 0x40);  // ~25 kHz deviation
        
        writeReg(CC1101Reg::FREND0, 0x10);
        writeReg(CC1101Reg::MCSM0, 0x18);
        writeReg(CC1101Reg::FOCCFG, 0x16);
        writeReg(CC1101Reg::AGCCTRL2, 0x43);
        writeReg(CC1101Reg::AGCCTRL1, 0x40);
        writeReg(CC1101Reg::AGCCTRL0, 0x91);
        writeReg(CC1101Reg::FSCAL3, 0xE9);
        writeReg(CC1101Reg::FSCAL2, 0x2A);
        writeReg(CC1101Reg::FSCAL1, 0x00);
        writeReg(CC1101Reg::FSCAL0, 0x1F);
        writeReg(CC1101Reg::TEST2, 0x81);
        writeReg(CC1101Reg::TEST1, 0x35);
        writeReg(CC1101Reg::TEST0, 0x09);
        
        writeReg(CC1101Reg::IOCFG0, 0x2E);   // High-Z for async TX
        writeReg(CC1101Reg::PKTCTRL0, 0x32); // Async serial mode
        writeReg(CC1101Reg::FSCTRL1, 0x06);
        writeReg(CC1101Reg::FREND1, 0x56);
        writeReg(CC1101Reg::FIFOTHR, 0x47);
        
        // Max TX power
        SPI.beginTransaction(spiSettings);
        select();
        waitMiso();
        SPI.transfer(CC1101Reg::PATABLE | 0x40);
        SPI.transfer(0xC0);
        deselect();
        SPI.endTransaction();
        
        strobe(CC1101Reg::SIDLE);
        delay(1);
        
        return true;
    }
    
    void startTx() {
        strobe(CC1101Reg::SIDLE);
        delayMicroseconds(100);
        strobe(CC1101Reg::SCAL);
        delay(1);
        strobe(CC1101Reg::STX);
        delayMicroseconds(500);
    }
    
    void stopTx() {
        strobe(CC1101Reg::SIDLE);
    }
};

class Remote {
private:
    CC1101 cc1101;
    rmt_item32_t rmtItems[PACKET_BITS + 4];
    esp_pm_lock_handle_t pmLock = nullptr;
    bool initialized = false;
    
    uint16_t burstGapMs = 68;
    uint16_t holdDurationMs = 1000;
    bool sendRelease = true;
    
    uint8_t hexNibble(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return 0;
    }
    
    uint16_t buildManchesterItems(const char* hex) {
        uint16_t idx = 0;
        size_t hexLen = strlen(hex);
        uint16_t bitCount = (hexLen * 4 > PACKET_BITS) ? PACKET_BITS : hexLen * 4;
        
        uint8_t nibble = 0;
        uint8_t nibblePos = 0;
        size_t hexIdx = 0;
        
        for (uint16_t currentBit = 0; currentBit < bitCount; currentBit++) {
            if (nibblePos == 0) {
                nibble = hexNibble(hex[hexIdx++]);
                nibblePos = 4;
            }
            
            nibblePos--;
            uint8_t bit = (nibble >> nibblePos) & 0x01;
            
            // Manchester: 104µs bit period (two 52µs half-bits)
            // Bit 0: LOW then HIGH (rising edge)
            // Bit 1: HIGH then LOW (falling edge)
            if (bit == 0) {
                rmtItems[idx].duration0 = HALF_BIT_US;
                rmtItems[idx].level0 = 0;
                rmtItems[idx].duration1 = HALF_BIT_US;
                rmtItems[idx].level1 = 1;
            } else {
                rmtItems[idx].duration0 = HALF_BIT_US;
                rmtItems[idx].level0 = 1;
                rmtItems[idx].duration1 = HALF_BIT_US;
                rmtItems[idx].level1 = 0;
            }
            idx++;
        }
        
        // Terminator
        rmtItems[idx].duration0 = 0;
        rmtItems[idx].level0 = 0;
        rmtItems[idx].duration1 = 0;
        rmtItems[idx].level1 = 0;
        
        return idx;
    }
    
    void transmitBurst(Button btn) {
        uint8_t i = static_cast<uint8_t>(btn);
        if (i >= static_cast<uint8_t>(Button::COUNT))
            return;
        
        uint16_t itemCount = buildManchesterItems(BUTTONS[i].payload);
        
        cc1101.startTx();
        rmt_write_items(RMT_TX_CHANNEL, rmtItems, itemCount + 1, true);
        rmt_wait_tx_done(RMT_TX_CHANNEL, portMAX_DELAY);
        cc1101.stopTx();
    }

public:
    bool begin() {
        Serial.println("Initializing...");
        
        if (!cc1101.init())
            return false;
        
        rmt_config_t config = {};
        config.rmt_mode = RMT_MODE_TX;
        config.channel = RMT_TX_CHANNEL;
        config.gpio_num = static_cast<gpio_num_t>(PIN_GDO0);
        config.clk_div = RMT_CLK_DIV;
        config.mem_block_num = 4;
        config.tx_config.idle_output_en = true;
        config.tx_config.idle_level = RMT_IDLE_LEVEL_LOW;
        config.tx_config.carrier_en = false;
        config.tx_config.loop_en = false;
        
        if (rmt_config(&config) != ESP_OK)
            return false;
        if (rmt_driver_install(RMT_TX_CHANNEL, 0, 0) != ESP_OK)
            return false;
        
        esp_pm_lock_create(ESP_PM_APB_FREQ_MAX, 0, "rmt", &pmLock);
        
        initialized = true;
        Serial.println("Ready...");
        return true;
    }
    
    void transmitSingle(Button btn) {
        if (!initialized) return;
        
        uint8_t i = static_cast<uint8_t>(btn);
        Serial.printf("[TX] %s\n", BUTTONS[i].name);
        
        if (pmLock) esp_pm_lock_acquire(pmLock);
        transmitBurst(btn);
        if (pmLock) esp_pm_lock_release(pmLock);
    }
    
    void transmitHold(Button btn) {
        if (!initialized) return;
        if (btn == Button::RELEASE) return;
        
        uint8_t i = static_cast<uint8_t>(btn);
        Serial.printf("[TX] HOLD %s (%dms)\n", BUTTONS[i].name, holdDurationMs);
        
        if (pmLock) esp_pm_lock_acquire(pmLock);
        
        uint32_t start = millis();
        while ((millis() - start) < holdDurationMs) {
            transmitBurst(btn);
            delay(burstGapMs);
        }
        
        if (sendRelease) {
            Serial.println("[TX] RELEASE");
            transmitBurst(Button::RELEASE);
        }
        
        if (pmLock) esp_pm_lock_release(pmLock);
    }
    
    void setBurstGap(uint16_t ms) { burstGapMs = ms; }
    void setHoldDuration(uint16_t ms) { holdDurationMs = ms; }
    void toggleRelease() { sendRelease = !sendRelease; }
};

Remote remote;

void setup() {
    Serial.begin(115200);
    delay(1000);

    
    Serial.println("\n=== Remote ===\n");
    
    if (!remote.begin()) {
        Serial.println("FATAL: Init failed");
        while (true) delay(1000);
    }
    
    Serial.println("Commands: R/L/U/D/M/S (hold), r/l/u/d/m/s (single), 0 (release)");
}

void loop() {
    if (!Serial.available())
        return;
    
    char c = Serial.read();
    
    switch (c) {
        case 'R': remote.transmitHold(Button::RIGHT); break;
        case 'L': remote.transmitHold(Button::LEFT); break;
        case 'U': remote.transmitHold(Button::UP); break;
        case 'D': remote.transmitHold(Button::DOWN); break;
        case 'M': remote.transmitHold(Button::MOTOR); break;
        case 'S': remote.transmitHold(Button::MOMENTARY); break;
        
        case 'r': remote.transmitSingle(Button::RIGHT); break;
        case 'l': remote.transmitSingle(Button::LEFT); break;
        case 'u': remote.transmitSingle(Button::UP); break;
        case 'd': remote.transmitSingle(Button::DOWN); break;
        case 'm': remote.transmitSingle(Button::MOTOR); break;
        case 's': remote.transmitSingle(Button::MOMENTARY); break;
        
        case '0': remote.transmitSingle(Button::RELEASE); break;
    }
}