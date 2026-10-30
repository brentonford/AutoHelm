#include "HelmModeManager.h"

HelmModeManager::HelmModeManager(GpsManager& gps, BleManager& ble,
                                 SpotLockController& spotLock,
                                 WaypointNavController& waypointNav)
    : _gps(gps)
    , _ble(ble)
    , _spotLock(spotLock)
    , _waypointNav(waypointNav) {}

bool HelmModeManager::validateNavPreconditions(float targetLat, float targetLon,
                                               const char*& errorCode) const {
    if (!_compassReady) {
        errorCode = "COMPASS_UNAVAILABLE";
        return false;
    }
    if (!GpsValidation::isValidCoordinate(targetLat, targetLon)) {
        errorCode = GpsValidation::errorCodeFor(GpsReadiness::InvalidCoordinates);
        return false;
    }

    const SpotLockSettings& settings = _waypointNav.getSettings();
    GpsReadiness readiness = _gps.checkAutonomyReadiness(settings.minSatellites, settings.maxHDOP);
    if (readiness != GpsReadiness::Ready) {
        errorCode = GpsValidation::errorCodeFor(readiness);
        return false;
    }

    errorCode = nullptr;
    return true;
}

bool HelmModeManager::validateSpotLockPreconditions(float lockLat, float lockLon,
                                                    const char*& errorCode) const {
    if (!_compassReady) {
        errorCode = "COMPASS_UNAVAILABLE";
        return false;
    }
    if (!GpsValidation::isValidCoordinate(lockLat, lockLon)) {
        errorCode = GpsValidation::errorCodeFor(GpsReadiness::InvalidCoordinates);
        return false;
    }

    const SpotLockSettings& settings = _spotLock.getSettings();
    GpsReadiness readiness = _gps.checkAutonomyReadiness(settings.minSatellites, settings.maxHDOP);
    if (readiness != GpsReadiness::Ready) {
        errorCode = GpsValidation::errorCodeFor(readiness);
        return false;
    }

    errorCode = nullptr;
    return true;
}

void HelmModeManager::sendAutonomyError(const char* errorCode) {
    char response[64];
    snprintf(response, sizeof(response), "{\"error\":\"%s\"}", errorCode);
    _ble.sendResponse(response);
}

void HelmModeManager::clearFault() {
    if (_mode == Mode::Fault) {
        _mode = Mode::Idle;
    }
    _spotLock.clearGpsAborted();
    _waypointNav.clearGpsAborted();
}

void HelmModeManager::enterFault(const char* reason) {
    _pendingNavStart = false;
    _pendingSpotLockEngage = false;
    _mode = Mode::Fault;

    char response[80];
    snprintf(response, sizeof(response),
             "{\"error\":\"%s\",\"helm_state\":%u}", reason, (unsigned)HelmState::Fault);
    _ble.sendResponse(response);

    _spotLock.clearGpsAborted();
    _waypointNav.clearGpsAborted();
    Serial.printf("[HelmMode] FAULT – %s\n", reason);
}

void HelmModeManager::handleControllerStopped(bool gpsAborted) {
    if (gpsAborted) {
        enterFault("GPS_LOST");
        return;
    }
    _mode = Mode::Idle;
}

void HelmModeManager::requestNavStart(float lat, float lon, uint8_t speed) {
    clearFault();

    const char* errorCode = nullptr;
    if (!validateNavPreconditions(lat, lon, errorCode)) {
        _pendingNavStart = false;
        sendAutonomyError(errorCode);
        return;
    }

    _pendingNavLat    = lat;
    _pendingNavLon    = lon;
    _pendingNavSpeed  = speed;
    _pendingNavStart  = true;
    _pendingSpotLockEngage = false;

    if (_spotLock.isActive()) {
        Serial.println("[HelmMode] NAV_START – disengaging Spot Lock first");
        _spotLock.disengage();
        _mode = Mode::SpotLockDisengaging;
        return;
    }

    if (_waypointNav.isActive()) {
        Serial.println("[HelmMode] NAV_START – restarting navigation");
        _waypointNav.cancel();
        _mode = Mode::NavCancelling;
        return;
    }

    _spotLock.takeKnownZero();
    _waypointNav.takeKnownZero();
    _waypointNav.start(lat, lon, speed, false);
    _pendingNavStart = false;
    _mode = Mode::Nav;
    _ble.sendResponse("{\"ack\":\"NAV_STARTED\"}");
}

void HelmModeManager::requestNavCancel() {
    clearFault();
    _pendingNavStart = false;
    _pendingSpotLockEngage = false;

    if (!_waypointNav.isActive()) {
        _mode = Mode::Idle;
        _ble.sendResponse("{\"ack\":\"NAV_CANCELLED\"}");
        return;
    }

    _waypointNav.cancel();
    _mode = Mode::NavCancelling;
    _ble.sendResponse("{\"ack\":\"NAV_CANCELLED\"}");
}

void HelmModeManager::requestSpotLockEngage(float lat, float lon) {
    clearFault();

    const char* errorCode = nullptr;
    if (!validateSpotLockPreconditions(lat, lon, errorCode)) {
        _pendingSpotLockEngage = false;
        sendAutonomyError(errorCode);
        return;
    }

    _pendingSlLat = lat;
    _pendingSlLon = lon;
    _pendingSpotLockEngage = true;
    _pendingNavStart = false;

    if (_waypointNav.isActive()) {
        Serial.println("[HelmMode] SPOTLOCK_ENGAGE – cancelling navigation first");
        _waypointNav.cancel();
        _mode = Mode::NavCancelling;
        return;
    }

    if (_spotLock.isActive()) {
        Serial.println("[HelmMode] SPOTLOCK_ENGAGE – re-locking at new position");
        _spotLock.disengage();
        _mode = Mode::SpotLockDisengaging;
        return;
    }

    _spotLock.takeKnownZero();
    _waypointNav.takeKnownZero();
    _spotLock.engage(lat, lon, false);
    _pendingSpotLockEngage = false;
    _mode = Mode::SpotLock;
    _ble.sendResponse("{\"ack\":\"SPOTLOCK_ENGAGED\"}");
}

void HelmModeManager::requestSpotLockDisengage() {
    clearFault();
    _pendingSpotLockEngage = false;

    if (!_spotLock.isActive()) {
        _mode = Mode::Idle;
        _ble.sendResponse("{\"ack\":\"SPOTLOCK_DISENGAGED\"}");
        return;
    }

    _spotLock.disengage();
    _mode = Mode::SpotLockDisengaging;
    _ble.sendResponse("{\"ack\":\"SPOTLOCK_DISENGAGED\"}");
}

bool HelmModeManager::requestSpotLockJog(SpotLockJogDir dir) {
    if (_mode != Mode::SpotLock) {
        return false;
    }
    return _spotLock.jog(dir);
}

void HelmModeManager::applyNavSettings(const SpotLockSettings& settings) {
    _waypointNav.applySettings(settings);
}

void HelmModeManager::applySpotLockSettings(const SpotLockSettings& settings) {
    _spotLock.applySettings(settings);
}

void HelmModeManager::beginNavHandoff(float lat, float lon) {
    Serial.printf("[HelmMode] NAV arrived – handoff to Spot Lock at %.6f,%.6f\n", lat, lon);
    _handoffLat = lat;
    _handoffLon = lon;
    _pendingNavStart = false;
    _pendingSpotLockEngage = false;
    _waypointNav.cancel();
    _mode = Mode::NavHandoff;
    if (!_waypointNav.isActive()) {
        finishNavHandoff();
    }
}

void HelmModeManager::tryStartPendingNav() {
    if (!_pendingNavStart) return;

    const char* errorCode = nullptr;
    if (!validateNavPreconditions(_pendingNavLat, _pendingNavLon, errorCode)) {
        _pendingNavStart = false;
        _mode = Mode::Idle;
        sendAutonomyError(errorCode);
        return;
    }

    bool knownZero = _spotLock.takeKnownZero() || _waypointNav.takeKnownZero();
    _waypointNav.start(_pendingNavLat, _pendingNavLon, _pendingNavSpeed, knownZero);
    _pendingNavStart = false;
    _mode = Mode::Nav;
    _ble.sendResponse("{\"ack\":\"NAV_STARTED\"}");
}

void HelmModeManager::tryEngagePendingSpotLock() {
    if (!_pendingSpotLockEngage) return;

    const char* errorCode = nullptr;
    if (!validateSpotLockPreconditions(_pendingSlLat, _pendingSlLon, errorCode)) {
        _pendingSpotLockEngage = false;
        _mode = Mode::Idle;
        sendAutonomyError(errorCode);
        return;
    }

    bool knownZero = _spotLock.takeKnownZero() || _waypointNav.takeKnownZero();
    _spotLock.engage(_pendingSlLat, _pendingSlLon, knownZero);
    _pendingSpotLockEngage = false;
    _mode = Mode::SpotLock;
    _ble.sendResponse("{\"ack\":\"SPOTLOCK_ENGAGED\"}");
}

void HelmModeManager::finishNavHandoff() {
    const char* errorCode = nullptr;
    if (!validateSpotLockPreconditions(_handoffLat, _handoffLon, errorCode)) {
        _mode = Mode::Idle;
        sendAutonomyError(errorCode);
        return;
    }

    _spotLock.engage(_handoffLat, _handoffLon, _waypointNav.takeKnownZero());
    _mode = Mode::SpotLock;
    _ble.sendResponse("{\"ack\":\"NAV_ARRIVED\"}");
}

void HelmModeManager::update(const GpsData& gps, float heading) {
    (void)gps;

    switch (_mode) {
        case Mode::Idle:
        case Mode::Fault:
            break;

        case Mode::SpotLock:
            _spotLock.update(gps, heading);
            if (!_spotLock.isActive()) {
                handleControllerStopped(_spotLock.wasGpsAborted());
            }
            break;

        case Mode::SpotLockDisengaging:
            _spotLock.update(gps, heading);
            if (!_spotLock.isActive()) {
                if (_spotLock.wasGpsAborted()) {
                    handleControllerStopped(true);
                } else if (_pendingNavStart) {
                    tryStartPendingNav();
                } else if (_pendingSpotLockEngage) {
                    tryEngagePendingSpotLock();
                } else {
                    _mode = Mode::Idle;
                }
            }
            break;

        case Mode::Nav: {
            bool arrived = _waypointNav.update(gps, heading);
            if (arrived) {
                beginNavHandoff(_waypointNav.getState().targetLat,
                                _waypointNav.getState().targetLon);
            } else if (!_waypointNav.isActive()) {
                handleControllerStopped(_waypointNav.wasGpsAborted());
            }
            break;
        }

        case Mode::NavCancelling:
            _waypointNav.update(gps, heading);
            if (!_waypointNav.isActive()) {
                if (_waypointNav.wasGpsAborted()) {
                    handleControllerStopped(true);
                } else if (_pendingNavStart) {
                    tryStartPendingNav();
                } else if (_pendingSpotLockEngage) {
                    tryEngagePendingSpotLock();
                } else {
                    _mode = Mode::Idle;
                }
            }
            break;

        case Mode::NavHandoff:
            _waypointNav.update(gps, heading);
            if (!_waypointNav.isActive()) {
                finishNavHandoff();
            }
            break;
    }
}

bool HelmModeManager::allowsManualRf() const {
    return _mode == Mode::Idle || _mode == Mode::Fault;
}

bool HelmModeManager::isAutonomousActive() const {
    return _mode != Mode::Idle && _mode != Mode::Fault;
}

HelmState HelmModeManager::getHelmState() const {
    if (_mode == Mode::Fault) {
        return HelmState::Fault;
    }

    switch (_mode) {
        case Mode::SpotLockDisengaging:
        case Mode::NavCancelling:
        case Mode::NavHandoff:
            return HelmState::Disengaging;

        case Mode::SpotLock:
            if (_spotLock.isZeroing() || _spotLock.isDisengaging()) return HelmState::Disengaging;
            return HelmState::SpotLockActive;

        case Mode::Nav:
            if (_waypointNav.isZeroing() || _waypointNav.isCancelling()) return HelmState::Disengaging;
            return HelmState::NavApproaching;

        case Mode::Idle:
        default:
            return HelmState::Idle;
    }
}