#ifndef DATA_MODELS_H
#define DATA_MODELS_H

struct GPSData {
    float latitude;
    float longitude;
    float altitude;
    int satellites;
    bool hasFix;
    unsigned long timestamp;
};

class SystemConfig {
public:
    static inline const char* VERSION = "1.0.0-dev";
    static constexpr long SERIAL_BAUD_RATE = 115200;
    static constexpr float HEADING_TOLERANCE = 15.0f;
    static constexpr float MIN_CORRECTION_INTERVAL = 2000.0f;
    static constexpr float MIN_DISTANCE_METERS = 5.0f;
    static constexpr int BUZZER_PIN = 4;
    static constexpr int GPS_RX_PIN = 2;
    static constexpr int GPS_TX_PIN = 3;
    static constexpr uint8_t SCREEN_ADDRESS = 0x3C;
};

#endif