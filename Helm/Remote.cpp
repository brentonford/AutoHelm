#include "Remote.h"
#include <Preferences.h>
#include <ctype.h>
#include <driver/gpio.h>
#include <string.h>

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
    , _initialized(false)
    , _transmitterReady(false)
    , _receiverOn(false)
    , _isrAttached(false)
    , _pairLockHeld(false)
    , _idFromNvs(false)
    , _pairing(false)
    , _pairStartMs(0)
    , _recentMs(0)
    , _lastMismatchMs(0)
    , _event(PairEvent::None)
    , _haveEdge(false)
    , _lastEdgeUs(0)
    , _lastEdgeLevel(0)
    , _pulseCount(0) {
    _deviceId[0] = '\0';
    _firstButton[0] = '\0';
    _firstId[0] = '\0';
    _recentButton[0] = '\0';
    _recentId[0] = '\0';
    _eventButton[0] = '\0';
    _eventId[0] = '\0';
}

bool Remote::installTransmitter() {
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

    _transmitterReady = true;
    return true;
}

bool Remote::begin() {
    loadDeviceId();

    if (!installTransmitter()) {
        return false;
    }

    esp_pm_lock_create(ESP_PM_APB_FREQ_MAX, 0, "rmt", &_pmLock);

    buildPayloads();

    _initialized = true;
    Serial.printf("[Remote] Ready (device id %s)\n", hasDeviceId() ? _deviceId : "not set");
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

    const char* id = hasDeviceId() ? _deviceId : "000000000000";

    for (uint8_t i = 0; i < static_cast<uint8_t>(Button::Count); i++) {
        snprintf(_payloads[i], sizeof(_payloads[i]), "%s%s%s%s",
            RemoteProtocol::preamble,
            RemoteProtocol::syncWord,
            id,
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

    ensureTransmitter();
    if (!hasDeviceId()) {
        Serial.println("[Remote] No device id — capture the handset before transmitting");
        return;
    }

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

    ensureTransmitter();
    if (!hasDeviceId()) {
        Serial.println("[Remote] No device id — capture the handset before transmitting");
        return;
    }

    if (button == Button::Release)
        return;

    uint16_t effectiveDuration = max(durationMs, RemoteProtocol::minReliableHoldMs);
    
    Serial.printf("[TX] HOLD %s (%dms)\n", buttonName(button), effectiveDuration);

    if (_pmLock)
        esp_pm_lock_acquire(_pmLock);

    uint32_t startTime = millis();
    uint32_t burstCount = 0;
    
    while ((millis() - startTime) < effectiveDuration) {
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

namespace {

constexpr uint16_t kEdgeCapacity = 768;
constexpr uint32_t kPairTimeoutMs = 45000;
constexpr uint32_t kRepeatWindowMs = 700;
constexpr uint32_t kMismatchWindowMs = 1000;

volatile uint32_t gEdgeTime[kEdgeCapacity];
volatile uint8_t gEdgeLevel[kEdgeCapacity];
volatile uint16_t gEdgeHead = 0;
volatile uint16_t gEdgeTail = 0;
volatile bool gEdgeOverflow = false;
portMUX_TYPE gEdgeMux = portMUX_INITIALIZER_UNLOCKED;
uint8_t gPairPin = 0;

void IRAM_ATTR pairEdgeIsr() {
    uint32_t now = micros();
    uint8_t level = static_cast<uint8_t>(gpio_get_level(static_cast<gpio_num_t>(gPairPin)));
    portENTER_CRITICAL_ISR(&gEdgeMux);
    uint16_t next = static_cast<uint16_t>((gEdgeHead + 1) % kEdgeCapacity);
    if (next == gEdgeTail) {
        gEdgeOverflow = true;
    } else {
        gEdgeTime[gEdgeHead] = now;
        gEdgeLevel[gEdgeHead] = level;
        gEdgeHead = next;
    }
    portEXIT_CRITICAL_ISR(&gEdgeMux);
}

bool isTwelveHex(const char* text) {
    if (!text) return false;
    bool nonzero = false;
    for (int i = 0; i < 12; i++) {
        if (!isxdigit(static_cast<unsigned char>(text[i]))) return false;
        if (text[i] != '0') nonzero = true;
    }
    return text[12] == '\0' && nonzero;
}

void upperHex(char* text) {
    for (char* p = text; *p; ++p) {
        *p = static_cast<char>(toupper(static_cast<unsigned char>(*p)));
    }
}

const char* buttonForCode(const char* code) {
    struct Entry { const char* code; const char* name; };
    const Entry table[] = {
        { ButtonCommands::right, "RIGHT" },
        { ButtonCommands::left, "LEFT" },
        { ButtonCommands::up, "UP" },
        { ButtonCommands::down, "DOWN" },
        { ButtonCommands::motor, "MOTOR" },
        { ButtonCommands::momentary, "MOMENTARY" },
        { ButtonCommands::release, "RELEASE" }
    };
    for (const Entry& entry : table) {
        if (strncasecmp(code, entry.code, 7) == 0) return entry.name;
    }
    return nullptr;
}

void syncBits(uint8_t out[32]) {
    const char* sync = RemoteProtocol::syncWord;
    int bit = 0;
    for (int i = 0; sync[i] != '\0' && bit < 32; i++) {
        uint8_t nibble = 0;
        char c = sync[i];
        if (c >= '0' && c <= '9') nibble = static_cast<uint8_t>(c - '0');
        else if (c >= 'a' && c <= 'f') nibble = static_cast<uint8_t>(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') nibble = static_cast<uint8_t>(c - 'A' + 10);
        for (int shift = 3; shift >= 0; shift--) {
            out[bit++] = (nibble >> shift) & 0x01;
        }
    }
}

}  // namespace

void Remote::loadDeviceId() {
    _deviceId[0] = '\0';
    _idFromNvs = false;

    Preferences prefs;
    if (prefs.begin("remote", true)) {
        String stored = prefs.getString("devid", "");
        prefs.end();
        if (isTwelveHex(stored.c_str())) {
            strncpy(_deviceId, stored.c_str(), sizeof(_deviceId) - 1);
            _deviceId[sizeof(_deviceId) - 1] = '\0';
            upperHex(_deviceId);
            _idFromNvs = true;
            Serial.printf("[Remote] Loaded device id %s from NVS\n", _deviceId);
            return;
        }
    }

    if (isTwelveHex(DEVICE_ID)) {
        strncpy(_deviceId, DEVICE_ID, sizeof(_deviceId) - 1);
        _deviceId[sizeof(_deviceId) - 1] = '\0';
        upperHex(_deviceId);
        Serial.printf("[Remote] Using firmware device id %s\n", _deviceId);
    }
}

void Remote::saveDeviceId(const char* id) {
    strncpy(_deviceId, id, sizeof(_deviceId) - 1);
    _deviceId[sizeof(_deviceId) - 1] = '\0';
    upperHex(_deviceId);
    _idFromNvs = true;

    Preferences prefs;
    if (!prefs.begin("remote", false)) {
        Serial.println("[Remote] NVS open failed — id kept for this boot only");
        return;
    }
    prefs.putString("devid", _deviceId);
    prefs.end();
    Serial.printf("[Remote] Saved device id %s\n", _deviceId);
}

void Remote::clearStoredDeviceId() {
    Preferences prefs;
    if (prefs.begin("remote", false)) {
        prefs.remove("devid");
        prefs.end();
    }
    loadDeviceId();
    buildPayloads();
    Serial.println("[Remote] Cleared saved device id");
}

void Remote::ensureTransmitter() {
    if (_pairing || _receiverOn || _isrAttached) {
        stopPairingSession(true);
        return;
    }
    if (!_transmitterReady) {
        installTransmitter();
    }
}

bool Remote::prepareReceiver() {
    if (_transmitterReady) {
        rmt_driver_uninstall(RmtConfig::txChannel);
        gpio_reset_pin(static_cast<gpio_num_t>(_gdo0Pin));
        _transmitterReady = false;
    }

    pinMode(_gdo0Pin, INPUT);
    if (!_radio.startRx()) {
        Serial.println("[Remote] RX start failed");
        installTransmitter();
        return false;
    }
    _receiverOn = true;

    portENTER_CRITICAL(&gEdgeMux);
    gEdgeHead = 0;
    gEdgeTail = 0;
    gEdgeOverflow = false;
    portEXIT_CRITICAL(&gEdgeMux);

    gPairPin = _gdo0Pin;
    attachInterrupt(digitalPinToInterrupt(_gdo0Pin), pairEdgeIsr, CHANGE);
    _isrAttached = true;

    if (_pmLock && !_pairLockHeld) {
        esp_pm_lock_acquire(_pmLock);
        _pairLockHeld = true;
    }
    return true;
}

void Remote::stopPairingSession(bool recordCancel) {
    if (_isrAttached) {
        detachInterrupt(digitalPinToInterrupt(_gdo0Pin));
        _isrAttached = false;
    }
    if (_receiverOn) {
        _radio.stopRx();
        _receiverOn = false;
    }
    if (!_transmitterReady) {
        installTransmitter();
    }
    if (_pmLock && _pairLockHeld) {
        esp_pm_lock_release(_pmLock);
        _pairLockHeld = false;
    }
    _pairing = false;
    _haveEdge = false;
    _pulseCount = 0;
    if (recordCancel) {
        _event = PairEvent::Cancelled;
    }
}

void Remote::resetCaptureState() {
    _firstButton[0] = '\0';
    _firstId[0] = '\0';
    _recentButton[0] = '\0';
    _recentId[0] = '\0';
    _recentMs = 0;
    _lastMismatchMs = 0;
    _event = PairEvent::None;
    _eventButton[0] = '\0';
    _eventId[0] = '\0';
    _haveEdge = false;
    _pulseCount = 0;
}

bool Remote::startPairing() {
    if (!_initialized) return false;
    if (_pairing) {
        stopPairingSession(false);
    }
    resetCaptureState();
    if (!prepareReceiver()) return false;
    _pairing = true;
    _pairStartMs = millis();
    Serial.println("[Remote] Listening for handset");
    return true;
}

void Remote::cancelPairing() {
    if (!_pairing && !_receiverOn && !_isrAttached) return;
    stopPairingSession(false);
    Serial.println("[Remote] Pairing cancelled");
}

void Remote::noteCapture(const char* button, const char* id) {
    if (!_pairing) return;
    if (strcmp(button, "RELEASE") == 0) return;

    uint32_t now = millis();
    bool repeat = strcmp(button, _recentButton) == 0
        && strcmp(id, _recentId) == 0
        && (now - _recentMs) < kRepeatWindowMs;
    strncpy(_recentButton, button, sizeof(_recentButton) - 1);
    _recentButton[sizeof(_recentButton) - 1] = '\0';
    strncpy(_recentId, id, sizeof(_recentId) - 1);
    _recentId[sizeof(_recentId) - 1] = '\0';
    _recentMs = now;
    if (repeat) return;

    if (_firstId[0] == '\0') {
        strncpy(_firstButton, button, sizeof(_firstButton) - 1);
        _firstButton[sizeof(_firstButton) - 1] = '\0';
        strncpy(_firstId, id, sizeof(_firstId) - 1);
        _firstId[sizeof(_firstId) - 1] = '\0';
        strncpy(_eventButton, button, sizeof(_eventButton) - 1);
        _eventButton[sizeof(_eventButton) - 1] = '\0';
        strncpy(_eventId, id, sizeof(_eventId) - 1);
        _eventId[sizeof(_eventId) - 1] = '\0';
        _event = PairEvent::Heard;
        Serial.printf("[Remote] Heard %s id=%s\n", button, id);
        return;
    }

    if (strcmp(id, _firstId) != 0) {
        if ((now - _lastMismatchMs) >= kMismatchWindowMs) {
            strncpy(_eventId, id, sizeof(_eventId) - 1);
            _eventId[sizeof(_eventId) - 1] = '\0';
            _eventButton[0] = '\0';
            _event = PairEvent::Mismatch;
            _lastMismatchMs = now;
            Serial.printf("[Remote] Mismatch id=%s (wanted %s)\n", id, _firstId);
        }
        return;
    }

    if (strcmp(button, _firstButton) == 0) return;

    saveDeviceId(id);
    buildPayloads();
    strncpy(_eventId, _deviceId, sizeof(_eventId) - 1);
    _eventId[sizeof(_eventId) - 1] = '\0';
    strncpy(_eventButton, button, sizeof(_eventButton) - 1);
    _eventButton[sizeof(_eventButton) - 1] = '\0';
    stopPairingSession(false);
    _event = PairEvent::Confirmed;
    Serial.printf("[Remote] Paired id=%s after %s\n", _deviceId, button);
}

void Remote::finishTrain() {
    if (_pulseCount < 40) {
        _pulseCount = 0;
        return;
    }

    static uint8_t halves[640];
    int halfCount = 0;
    for (int i = 0; i < _pulseCount && halfCount < 640; i++) {
        uint16_t width = _pulseWidth[i];
        int copies = 0;
        if (width >= 26 && width <= 78) copies = 1;
        else if (width <= 150) copies = 2;
        for (int c = 0; c < copies && halfCount < 640; c++) {
            halves[halfCount++] = _pulseLevel[i];
        }
    }
    _pulseCount = 0;
    if (halfCount < 216) return;

    uint8_t sync[32];
    syncBits(sync);
    static uint8_t bits[320];

    auto acceptRun = [&](int bitCount) -> bool {
        if (bitCount < 108) return false;
        for (int start = 0; start + 108 <= bitCount; start++) {
            bool found = true;
            for (int b = 0; b < 32; b++) {
                if (bits[start + b] != sync[b]) {
                    found = false;
                    break;
                }
            }
            if (!found) continue;

            int cursor = start + 32;
            char id[13];
            char code[8];
            for (int n = 0; n < 12; n++) {
                uint8_t nibble = 0;
                for (int b = 0; b < 4; b++) {
                    nibble = static_cast<uint8_t>((nibble << 1) | bits[cursor++]);
                }
                id[n] = "0123456789ABCDEF"[nibble];
            }
            id[12] = '\0';
            for (int n = 0; n < 7; n++) {
                uint8_t nibble = 0;
                for (int b = 0; b < 4; b++) {
                    nibble = static_cast<uint8_t>((nibble << 1) | bits[cursor++]);
                }
                code[n] = "0123456789abcdef"[nibble];
            }
            code[7] = '\0';

            const char* name = buttonForCode(code);
            if (name == nullptr || !isTwelveHex(id)) continue;
            noteCapture(name, id);
            return true;
        }
        return false;
    };

    for (int invert = 0; invert < 2; invert++) {
        for (int phase = 0; phase < 2; phase++) {
            int bitCount = 0;
            for (int i = phase; i + 1 < halfCount; i += 2) {
                uint8_t a = halves[i] ^ static_cast<uint8_t>(invert);
                uint8_t b = halves[i + 1] ^ static_cast<uint8_t>(invert);
                int bit = -1;
                if (a == 0 && b == 1) bit = 0;
                else if (a == 1 && b == 0) bit = 1;

                if (bit < 0 || bitCount == 320) {
                    if (acceptRun(bitCount)) return;
                    bitCount = 0;
                    if (bit < 0) continue;
                }
                bits[bitCount++] = static_cast<uint8_t>(bit);
            }
            if (acceptRun(bitCount)) return;
        }
    }
}

void Remote::noteEdge(uint32_t timeUs, uint8_t level) {
    if (!_haveEdge) {
        _lastEdgeUs = timeUs;
        _lastEdgeLevel = level;
        _haveEdge = true;
        return;
    }

    uint32_t width = timeUs - _lastEdgeUs;
    uint8_t pulseLevel = _lastEdgeLevel;
    _lastEdgeUs = timeUs;
    _lastEdgeLevel = level;

    if (width < 20) return;
    if (width > 180) {
        finishTrain();
        return;
    }
    if (_pulseCount >= kMaxPulses) {
        finishTrain();
        return;
    }
    _pulseWidth[_pulseCount] = static_cast<uint16_t>(width);
    _pulseLevel[_pulseCount] = pulseLevel;
    _pulseCount++;
}

void Remote::drainEdges() {
    if (gEdgeOverflow) {
        portENTER_CRITICAL(&gEdgeMux);
        gEdgeTail = gEdgeHead;
        gEdgeOverflow = false;
        portEXIT_CRITICAL(&gEdgeMux);
        _haveEdge = false;
        _pulseCount = 0;
        return;
    }

    uint32_t times[64];
    uint8_t levels[64];
    for (;;) {
        portENTER_CRITICAL(&gEdgeMux);
        int count = 0;
        while (gEdgeTail != gEdgeHead && count < 64) {
            times[count] = gEdgeTime[gEdgeTail];
            levels[count] = gEdgeLevel[gEdgeTail];
            gEdgeTail = static_cast<uint16_t>((gEdgeTail + 1) % kEdgeCapacity);
            count++;
        }
        portEXIT_CRITICAL(&gEdgeMux);
        if (count == 0) return;
        for (int i = 0; i < count; i++) {
            noteEdge(times[i], levels[i]);
        }
    }
}

PairEvent Remote::pollPairing(char* button, size_t buttonLen, char* id, size_t idLen) {
    if (button && buttonLen > 0) button[0] = '\0';
    if (id && idLen > 0) id[0] = '\0';

    if (_pairing) {
        drainEdges();
        if ((millis() - _pairStartMs) >= kPairTimeoutMs) {
            stopPairingSession(false);
            _event = PairEvent::Timeout;
            Serial.println("[Remote] Pairing timed out");
        }
    }

    PairEvent event = _event;
    _event = PairEvent::None;
    if (button && buttonLen > 0) {
        strncpy(button, _eventButton, buttonLen - 1);
        button[buttonLen - 1] = '\0';
    }
    if (id && idLen > 0) {
        strncpy(id, _eventId, idLen - 1);
        id[idLen - 1] = '\0';
    }
    return event;
}