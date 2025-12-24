#include "GpsManager.h"

GpsManager::GpsManager(uint8_t rxPin, uint8_t txPin)
    : _rxPin(rxPin)
    , _txPin(txPin)
    , _serial(2)
    , _bufferIndex(0)
    , _initialized(false)
    , _lastReceiveTime(0)
    , _firstFixReceived(false)
    , _lastDebugTime(0)
    , _charCount(0)
    , _debugEnabled(false) {
}

bool GpsManager::begin() {
    _serial.begin(Config::gpsBaud, SERIAL_8N1, _rxPin, _txPin);
    _initialized = true;
    _lastReceiveTime = millis();
    Serial.println("[GPS] Initialized on UART2");
    return true;
}

void GpsManager::setDebugEnabled(bool enabled) {
    _debugEnabled = enabled;
    Serial.printf("[GPS] Debug output %s\n", enabled ? "ENABLED" : "DISABLED");
}

bool GpsManager::isDebugEnabled() const {
    return _debugEnabled;
}

void GpsManager::update() {
    if (!_initialized)
        return;

    uint32_t now = millis();

    while (_serial.available()) {
        char c = _serial.read();
        _charCount++;
        _lastReceiveTime = now;

        if (c == '$') {
            _bufferIndex = 0;
        }

        if (_bufferIndex < GpsConfig::bufferSize - 1) {
            _buffer[_bufferIndex++] = c;
            _buffer[_bufferIndex] = '\0';
        }

        if (c == '\n') {
            processBuffer();
            _bufferIndex = 0;
        }
    }

    if (_debugEnabled) {
        printDebugStatus();
    }
}

void GpsManager::printDebugStatus() {
    uint32_t now = millis();
    if ((now - _lastDebugTime) <= GpsConfig::debugPrintIntervalMs)
        return;

    if (_charCount > 0) {
        Serial.printf("[GPS] Received %d characters in last 5 seconds\n", _charCount);
    } else {
        Serial.println("[GPS] WARNING: No data received from GPS module!");
    }
    _charCount = 0;
    _lastDebugTime = now;
}

void GpsManager::processBuffer() {
    if (_buffer[0] != '$')
        return;

    if (_bufferIndex < 15)
        return;

    if (!validateChecksum(_buffer))
        return;

    // Support GP, GL, GA, GN talker IDs
    if (_buffer[1] != 'G')
        return;

    char talkerId = _buffer[2];
    if (talkerId != 'P' && talkerId != 'L' && talkerId != 'A' && talkerId != 'N')
        return;

    const char* sentenceType = _buffer + 3;

    if (strncmp(sentenceType, "GGA", 3) == 0) {
        parseGga(_buffer);
    } else if (strncmp(sentenceType, "GSA", 3) == 0) {
        parseGsa(_buffer);
    } else if (strncmp(sentenceType, "RMC", 3) == 0) {
        parseRmc(_buffer);
    }
}

bool GpsManager::validateChecksum(const char* sentence) const {
    const char* star = strchr(sentence, '*');
    if (!star || star == sentence)
        return false;

    uint8_t checksum = 0;
    for (const char* p = sentence + 1; p < star; p++) {
        checksum ^= *p;
    }

    char checksumStr[3];
    checksumStr[0] = *(star + 1);
    checksumStr[1] = *(star + 2);
    checksumStr[2] = '\0';

    uint8_t expected = strtol(checksumStr, nullptr, 16);
    return checksum == expected;
}

bool GpsManager::extractField(const char* sentence, uint8_t fieldIndex, char* outBuffer, size_t bufferSize) const {
    if (!outBuffer || bufferSize == 0)
        return false;

    outBuffer[0] = '\0';

    const char* start = sentence;
    uint8_t currentField = 0;

    while (*start && currentField < fieldIndex) {
        if (*start == ',')
            currentField++;
        start++;
    }

    if (currentField != fieldIndex)
        return false;

    size_t i = 0;
    while (*start && *start != ',' && *start != '*' && *start != '\r' && *start != '\n' && i < bufferSize - 1) {
        outBuffer[i++] = *start++;
    }
    outBuffer[i] = '\0';

    return i > 0;
}

float GpsManager::parseFloat(const char* str) const {
    if (!str || !*str)
        return 0.0f;
    return atof(str);
}

int GpsManager::parseInt(const char* str) const {
    if (!str || !*str)
        return 0;
    return atoi(str);
}

float GpsManager::parseCoordinate(const char* coord, char direction) const {
    if (!coord || !*coord || direction == '\0')
        return 0.0f;

    float raw = parseFloat(coord);
    if (raw == 0.0f)
        return 0.0f;

    int degrees = static_cast<int>(raw / 100);
    float minutes = raw - (degrees * 100);
    float decimal = degrees + (minutes / 60.0f);

    if (direction == 'S' || direction == 'W')
        decimal = -decimal;

    return decimal;
}

void GpsManager::parseGga(const char* sentence) {
    char latStr[GpsConfig::fieldBufferSize];
    char latDir[4];
    char lonStr[GpsConfig::fieldBufferSize];
    char lonDir[4];
    char quality[4];
    char sats[4];
    char hdop[10];
    char alt[12];

    extractField(sentence, 2, latStr, sizeof(latStr));
    extractField(sentence, 3, latDir, sizeof(latDir));
    extractField(sentence, 4, lonStr, sizeof(lonStr));
    extractField(sentence, 5, lonDir, sizeof(lonDir));
    extractField(sentence, 6, quality, sizeof(quality));
    extractField(sentence, 7, sats, sizeof(sats));
    extractField(sentence, 8, hdop, sizeof(hdop));
    extractField(sentence, 9, alt, sizeof(alt));

    int fixQuality = parseInt(quality);

    int satCount = parseInt(sats);
    if (satCount > 0 && satCount < 20) {
        _data.satellites = satCount;
    }

    float hdopVal = parseFloat(hdop);
    if (hdopVal > 0.0f && hdopVal < 50.0f) {
        _data.hdop = hdopVal;
    }

    bool hasFix = (fixQuality >= 1);

    if (!hasFix)
        return;

    float lat = parseCoordinate(latStr, latDir[0]);
    float lon = parseCoordinate(lonStr, lonDir[0]);

    if (lat == 0.0f || lon == 0.0f)
        return;

    _data.latitude = lat;
    _data.longitude = lon;
    _data.altitude = parseFloat(alt);
    _data.hasFix = true;
    _data.timestamp = millis();

    if (!_firstFixReceived) {
        Serial.println("[GPS] *** FIRST FIX ACQUIRED (GGA) ***");
        Serial.printf("[GPS] Position: %.6f, %.6f\n", _data.latitude, _data.longitude);
        Serial.printf("[GPS] Satellites: %d, HDOP: %.1f\n", _data.satellites, _data.hdop);
        _firstFixReceived = true;
    }
}

void GpsManager::parseGsa(const char* sentence) {
    char pdop[10];
    char hdop[10];
    char vdop[10];

    extractField(sentence, 15, pdop, sizeof(pdop));
    extractField(sentence, 16, hdop, sizeof(hdop));
    extractField(sentence, 17, vdop, sizeof(vdop));

    if (*pdop)
        _data.pdop = parseFloat(pdop);
    if (*hdop)
        _data.hdop = parseFloat(hdop);
    if (*vdop)
        _data.vdop = parseFloat(vdop);
}

void GpsManager::parseRmc(const char* sentence) {
    if (_debugEnabled) {
        static uint32_t lastPrintTime = 0;
        uint32_t now = millis();

        if ((now - lastPrintTime) > GpsConfig::debugPrintIntervalMs) {
            Serial.printf("[GPS] RMC: %s\n", sentence);
            lastPrintTime = now;
        }
    }

    char status[4];
    extractField(sentence, 2, status, sizeof(status));

    if (status[0] != 'A')
        return;

    char latStr[GpsConfig::fieldBufferSize];
    char latDir[4];
    char lonStr[GpsConfig::fieldBufferSize];
    char lonDir[4];

    extractField(sentence, 3, latStr, sizeof(latStr));
    extractField(sentence, 4, latDir, sizeof(latDir));
    extractField(sentence, 5, lonStr, sizeof(lonStr));
    extractField(sentence, 6, lonDir, sizeof(lonDir));

    if (_debugEnabled) {
        Serial.printf("[GPS] Fields - Lat: '%s' '%s', Lon: '%s' '%s'\n", latStr, latDir, lonStr, lonDir);
    }

    float lat = parseCoordinate(latStr, latDir[0]);
    float lon = parseCoordinate(lonStr, lonDir[0]);

    if (_debugEnabled) {
        Serial.printf("[GPS] Parsed - Lat: %.6f, Lon: %.6f\n", lat, lon);
    }

    if (lat == 0.0f || lon == 0.0f)
        return;

    _data.latitude = lat;
    _data.longitude = lon;
    _data.hasFix = true;
    _data.timestamp = millis();

    if (!_firstFixReceived) {
        Serial.println("[GPS] *** FIRST FIX ACQUIRED (RMC) ***");
        Serial.printf("[GPS] Position: %.6f, %.6f\n", _data.latitude, _data.longitude);
        _firstFixReceived = true;
    }
}

GpsData GpsManager::getData() const {
    return _data;
}

bool GpsManager::isDataFresh() const {
    if (!_data.hasFix)
        return false;
    return (millis() - _data.timestamp) < GpsConfig::staleThresholdMs;
}

bool GpsManager::hasValidFix() const {
    return _data.hasFix && isDataFresh();
}

bool GpsManager::hasSufficientSatellites() const {
    return _data.satellites >= NavigationConfig::minSatellites;
}

bool GpsManager::hasAcceptableDop() const {
    return _data.hdop < NavigationConfig::maxDop;
}