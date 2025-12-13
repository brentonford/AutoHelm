#include "Remote.h"

Remote::Remote(CC1101& radio, uint8_t gdo0Pin)
    : _radio(radio)
    , _gdo0Pin(gdo0Pin)
    , _initialized(false) {
}

bool Remote::begin() {
    rmt_config_t config = {};
    config.rmt_mode = RMT_MODE_TX;
    config.channel = RmtConfig::txChannel;
    config.gpio_num = static_cast<gpio_num_t>(_gdo0Pin);
    config.clk_div = RmtConfig::clkDiv;
    config.mem_block_num = 4;
    config.tx_config.idle_output_en = true;
    config.tx_config.idle_level = RMT_IDLE_LEVEL_LOW;
    config.tx_config.carrier_en = false;
    config.tx_config.loop_en = false;

    if (rmt_config(&config) != ESP_OK) {
        Serial.println("[RMT] Config failed");
        return false;
    }

    if (rmt_driver_install(RmtConfig::txChannel, 0, 0) != ESP_OK) {
        Serial.println("[RMT] Driver install failed");
        return false;
    }

    _initialized = true;
    Serial.println("[RMT] Initialized for Manchester encoding");
    return true;
}

uint8_t Remote::hexCharToNibble(char c) {
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return 0;
}

uint16_t Remote::buildManchesterItems(const char* hexPayload) {
    uint16_t itemIndex = 0;
    size_t hexLen = strlen(hexPayload);
    uint16_t totalBits = hexLen * 4;

    if (totalBits > ManchesterTiming::maxBits)
        totalBits = ManchesterTiming::maxBits;

    uint8_t nibble = 0;
    uint8_t nibblePos = 0;
    size_t hexIndex = 0;

    for (uint16_t bitNum = 0; bitNum < totalBits; bitNum++) {
        if (nibblePos == 0) {
            nibble = hexCharToNibble(hexPayload[hexIndex++]);
            nibblePos = 4;
        }

        nibblePos--;
        uint8_t bit = (nibble >> nibblePos) & 0x01;

        // Manchester encoding:
        // Bit 0: LOW then HIGH (rising edge)
        // Bit 1: HIGH then LOW (falling edge)
        if (bit == 0) {
            _rmtItems[itemIndex].duration0 = ManchesterTiming::halfBitUs;
            _rmtItems[itemIndex].level0 = 0;
            _rmtItems[itemIndex].duration1 = ManchesterTiming::halfBitUs;
            _rmtItems[itemIndex].level1 = 1;
        } else {
            _rmtItems[itemIndex].duration0 = ManchesterTiming::halfBitUs;
            _rmtItems[itemIndex].level0 = 1;
            _rmtItems[itemIndex].duration1 = ManchesterTiming::halfBitUs;
            _rmtItems[itemIndex].level1 = 0;
        }
        itemIndex++;
    }

    // Terminator
    _rmtItems[itemIndex].duration0 = 0;
    _rmtItems[itemIndex].level0 = 0;
    _rmtItems[itemIndex].duration1 = 0;
    _rmtItems[itemIndex].level1 = 0;

    return itemIndex;
}

void Remote::transmitPayload(const char* hexPayload) {
    if (!_initialized)
        return;

    uint16_t itemCount = buildManchesterItems(hexPayload);

    _radio.startTx();
    rmt_write_items(RmtConfig::txChannel, _rmtItems, itemCount + 1, true);
    rmt_wait_tx_done(RmtConfig::txChannel, portMAX_DELAY);
    _radio.stopTx();
}