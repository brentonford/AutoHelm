import Foundation

struct SpotLockSettings: Codable, Equatable {

    // MARK: - Position Control
    var deadZoneRadius: Double = 2.0
    var activationThreshold: Double = 4.0
    var jogDistance: Double = 1.5

    // MARK: - Speed Control
    var minSpeed: Int = 3
    var maxSpeed: Int = 10
    var proportionalGain: Double = 1.0
    var speedChangeDelay: Double = 2.0

    // MARK: - Steering Control
    var headingTolerance: Double = 10.0
    var correctionInterval: Double = 1.0
    var smallAngleThreshold: Double = 30.0
    var largeAngleThreshold: Double = 90.0
    var smallSteeringDuration: Int = 200
    var mediumSteeringDuration: Int = 600
    var largeSteeringDuration: Int = 1000

    // MARK: - Cable Tangle Prevention
    var maxRotationBeforeUntangle: Double = 720.0
    var rotationPerMs: Double = 0.1

    // MARK: - GPS Quality
    var minSatellites: Int = 4
    var maxHDOP: Double = 5.0
    var maxConsecutiveGpsFailures: Int = 5

    // MARK: - Connectivity
    var disconnectGracePeriodSeconds: Double = 5.0

    // MARK: - Position Filtering
    var filterWindowSize: Int = 5

    // MARK: - Defaults

    static let defaults = SpotLockSettings()

    var isAllDefault: Bool { self == SpotLockSettings.defaults }

    /// Encodes settings as a CSV command string for the Helm device.
    /// Field order matches the device-side SPOTLOCK_SETTINGS parser exactly.
    func toSettingsCommand() -> String {
        "SPOTLOCK_SETTINGS:\(deadZoneRadius),\(activationThreshold),\(jogDistance)" +
        ",\(minSpeed),\(maxSpeed),\(proportionalGain)" +
        ",\(speedChangeDelay),\(headingTolerance),\(correctionInterval)" +
        ",\(smallAngleThreshold),\(largeAngleThreshold)" +
        ",\(smallSteeringDuration),\(mediumSteeringDuration),\(largeSteeringDuration)" +
        ",\(maxRotationBeforeUntangle),\(rotationPerMs)" +
        ",\(minSatellites),\(maxHDOP),\(maxConsecutiveGpsFailures),\(filterWindowSize)"
    }

    // MARK: - Validation

    /// Clamps all fields to valid ranges and auto-corrects interdependent values.
    mutating func validate() {
        // Clamp individual fields to valid ranges first
        deadZoneRadius               = max(0.5,   min(10.0,  deadZoneRadius))
        activationThreshold          = max(1.0,   min(20.0,  activationThreshold))
        jogDistance                  = max(0.5,   min(10.0,  jogDistance))
        minSpeed                     = max(1,     min(9,     minSpeed))
        maxSpeed                     = max(2,     min(10,    maxSpeed))
        proportionalGain             = max(0.1,   min(5.0,   proportionalGain))
        speedChangeDelay             = max(0.5,   min(10.0,  speedChangeDelay))
        headingTolerance             = max(2.0,   min(45.0,  headingTolerance))
        correctionInterval           = max(0.5,   min(5.0,   correctionInterval))
        smallAngleThreshold          = max(5.0,   min(89.0,  smallAngleThreshold))
        largeAngleThreshold          = max(6.0,   min(180.0, largeAngleThreshold))
        smallSteeringDuration        = max(50,    min(2000,  smallSteeringDuration))
        mediumSteeringDuration       = max(100,   min(3000,  mediumSteeringDuration))
        largeSteeringDuration        = max(200,   min(5000,  largeSteeringDuration))
        maxRotationBeforeUntangle    = max(180.0, min(2160.0, maxRotationBeforeUntangle))
        rotationPerMs                = max(0.01,  min(1.0,   rotationPerMs))
        minSatellites                = max(1,     min(12,    minSatellites))
        maxHDOP                      = max(1.0,   min(20.0,  maxHDOP))
        maxConsecutiveGpsFailures    = max(1,     min(30,    maxConsecutiveGpsFailures))
        disconnectGracePeriodSeconds = max(1.0,   min(30.0,  disconnectGracePeriodSeconds))
        filterWindowSize             = max(1,     min(20,    filterWindowSize))

        // Dead zone must be at least 0.5m less than activation threshold.
        // If the user raised dead zone into or above activation threshold, push activation up.
        if deadZoneRadius >= activationThreshold - 0.5 {
            activationThreshold = min(20.0, deadZoneRadius + 0.5)
        }

        // Min speed must be strictly less than max speed.
        if minSpeed >= maxSpeed {
            minSpeed = max(1, maxSpeed - 1)
        }

        // Angle thresholds must be in ascending order with at least 1° gap.
        if smallAngleThreshold >= largeAngleThreshold {
            largeAngleThreshold = min(180.0, smallAngleThreshold + 1.0)
        }

        // Steering pulse durations must be in ascending order with at least 50ms gap.
        if smallSteeringDuration >= mediumSteeringDuration {
            mediumSteeringDuration = min(3000, smallSteeringDuration + 50)
        }
        if mediumSteeringDuration >= largeSteeringDuration {
            largeSteeringDuration = min(5000, mediumSteeringDuration + 50)
        }
    }
}
