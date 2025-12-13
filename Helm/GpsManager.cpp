#include "GpsManager.h"

GpsManager::GpsManager(uint8_t rxPin, uint8_t txPin)
    : _rxPin(rxPin)
    , _txPin(txPin)
    , _serial(2)
    , _bufferIndex(0)
    , _initialized(false) {
}

bool GpsManager::begin() {
    _serial.begin(Config::gpsBaud, SERIAL_8N1, _rxPin, _txPin);
    _initialized = true;
    Serial.println("[GPS] Initialized on UART2");
    return true;
}

void GpsManager::update() {
    if (!_initialized)
        return;

    while (_serial.available()) {
        char c = _serial.read();

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
}

void GpsManager::processBuffer() {
    if (_buffer[0] != '$')
        return;

    if (!validateChecksum(_buffer))
        return;

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
    if (!star)
        return false;

    uint8_t checksum = 0;
    for (const char* p = sentence + 1; p < star; p++) {
        checksum ^= *p;
    }

    uint8_t expected = strtol(star + 1, nullptr, 16);
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
    while (*start && *start != ',' && *start != '*' && i < sizeof(field) - 1) {
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
    int degrees = (int)(raw / 100);
    float minutes = raw - (degrees * 100);
    float decimal = degrees + (minutes / 60.0f);

    if (*direction == 'S' || *direction == 'W')
        decimal = -decimal;

    return decimal;
}

void GpsManager::parseGga(const char* sentence) {
    // $GPGGA,time,lat,N/S,lon,E/W,quality,sats,hdop,alt,M,geoid,M,age,station*cs

    const char* latStr = getField(sentence, 2);
    const char* latDir = getField(sentence, 3);
    const char* lonStr = getField(sentence, 4);
    const char* lonDir = getField(sentence, 5);
    const char* quality = getField(sentence, 6);
    const char* sats = getField(sentence, 7);
    const char* hdop = getField(sentence, 8);
    const char* alt = getField(sentence, 9);

    int fixQuality = parseInt(quality);
    _data.hasFix = (fixQuality >= 1);
    _data.satellites = parseInt(sats);

    if (_data.hasFix) {
        _data.latitude = parseCoordinate(latStr, latDir);
        _data.longitude = parseCoordinate(lonStr, lonDir);
        _data.altitude = parseFloat(alt);
        _data.hdop = parseFloat(hdop);
        _data.timestamp = millis();
    }
}

void GpsManager::parseGsa(const char* sentence) {
    // $GPGSA,mode,fix,prn1,...,prn12,pdop,hdop,vdop*cs

    const char* pdop = getField(sentence, 15);
    const char* hdop = getField(sentence, 16);
    const char* vdop = getField(sentence, 17);

    if (*pdop)
        _data.pdop = parseFloat(pdop);
    if (*hdop)
        _data.hdop = parseFloat(hdop);
    if (*vdop)
        _data.vdop = parseFloat(vdop);
}

void GpsManager::parseRmc(const char* sentence) {
    // $GPRMC,time,status,lat,N/S,lon,E/W,speed,course,date,mag,dir,mode*cs

    const char* status = getField(sentence, 2);

    if (*status == 'A') {
        const char* latStr = getField(sentence, 3);
        const char* latDir = getField(sentence, 4);
        const char* lonStr = getField(sentence, 5);
        const char* lonDir = getField(sentence, 6);

        _data.latitude = parseCoordinate(latStr, latDir);
        _data.longitude = parseCoordinate(lonStr, lonDir);
        _data.hasFix = true;
        _data.timestamp = millis();
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