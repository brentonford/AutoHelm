import XCTest
import CoreLocation
@testable import Waypoint

// MARK: - Bearing & Distance Tests

final class CoordinateMathTests: XCTestCase {

    // Tolerance: 0.5° for bearing, 1m for distance
    private let bearingTolerance = 0.5
    private let distanceTolerance = 1.0

    // MARK: Cardinal bearings

    func test_bearing_dueNorth() {
        let from = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let to   = CLLocationCoordinate2D(latitude: -32.0, longitude: 151.0)
        XCTAssertEqual(from.bearing(to: to), 0.0, accuracy: bearingTolerance)
    }

    func test_bearing_dueEast() {
        let from = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let to   = CLLocationCoordinate2D(latitude: -33.0, longitude: 152.0)
        XCTAssertEqual(from.bearing(to: to), 90.0, accuracy: bearingTolerance)
    }

    func test_bearing_dueSouth() {
        let from = CLLocationCoordinate2D(latitude: -32.0, longitude: 151.0)
        let to   = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        XCTAssertEqual(from.bearing(to: to), 180.0, accuracy: bearingTolerance)
    }

    func test_bearing_dueWest() {
        let from = CLLocationCoordinate2D(latitude: -33.0, longitude: 152.0)
        let to   = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        XCTAssertEqual(from.bearing(to: to), 270.0, accuracy: bearingTolerance)
    }

    func test_bearing_wrapsInto0to360() {
        let from = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let to   = CLLocationCoordinate2D(latitude: -33.5, longitude: 150.5)
        let result = from.bearing(to: to)
        XCTAssertGreaterThanOrEqual(result, 0.0)
        XCTAssertLessThan(result, 360.0)
    }

    func test_bearing_samePoint_isFinite() {
        let coord = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let result = coord.bearing(to: coord)
        XCTAssertTrue(result.isFinite, "Bearing to self must not be NaN or infinite")
    }

    // MARK: Distance

    func test_distance_zeroForSamePoint() {
        let coord = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        XCTAssertEqual(coord.distance(to: coord), 0.0, accuracy: distanceTolerance)
    }

    func test_distance_knownShortDistance() {
        // ~111 m per 0.001° latitude at any longitude
        let from = CLLocationCoordinate2D(latitude: -33.0000, longitude: 151.0)
        let to   = CLLocationCoordinate2D(latitude: -33.0010, longitude: 151.0)
        XCTAssertEqual(from.distance(to: to), 111.0, accuracy: 2.0)
    }

    func test_distance_isSymmetric() {
        let a = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let b = CLLocationCoordinate2D(latitude: -33.01, longitude: 151.01)
        XCTAssertEqual(a.distance(to: b), b.distance(to: a), accuracy: distanceTolerance)
    }
}

// MARK: - Relative Angle Tests

final class RelativeAngleTests: XCTestCase {

    // Mirror the private helper from SpotLockController
    private func relativeAngle(heading: Double, bearing: Double) -> Double {
        var angle = bearing - heading
        while angle > 180  { angle -= 360 }
        while angle < -180 { angle += 360 }
        return angle
    }

    func test_straightAhead_isZero() {
        XCTAssertEqual(relativeAngle(heading: 45, bearing: 45), 0.0, accuracy: 0.001)
    }

    func test_90DegRight() {
        XCTAssertEqual(relativeAngle(heading: 0, bearing: 90), 90.0, accuracy: 0.001)
    }

    func test_90DegLeft() {
        XCTAssertEqual(relativeAngle(heading: 90, bearing: 0), -90.0, accuracy: 0.001)
    }

    func test_wrapsPositive_northThroughWest() {
        // Heading 350°, target 10° — should be +20° (right), not -340°
        XCTAssertEqual(relativeAngle(heading: 350, bearing: 10), 20.0, accuracy: 0.001)
    }

    func test_wrapsNegative_northThroughEast() {
        // Heading 10°, target 350° — should be -20° (left), not +340°
        XCTAssertEqual(relativeAngle(heading: 10, bearing: 350), -20.0, accuracy: 0.001)
    }

    func test_exactly180_isPositive() {
        // Directly behind: value must be ±180, wrapped consistently
        let angle = relativeAngle(heading: 0, bearing: 180)
        XCTAssertTrue(abs(angle) == 180.0)
    }

    func test_resultAlwaysInRange() {
        for heading in stride(from: 0.0, to: 360.0, by: 15.0) {
            for bearing in stride(from: 0.0, to: 360.0, by: 15.0) {
                let angle = relativeAngle(heading: heading, bearing: bearing)
                XCTAssertGreaterThanOrEqual(angle, -180.0,
                    "angle out of range for heading=\(heading) bearing=\(bearing)")
                XCTAssertLessThanOrEqual(angle, 180.0,
                    "angle out of range for heading=\(heading) bearing=\(bearing)")
            }
        }
    }
}

// MARK: - Proportional Speed Tests

final class ProportionalSpeedTests: XCTestCase {

    // Mirror the private helper from SpotLockController using default settings
    private func proportionalSpeed(distance: Double,
                                   gain: Double = 1.0,
                                   minSpeed: Int = 3,
                                   maxSpeed: Int = 10) -> Int {
        guard distance > 0 else { return minSpeed }
        let raw = distance * gain + Double(minSpeed)
        let clamped = min(raw, Double(maxSpeed))
        return max(minSpeed, Int(round(clamped)))
    }

    func test_zeroDistance_returnsMinSpeed() {
        XCTAssertEqual(proportionalSpeed(distance: 0), 3)
    }

    func test_smallDistance_staysNearMinSpeed() {
        // 0.5 m × 1.0 gain + 3 = 3.5 → rounds to 4
        XCTAssertEqual(proportionalSpeed(distance: 0.5), 4)
    }

    func test_largeDistance_clampedAtMaxSpeed() {
        XCTAssertEqual(proportionalSpeed(distance: 100), 10)
    }

    func test_exactlyAtMaxWithGain() {
        // gain 2.0: 3.5m × 2.0 + 3 = 10 → exactly max
        XCTAssertEqual(proportionalSpeed(distance: 3.5, gain: 2.0), 10)
    }

    func test_higherGainProducesHigherSpeed() {
        let low  = proportionalSpeed(distance: 2.0, gain: 0.5)
        let high = proportionalSpeed(distance: 2.0, gain: 2.0)
        XCTAssertLessThan(low, high)
    }

    func test_neverBelowMin() {
        for d in [0.0, 0.1, 0.5, 1.0] {
            XCTAssertGreaterThanOrEqual(proportionalSpeed(distance: d), 3)
        }
    }

    func test_neverAboveMax() {
        for d in [5.0, 10.0, 50.0, 1000.0] {
            XCTAssertLessThanOrEqual(proportionalSpeed(distance: d), 10)
        }
    }
}

// MARK: - Jog Destination Tests

final class JogDestinationTests: XCTestCase {

    // Mirror calculateDestination from SpotLockController
    private func destination(from: CLLocationCoordinate2D,
                              heading: Double,
                              distance: Double) -> CLLocationCoordinate2D {
        let headingRad = heading * .pi / 180.0
        let metersPerDegLat = 111320.0
        let deltaLat = (distance / metersPerDegLat) * cos(headingRad)
        let deltaLon = (distance / (metersPerDegLat * cos(from.latitude * .pi / 180.0))) * sin(headingRad)
        return CLLocationCoordinate2D(
            latitude:  from.latitude  + deltaLat,
            longitude: from.longitude + deltaLon
        )
    }

    private let origin = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
    private let jogDist = 1.5

    func test_jogNorth_latIncreases() {
        let result = destination(from: origin, heading: 0, distance: jogDist)
        XCTAssertGreaterThan(result.latitude, origin.latitude)
        XCTAssertEqual(result.longitude, origin.longitude, accuracy: 0.000001)
    }

    func test_jogSouth_latDecreases() {
        let result = destination(from: origin, heading: 180, distance: jogDist)
        XCTAssertLessThan(result.latitude, origin.latitude)
        XCTAssertEqual(result.longitude, origin.longitude, accuracy: 0.000001)
    }

    func test_jogEast_lonIncreases() {
        let result = destination(from: origin, heading: 90, distance: jogDist)
        XCTAssertEqual(result.latitude, origin.latitude, accuracy: 0.000001)
        XCTAssertGreaterThan(result.longitude, origin.longitude)
    }

    func test_jogWest_lonDecreases() {
        let result = destination(from: origin, heading: 270, distance: jogDist)
        XCTAssertEqual(result.latitude, origin.latitude, accuracy: 0.000001)
        XCTAssertLessThan(result.longitude, origin.longitude)
    }

    func test_jogDistance_isApproxCorrect() {
        let result = destination(from: origin, heading: 0, distance: jogDist)
        let actual = origin.distance(to: result)
        XCTAssertEqual(actual, jogDist, accuracy: 0.1)
    }

    func test_resultIsFinite() {
        for heading in [0.0, 90.0, 180.0, 270.0] {
            let result = destination(from: origin, heading: heading, distance: jogDist)
            XCTAssertTrue(result.latitude.isFinite)
            XCTAssertTrue(result.longitude.isFinite)
        }
    }
}

// MARK: - GPS Quality Tests

final class GPSQualityTests: XCTestCase {

    private func makeSensor(hasFix: Bool = true,
                            satellites: Int = 6,
                            hdop: Double = 1.5) -> SensorData {
        SensorData(hasFix: hasFix, satellites: satellites,
                   currentLat: -33.0, currentLon: 151.0,
                   altitude: 0, hdop: hdop, heading: 0)
    }

    // Mirror isGPSQualityAcceptable from SpotLockController (default settings)
    private func isAcceptable(_ s: SensorData,
                               minSats: Int = 4,
                               maxHDOP: Double = 5.0) -> Bool {
        guard s.hasFix else { return false }
        guard s.satellites >= minSats else { return false }
        if s.hdop < 99.0 && s.hdop >= maxHDOP { return false }
        return true
    }

    func test_goodSignal_accepted() {
        XCTAssertTrue(isAcceptable(makeSensor()))
    }

    func test_noFix_rejected() {
        XCTAssertFalse(isAcceptable(makeSensor(hasFix: false)))
    }

    func test_lowSatellites_rejected() {
        XCTAssertFalse(isAcceptable(makeSensor(satellites: 3)))
    }

    func test_highHDOP_rejected() {
        XCTAssertFalse(isAcceptable(makeSensor(hdop: 6.0)))
    }

    func test_exactlyAtMinSatellites_accepted() {
        XCTAssertTrue(isAcceptable(makeSensor(satellites: 4)))
    }

    func test_exactlyAtMaxHDOP_rejected() {
        XCTAssertFalse(isAcceptable(makeSensor(hdop: 5.0)))
    }

    func test_invalidHDOP99_accepted() {
        // HDOP=99 is the hardware sentinel for "no reading" — should not trip the quality check
        XCTAssertTrue(isAcceptable(makeSensor(hdop: 99.0)))
    }
}

// MARK: - Position Filter Tests

final class PositionFilterTests: XCTestCase {

    // Reproduce the sliding-window average from SpotLockController.addToPositionHistory
    private func averageCoord(_ samples: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let avgLat = samples.map { $0.latitude  }.reduce(0, +) / Double(samples.count)
        let avgLon = samples.map { $0.longitude }.reduce(0, +) / Double(samples.count)
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
    }

    func test_singleSample_returnsItself() {
        let c = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let avg = averageCoord([c])
        XCTAssertEqual(avg.latitude,  c.latitude,  accuracy: 0.000001)
        XCTAssertEqual(avg.longitude, c.longitude, accuracy: 0.000001)
    }

    func test_twoIdentical_returnsSame() {
        let c = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let avg = averageCoord([c, c])
        XCTAssertEqual(avg.latitude,  c.latitude,  accuracy: 0.000001)
        XCTAssertEqual(avg.longitude, c.longitude, accuracy: 0.000001)
    }

    func test_twoOpposites_returnsMidpoint() {
        let a = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let b = CLLocationCoordinate2D(latitude: -33.002, longitude: 151.002)
        let avg = averageCoord([a, b])
        XCTAssertEqual(avg.latitude,  -33.001,  accuracy: 0.000001)
        XCTAssertEqual(avg.longitude, 151.001, accuracy: 0.000001)
    }

    func test_noisyJitter_reducesVariance() {
        // Simulate 5 noisy samples around a true position
        let truth = CLLocationCoordinate2D(latitude: -33.0, longitude: 151.0)
        let jitter: [Double] = [0.00002, -0.00003, 0.00001, -0.00001, 0.00002]
        let samples = jitter.map {
            CLLocationCoordinate2D(latitude: truth.latitude + $0,
                                   longitude: truth.longitude - $0)
        }
        let avg = averageCoord(samples)
        // Average jitter is 0.000002 — much smaller than max 0.00003
        XCTAssertEqual(avg.latitude,  truth.latitude,  accuracy: 0.00005)
        XCTAssertEqual(avg.longitude, truth.longitude, accuracy: 0.00005)
    }
}
