import Foundation

struct NavSettings: Codable, Equatable {

    // MARK: - Arrival

    /// Radius within which the boat is considered to have arrived at the waypoint.
    /// Navigation stops and Spot Lock engages when distance falls below this value.
    /// Larger than SpotLock's dead zone — it's acceptable to stop a few metres from
    /// a waypoint rather than trying to hold the exact GPS coordinate.
    var arrivalRadius: Double = 5.0

    // MARK: - Speed Control

    /// Floor speed level used during the ramp-down zone (final 8 m before arrival).
    /// Lower than SpotLock's minimum — the boat can crawl in gently.
    var minSpeed: Int = 2

    /// Pause between each motor speed level step during ramp-up or ramp-down.
    var speedChangeDelay: Double = 2.0

    // MARK: - Steering Control

    /// Angular dead band during transit — wider than SpotLock's 10° because precise
    /// heading maintenance is less critical when moving toward a target than when holding position.
    var headingTolerance: Double = 15.0

    /// Minimum time between steering correction cycles.
    var correctionInterval: Double = 1.0

    var smallAngleThreshold: Double = 30.0
    var largeAngleThreshold: Double = 90.0
    var smallSteeringDuration: Int = 200
    var mediumSteeringDuration: Int = 600
    var largeSteeringDuration: Int = 1000

    // MARK: - Cable Management

    var maxRotationBeforeUntangle: Double = 720.0
    var rotationPerMs: Double = 0.1

    // MARK: - GPS Quality

    var minSatellites: Int = 4
    var maxHDOP: Double = 5.0
    var maxConsecutiveGpsFailures: Int = 5

    // MARK: - Position Filtering

    var filterWindowSize: Int = 5

    // MARK: - Defaults

    static let defaults = NavSettings()

    var isAllDefault: Bool { self == NavSettings.defaults }

    /// Encodes settings as a `NAV_SETTINGS:` CSV command for the Helm device.
    ///
    /// Reuses the 20-field SPOTLOCK_SETTINGS wire format so the device can parse it
    /// with the same SpotLockSettings struct. The four fields unused by navigation
    /// (activationThreshold, jogDistance, maxSpeed, proportionalGain) are sent as
    /// fixed passthrough values — the device algorithm ignores them during navigation.
    func toNavSettingsCommand() -> String {
        "NAV_SETTINGS:\(arrivalRadius),10.0,1.5" +           // arrivalRadius, activation↑, jog↑
        ",\(minSpeed),10,1.0" +                               // minSpeed, maxSpeed↑, gain↑
        ",\(speedChangeDelay),\(headingTolerance),\(correctionInterval)" +
        ",\(smallAngleThreshold),\(largeAngleThreshold)" +
        ",\(smallSteeringDuration),\(mediumSteeringDuration),\(largeSteeringDuration)" +
        ",\(maxRotationBeforeUntangle),\(rotationPerMs)" +
        ",\(minSatellites),\(maxHDOP),\(maxConsecutiveGpsFailures),\(filterWindowSize)"
        // ↑ passthrough — not used by WaypointNavController
    }

    // MARK: - Validation

    mutating func validate() {
        arrivalRadius             = max(1.0,   min(20.0,   arrivalRadius))
        minSpeed                  = max(1,     min(9,      minSpeed))
        speedChangeDelay          = max(0.5,   min(10.0,   speedChangeDelay))
        headingTolerance          = max(2.0,   min(45.0,   headingTolerance))
        correctionInterval        = max(0.5,   min(5.0,    correctionInterval))
        smallAngleThreshold       = max(5.0,   min(89.0,   smallAngleThreshold))
        largeAngleThreshold       = max(6.0,   min(180.0,  largeAngleThreshold))
        smallSteeringDuration     = max(50,    min(2000,   smallSteeringDuration))
        mediumSteeringDuration    = max(100,   min(3000,   mediumSteeringDuration))
        largeSteeringDuration     = max(200,   min(5000,   largeSteeringDuration))
        maxRotationBeforeUntangle = max(180.0, min(2160.0, maxRotationBeforeUntangle))
        rotationPerMs             = max(0.01,  min(1.0,    rotationPerMs))
        minSatellites             = max(1,     min(12,     minSatellites))
        maxHDOP                   = max(1.0,   min(20.0,   maxHDOP))
        maxConsecutiveGpsFailures = max(1,     min(30,     maxConsecutiveGpsFailures))
        filterWindowSize          = max(1,     min(20,     filterWindowSize))

        if smallAngleThreshold >= largeAngleThreshold {
            largeAngleThreshold = min(180.0, smallAngleThreshold + 1.0)
        }
        if smallSteeringDuration >= mediumSteeringDuration {
            mediumSteeringDuration = min(3000, smallSteeringDuration + 50)
        }
        if mediumSteeringDuration >= largeSteeringDuration {
            largeSteeringDuration = min(5000, mediumSteeringDuration + 50)
        }
    }
}
