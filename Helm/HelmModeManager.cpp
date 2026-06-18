#include "HelmModeManager.h"

HelmModeManager::HelmModeManager(BleManager& ble,
                                 SpotLockController& spotLock,
                                 WaypointNavController& waypointNav)
    : _ble(ble)
    , _spotLock(spotLock)
    , _waypointNav(waypointNav) {}

void HelmModeManager::requestNavStart(float lat, float lon, uint8_t speed) {
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

    _waypointNav.start(lat, lon, speed);
    _pendingNavStart = false;
    _mode = Mode::Nav;
    _ble.sendResponse("{\"ack\":\"NAV_STARTED\"}");
}

void HelmModeManager::requestNavCancel() {
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

    _spotLock.engage(lat, lon);
    _pendingSpotLockEngage = false;
    _mode = Mode::SpotLock;
    _ble.sendResponse("{\"ack\":\"SPOTLOCK_ENGAGED\"}");
}

void HelmModeManager::requestSpotLockDisengage() {
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

void HelmModeManager::requestSpotLockJog(SpotLockJogDir dir) {
    if (_mode == Mode::SpotLock) {
        _spotLock.jog(dir);
    }
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
}

void HelmModeManager::tryStartPendingNav() {
    if (!_pendingNavStart) return;

    _waypointNav.start(_pendingNavLat, _pendingNavLon, _pendingNavSpeed);
    _pendingNavStart = false;
    _mode = Mode::Nav;
    _ble.sendResponse("{\"ack\":\"NAV_STARTED\"}");
}

void HelmModeManager::tryEngagePendingSpotLock() {
    if (!_pendingSpotLockEngage) return;

    _spotLock.engage(_pendingSlLat, _pendingSlLon);
    _pendingSpotLockEngage = false;
    _mode = Mode::SpotLock;
    _ble.sendResponse("{\"ack\":\"SPOTLOCK_ENGAGED\"}");
}

void HelmModeManager::finishNavHandoff() {
    _spotLock.engage(_handoffLat, _handoffLon);
    _mode = Mode::SpotLock;
    _ble.sendResponse("{\"ack\":\"NAV_ARRIVED\"}");
}

void HelmModeManager::update(const GpsData& gps, float heading) {
    switch (_mode) {
        case Mode::Idle:
            break;

        case Mode::SpotLock:
            _spotLock.update(gps, heading);
            if (!_spotLock.isActive()) {
                _mode = Mode::Idle;
            }
            break;

        case Mode::SpotLockDisengaging:
            _spotLock.update(gps, heading);
            if (!_spotLock.isActive()) {
                if (_pendingNavStart) {
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
                _mode = Mode::Idle;
            }
            break;
        }

        case Mode::NavCancelling:
            _waypointNav.update(gps, heading);
            if (!_waypointNav.isActive()) {
                if (_pendingNavStart) {
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
    return _mode == Mode::Idle;
}

bool HelmModeManager::isAutonomousActive() const {
    return _mode != Mode::Idle;
}

HelmState HelmModeManager::getHelmState() const {
    switch (_mode) {
        case Mode::SpotLockDisengaging:
        case Mode::NavCancelling:
        case Mode::NavHandoff:
            return HelmState::Disengaging;

        case Mode::SpotLock:
            if (_spotLock.isZeroing()) return HelmState::Disengaging;
            return HelmState::SpotLockActive;

        case Mode::Nav:
            if (_waypointNav.isZeroing()) return HelmState::Disengaging;
            if (_waypointNav.getState().arriving) return HelmState::NavArriving;
            return HelmState::NavApproaching;

        case Mode::Idle:
        default:
            return HelmState::Idle;
    }
}