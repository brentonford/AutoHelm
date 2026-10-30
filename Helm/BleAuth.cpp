#include "BleAuth.h"

#include "secrets.h"

namespace {

bool isPlaceholderSecret(const char* secret) {
    if (!secret || secret[0] == '\0') {
        return true;
    }

    if (strcmp(secret, "CHANGE_ME") == 0) {
        return true;
    }

    bool allZero = true;
    for (const char* p = secret; *p; ++p) {
        if (*p != '0') {
            allZero = false;
            break;
        }
    }
    return allZero;
}

const char* configuredSecret() {
#ifdef BLE_AUTH_SECRET
    return BLE_AUTH_SECRET;
#else
    return "";
#endif
}

}  // namespace

namespace BleAuth {

bool isRequired() {
    const char* secret = configuredSecret();
    return !isPlaceholderSecret(secret);
}

bool constantTimeEqual(const char* a, const char* b, size_t len) {
    if (!a || !b) {
        return false;
    }

    uint8_t diff = 0;
    for (size_t i = 0; i < len; ++i) {
        diff |= static_cast<uint8_t>(a[i] ^ b[i]);
    }
    return diff == 0;
}

bool validateSecret(const char* provided) {
    if (!isRequired()) {
        return true;
    }

    if (!provided || provided[0] == '\0') {
        return false;
    }

    const char* expected = configuredSecret();
    size_t expectedLen = strnlen(expected, secretMaxLen);
    size_t providedLen = strnlen(provided, secretMaxLen + 1);

    if (providedLen == 0 || providedLen > secretMaxLen) {
        return false;
    }

    if (providedLen != expectedLen) {
        return false;
    }

    return constantTimeEqual(provided, expected, expectedLen);
}

}  // namespace