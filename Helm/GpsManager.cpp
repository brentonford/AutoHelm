#include "GpsManager.h"

GpsManager::GpsManager(uint8_t rxPin, uint8_t txPin)
    : _rxPin(rxPin)
    , _txPin(txPin)
    , _serial(2)
    , _bufferIndex(0)
    , _initialized(false)
    , _lastReceiveTime(0)
    , _firstFixReceived(false) {
}

bool GpsManager::begin() {
    _serial.begin(Config::gpsBaud, SERIAL_8N1, _rxPin, _txPin);
    _initialized = true;
    _lastReceiveTime = millis();
    Serial.println("[GPS] Initialized on UART2");
    Serial.println("[GPS] Waiting for GPS data...");
    return true;
}

void GpsManager::update() {
    if (!_initialized)
        return;

    uint32_t now = millis();
    
    static uint32_t lastDebugTime = 0;
    static uint16_t charCount = 0;
    
    while (_serial.available()) {
        char c = _serial.read();
        charCount++;
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
    
    if ((now - lastDebugTime) > 5000) {
        if (charCount > 0) {
            Serial.printf("[GPS] Received %d characters in last 5 seconds\n", charCount);
        } else {
            Serial.println("[GPS] WARNING: No data received from GPS module!");
        }
        charCount = 0;
        lastDebugTime = now;
    }
}

void GpsManager::processBuffer() {
    if (_buffer[0] != '$')
        return;

    if (_bufferIndex < 15) {
        return;
    }

    if (!validateChecksum(_buffer)) {
        return;
    }

    if (_buffer[1] != 'G' || (_buffer[2] != 'P' && _buffer[2] != 'L' && _buffer[2] != 'A' && _buffer[2] != 'N')) {
        return;
    }

    if (strncmp(_buffer + 3, "GGA", 3) == 0) {
        parseGga(_buffer);
    } else if (strncmp(_buffer + 3, "GSA", 3) == 0) {
        parseGsa(_buffer);
    } else if (strncmp(_buffer + 3, "RMC", 3) == 0) {
        parseRmc(_buffer);
    }
}

bool GpsManager::validateChecksum(const char* sentence) {
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

const char* GpsManager::getField(const char* sentence, uint8_t fieldIndex) {
    static char field[20];
    field[0] = '\0';

    const char* start = sentence;
    uint8_t currentField = 0;

    while (*start && currentField < fieldIndex) {
        if (*start == ',')
            currentField++;
        start++;
    }

    if (currentField != fieldIndex)
        return field;

    uint8_t i = 0;
    while (*start && *start != ',' && *start != '*' && *start != '\r' && *start != '\n' && i < sizeof(field) - 1) {
        field[i++] = *start++;
    }
    field[i] = '\0';

    return field;
}

float GpsManager::parseFloat(const char* str) {
    if (!str || !*str)
        return 0.0f;
    return atof(str);
}

int GpsManager::parseInt(const char* str) {
    if (!str || !*str)
        return 0;
    return atoi(str);
}

float GpsManager::parseCoordinate(const char* coord, const char* direction) {
    if (!coord || !*coord || !direction || !*direction)
        return 0.0f;

    float raw = parseFloat(coord);
    if (raw == 0.0f)
        return 0.0f;
    
    int degrees;
    float minutes;
    
    if (raw < 10000.0f) {
        degrees = (int)(raw / 100);
        minutes = raw - (degrees * 100);
    } else {
        degrees = (int)(raw / 100);
        minutes = raw - (degrees * 100);
    }
    
    float decimal = degrees + (minutes / 60.0f);

    if (*direction == 'S' || *direction == 'W')
        decimal = -decimal;

    return decimal;
}

void GpsManager::parseGga(const char* sentence) {
    // Extract fields into local buffers
    char latStr[15], latDir[2], lonStr[15], lonDir[2];
    char quality[3], sats[3], hdop[8], alt[12];
    
    strncpy(latStr, getField(sentence, 2), sizeof(latStr) - 1);
    latStr[sizeof(latStr) - 1] = '\0';
    
    strncpy(latDir, getField(sentence, 3), sizeof(latDir) - 1);
    latDir[sizeof(latDir) - 1] = '\0';
    
    strncpy(lonStr, getField(sentence, 4), sizeof(lonStr) - 1);
    lonStr[sizeof(lonStr) - 1] = '\0';
    
    strncpy(lonDir, getField(sentence, 5), sizeof(lonDir) - 1);
    lonDir[sizeof(lonDir) - 1] = '\0';
    
    strncpy(quality, getField(sentence, 6), sizeof(quality) - 1);
    quality[sizeof(quality) - 1] = '\0';
    
    strncpy(sats, getField(sentence, 7), sizeof(sats) - 1);
    sats[sizeof(sats) - 1] = '\0';
    
    strncpy(hdop, getField(sentence, 8), sizeof(hdop) - 1);
    hdop[sizeof(hdop) - 1] = '\0';
    
    strncpy(alt, getField(sentence, 9), sizeof(alt) - 1);
    alt[sizeof(alt) - 1] = '\0';

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
    
    if (hasFix) {
        float lat = parseCoordinate(latStr, latDir);
        float lon = parseCoordinate(lonStr, lonDir);
        
        if (lat != 0.0f && lon != 0.0f) {
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
    }
}

void GpsManager::parseGsa(const char* sentence) {
    char pdop[8], hdop[8], vdop[8];
    
    strncpy(pdop, getField(sentence, 15), sizeof(pdop) - 1);
    pdop[sizeof(pdop) - 1] = '\0';
    
    strncpy(hdop, getField(sentence, 16), sizeof(hdop) - 1);
    hdop[sizeof(hdop) - 1] = '\0';
    
    strncpy(vdop, getField(sentence, 17), sizeof(vdop) - 1);
    vdop[sizeof(vdop) - 1] = '\0';

    if (*pdop)
        _data.pdop = parseFloat(pdop);
    if (*hdop)
        _data.hdop = parseFloat(hdop);
    if (*vdop)
        _data.vdop = parseFloat(vdop);
}

void GpsManager::parseRmc(const char* sentence) {
    static uint32_t lastPrintTime = 0;
    if ((millis() - lastPrintTime) > 5000) {
        Serial.printf("[GPS] RMC: %s\n", sentence);
        lastPrintTime = millis();
    }

    const char* status = getField(sentence, 2);

    if (*status == 'A') {
        // Extract fields into local buffers to avoid static buffer reuse issue
        char latStr[15];
        char latDir[2];
        char lonStr[15];
        char lonDir[2];
        
        strncpy(latStr, getField(sentence, 3), sizeof(latStr) - 1);
        latStr[sizeof(latStr) - 1] = '\0';
        
        strncpy(latDir, getField(sentence, 4), sizeof(latDir) - 1);
        latDir[sizeof(latDir) - 1] = '\0';
        
        strncpy(lonStr, getField(sentence, 5), sizeof(lonStr) - 1);
        lonStr[sizeof(lonStr) - 1] = '\0';
        
        strncpy(lonDir, getField(sentence, 6), sizeof(lonDir) - 1);
        lonDir[sizeof(lonDir) - 1] = '\0';
        
        Serial.printf("[GPS] Fields - Lat: '%s' '%s', Lon: '%s' '%s'\n", latStr, latDir, lonStr, lonDir);

        float lat = parseCoordinate(latStr, latDir);
        float lon = parseCoordinate(lonStr, lonDir);
        
        Serial.printf("[GPS] Parsed - Lat: %.6f, Lon: %.6f\n", lat, lon);
        
        if (lat != 0.0f && lon != 0.0f) {
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