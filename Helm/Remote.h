#pragma once

#include <Arduino.h>
#include <driver/rmt.h>
#include <esp_pm.h>
#include "CC1101.h"
#include "secrets.h"

namespace RmtConfig {
    constexpr rmt_channel_t txChannel = RMT_CHANNEL_0;
    constexpr uint8_t clkDiv = 80;  // 80 MHz / 80 = 1µs resolution
}

namespace ManchesterTiming {
    constexpr uint16_t halfBitUs = 52;
    constexpr uint16_t bitPeriodUs = 104;
    constexpr uint16_t maxBits = 140;
}

namespace RemoteProtocol {
    constexpr const char* preamble = "2aaaaaaa";
    constexpr const char* syncWord = "d391d391";
    constexpr uint16_t burstGapMs = 68;
    constexpr uint16_t defaultHoldMs = 1000;
    constexpr uint16_t minReliableHoldMs = 500;
}

enum class Button : uint8_t {
    Right,
    Left,
    Up,
    Down,
    Motor,
    Momentary,
    Release,
    Count
};

enum class PairEvent : uint8_t {
    None,
    Heard,
    Confirmed,
    Mismatch,
    Timeout,
    Cancelled
};

class Remote {
public:
    Remote(CC1101& radio, uint8_t gdo0Pin);

    bool begin();
    void transmitSingle(Button button);
    void transmitHold(Button button, uint16_t durationMs = RemoteProtocol::defaultHoldMs);

    bool startPairing();
    void cancelPairing();
    bool isPairing() const { return _pairing; }
    PairEvent pollPairing(char* button, size_t buttonLen, char* id, size_t idLen);

    bool hasDeviceId() const { return _deviceId[0] != '\0'; }
    const char* deviceId() const { return _deviceId; }
    bool deviceIdFromNvs() const { return _idFromNvs; }
    void clearStoredDeviceId();

private:
    CC1101& _radio;
    uint8_t _gdo0Pin;
    rmt_item32_t _rmtItems[ManchesterTiming::maxBits + 1];
    esp_pm_lock_handle_t _pmLock;
    bool _initialized;
    bool _transmitterReady;
    bool _receiverOn;
    bool _isrAttached;
    bool _pairLockHeld;

    char _payloads[static_cast<uint8_t>(Button::Count)][38];
    char _deviceId[13];
    bool _idFromNvs;

    bool _pairing;
    uint32_t _pairStartMs;
    char _firstButton[12];
    char _firstId[13];
    char _recentButton[12];
    char _recentId[13];
    uint32_t _recentMs;
    uint32_t _lastMismatchMs;
    PairEvent _event;
    char _eventButton[12];
    char _eventId[13];

    bool _haveEdge;
    uint32_t _lastEdgeUs;
    uint8_t _lastEdgeLevel;
    static constexpr int kMaxPulses = 320;
    uint16_t _pulseWidth[kMaxPulses];
    uint8_t _pulseLevel[kMaxPulses];
    int _pulseCount;

    bool installTransmitter();
    void loadDeviceId();
    void saveDeviceId(const char* id);
    void buildPayloads();
    void ensureTransmitter();
    bool prepareReceiver();
    void stopPairingSession(bool recordCancel);
    void resetCaptureState();
    void drainEdges();
    void noteEdge(uint32_t timeUs, uint8_t level);
    void finishTrain();
    void noteCapture(const char* button, const char* id);
    uint8_t hexCharToNibble(char c);
    uint16_t buildManchesterItems(const char* hexPayload);
    void transmitBurst(Button button);
    const char* buttonName(Button button);
};