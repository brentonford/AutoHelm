#pragma once

#include <Arduino.h>

namespace BleAuth {
    constexpr size_t secretMaxLen = 64;

    bool isRequired();
    bool validateSecret(const char* provided);
    bool constantTimeEqual(const char* a, const char* b, size_t len);
}