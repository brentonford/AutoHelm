#include "Remote.h"

namespace ButtonCommands {
    constexpr const char* right     = "08696a8";
    constexpr const char* left      = "0269568";
    constexpr const char* up        = "0469428";
    constexpr const char* down      = "806a5a8";
    constexpr const char* motor     = "4068da8";
    constexpr const char* momentary = "10693a8";
    constexpr const char* release   = "00e9590";
}

Remote::Remote(CC1101& radio, uint8_t gdo0Pin)
    : _radio(radio)
    , _gdo0Pin(gdo0Pin)
    , _pmLock(nullptr)
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

    esp_pm_lock_create(ESP_PM_APB_FREQ_MAX, 0, "rmt", &_pmLock);

    buildPayloads();

    _initialized = true;
    Serial.println("[Remote] Ready");
    return true;
}

void Remote::buildPayloads() {
    const char* commands[] = {
        ButtonCommands::right,
        ButtonCommands::left,
        ButtonCommands::up,
        ButtonCommands::down,
        ButtonCommands::motor,
        ButtonCommands::momentary,
        ButtonCommands::release
    };

    for (uint8_t i = 0; i < static_cast<uint8_t>(Button::Count); i++) {
        snprintf(_payloads[i], sizeof(_payloads[i]), "%s%s%s%s",
            RemoteProtocol::preamble,
            RemoteProtocol::syncWord,
            DEVICE_ID,
            commands[i]);
    }
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

    _rmtItems[itemIndex].duration0 = 0;
    _rmtItems[itemIndex].level0 = 0;
    _rmtItems[itemIndex].duration1 = 0;
    _rmtItems[itemIndex].level1 = 0;

    return itemIndex;
}

void Remote::transmitBurst(Button button) {
    uint8_t index = static_cast<uint8_t>(button);
    if (index >= static_cast<uint8_t>(Button::Count))
        return;

    uint16_t itemCount = buildManchesterItems(_payloads[index]);

    _radio.startTx();
    rmt_write_items(RmtConfig::txChannel, _rmtItems, itemCount + 1, true);
    rmt_wait_tx_done(RmtConfig::txChannel, portMAX_DELAY);
    _radio.stopTx();
}

void Remote::transmitSingle(Button button) {
    if (!_initialized)
        return;

    Serial.printf("[TX] %s\n", buttonName(button));

    if (_pmLock)
        esp_pm_lock_acquire(_pmLock);

    transmitBurst(button);

    if (_pmLock)
        esp_pm_lock_release(_pmLock);
}

void Remote::transmitHold(Button button, uint16_t durationMs) {
    if (!_initialized)
        return;

    if (button == Button::Release)
        return;

    Serial.printf("[TX] HOLD %s (%dms)\n", buttonName(button), durationMs);

    if (_pmLock)
        esp_pm_lock_acquire(_pmLock);

    uint32_t startTime = millis();
    uint32_t burstCount = 0;
    
    while ((millis() - startTime) < durationMs) {
        transmitBurst(button);
        burstCount++;
        delay(RemoteProtocol::burstGapMs);
    }

    Serial.printf("[TX] RELEASE (sent %d bursts)\n", burstCount);
    transmitBurst(Button::Release);

    if (_pmLock)
        esp_pm_lock_release(_pmLock);
}

const char* Remote::buttonName(Button button) {
    switch (button) {
        case Button::Right:     return "RIGHT";
        case Button::Left:      return "LEFT";
        case Button::Up:        return "UP";
        case Button::Down:      return "DOWN";
        case Button::Motor:     return "MOTOR";
        case Button::Momentary: return "MOMENTARY";
        case Button::Release:   return "RELEASE";
        default:                return "UNKNOWN";
    }
}