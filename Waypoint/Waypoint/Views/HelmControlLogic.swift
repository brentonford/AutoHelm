import SwiftUI
import CoreLocation

extension HelmControlView {
    
    func startHoldCommand(_ command: String, label: String) {
        stopAllAutomation()
        
        activeHoldButton = label
        commandFeedback = "Sending \(label)..."
        bluetooth.sendCommand(command)
    }

    func stopHoldCommand() {
        guard activeHoldButton != nil else { return }
        
        commandFeedback = "Releasing..."
        bluetooth.sendCommand("RF_RELEASE")

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            activeHoldButton = nil
            commandFeedback = nil
        }
    }

    func sendMomentaryCommand(_ command: String, label: String) {
        stopAllAutomation()
        
        activeMomentaryButton = label
        commandFeedback = "Sending \(label) (1s)..."
        bluetooth.sendCommand(command)

        Task {
            try? await Task.sleep(for: .milliseconds(800))
            activeMomentaryButton = nil
            commandFeedback = nil
        }
    }
    
    func toggleSpotLock() {
        if isSpotLockEngaged {
            stopSpotLock()
        } else {
            guard let sensors = bluetooth.sensorData else { return }
            
            if navigationEnabled {
                stopNavigation()
            }
            
            spotLockPosition = sensors.currentLocation
            isSpotLockEngaged = true
            startSpotLockAutomation()
        }
    }
    
    func jogSpotLock(direction: JogDirection) {
        guard let sensors = bluetooth.sensorData else { return }
        guard let lockPos = spotLockPosition else { return }
        
        let currentHeading = sensors.heading
        var jogHeading = currentHeading
        
        switch direction {
        case .forward:
            break
        case .back:
            jogHeading += 180.0
        case .left:
            jogHeading -= 90.0
        case .right:
            jogHeading += 90.0
        }
        
        jogHeading = ((jogHeading + 360).truncatingRemainder(dividingBy: 360))
        
        let jogHeadingRad = jogHeading * .pi / 180.0
        let metersPerDegLat = 111320.0
        
        let newLat = lockPos.latitude + (Constants.jogDistanceM / metersPerDegLat) * cos(jogHeadingRad)
        let newLon = lockPos.longitude + (Constants.jogDistanceM / (metersPerDegLat * cos(lockPos.latitude * .pi / 180.0))) * sin(jogHeadingRad)
        
        spotLockPosition = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }
    
    func handleNavigationToggle(_ enabled: Bool) {
        if !enabled {
            stopNavigation()
        }
    }
    
    func handleWaypointChange() {
        guard let sensors = bluetooth.sensorData, let waypoint = selectedWaypoint else { return }
        totalDistance = sensors.currentLocation.distance(to: waypoint.coordinate)
        
        if waypoint.approachSpeed > 0 {
            targetSpeedKmh = waypoint.approachSpeed
            targetSpeedLevel = calculateTargetSpeedLevel(for: waypoint.approachSpeed)
        } else {
            targetSpeedKmh = 3.6
            targetSpeedLevel = 10
        }
    }
    
    func calculateTargetSpeedLevel(for speedKmh: Double) -> Int {
        let speedMs = speedKmh / 3.6
        let level = Int(round(speedMs / 0.36))
        return min(max(level, 1), 10)
    }
    
    func startNavigation(to waypoint: Waypoint) {
        guard let sensors = bluetooth.sensorData else { return }
        
        totalDistance = sensors.currentLocation.distance(to: waypoint.coordinate)
        motorOn = false
        currentSpeedLevel = 0
        lastSpeedCommandTime = nil
        accelerationStartTime = Date()
        steeringCommand = "None"
        speedCommand = "Initializing"
        navigationEnabled = true
        navigationPhase = .clearingPowerLevel
        motorVerificationAttempts = 0
        lastGpsSpeed = 0
        
        if waypoint.approachSpeed > 0 {
            targetSpeedKmh = waypoint.approachSpeed
            targetSpeedLevel = calculateTargetSpeedLevel(for: waypoint.approachSpeed)
        } else {
            targetSpeedKmh = 3.6
            targetSpeedLevel = 10
        }
        
        Task {
            await initializeMotor()
        }
    }
    
    func stopNavigation() {
        navigationEnabled = false
        stopNavigationAutomation()
        navigationPhase = .idle
        
        Task {
            await shutdownMotor()
        }
    }
    
    func stopAllAutomation() {
        if navigationEnabled {
            stopNavigation()
        }
        if isSpotLockEngaged {
            stopSpotLock()
        }
    }
    
    func initializeMotor() async {
        navigationPhase = .clearingPowerLevel
        speedCommand = "Clearing power levels..."
        
        for _ in 0..<10 {
            bluetooth.sendMotorCommand("RF_DOWN")
            await delay(0.5)
        }
        
        await delay(1.0)
        
        navigationPhase = .verifyingMotor
        speedCommand = "Verifying motor response..."
        motorVerificationAttempts = 0
        
        let verificationSuccess = await verifyMotorResponse()
        
        if verificationSuccess {
            navigationPhase = .accelerating
            startNavigationAutomation()
        } else {
            navigationEnabled = false
            navigationPhase = .idle
            errorMessage = "Motor not responding to commands. Check motor connection and power."
            showingError = true
            await shutdownMotor()
        }
    }
    
    func verifyMotorResponse() async -> Bool {
        while motorVerificationAttempts < Constants.maxMotorVerificationAttempts {
            guard let sensors = bluetooth.sensorData else {
                await delay(1.0)
                continue
            }
            
            let initialSpeed = sensors.speedKmh
            lastGpsSpeed = initialSpeed
            speedVerificationStartTime = Date()
            
            bluetooth.sendMotorCommand("RF_MOTOR")
            await delay(Constants.navigationCommandDelaySeconds)
            
            bluetooth.sendMotorCommand("RF_UP")
            await delay(Constants.motorVerificationDelaySeconds)
            
            guard let updatedSensors = bluetooth.sensorData else {
                motorVerificationAttempts += 1
                continue
            }
            
            let currentSpeed = updatedSensors.speedKmh
            let speedIncrease = currentSpeed - initialSpeed
            
            if speedIncrease > 0.2 {
                motorOn = true
                currentSpeedLevel = 1
                return true
            }
            
            motorVerificationAttempts += 1
            
            if motorVerificationAttempts < Constants.maxMotorVerificationAttempts {
                bluetooth.sendMotorCommand("RF_MOTOR")
                await delay(Constants.navigationCommandDelaySeconds)
            }
        }
        
        return false
    }
    
    func startNavigationAutomation() {
        stopNavigationAutomation()
        
        navigationTimer = Timer.scheduledTimer(withTimeInterval: Constants.navigationCommandDelaySeconds, repeats: true) { [self] _ in
            Task { @MainActor in
                await self.executeNavigationCycle()
            }
        }
    }
    
    func stopNavigationAutomation() {
        navigationTimer?.invalidate()
        navigationTimer = nil
    }
    
    func executeNavigationCycle() async {
        guard let sensors = bluetooth.sensorData else { return }
        guard let waypoint = selectedWaypoint else { return }
        guard navigationEnabled else { return }
        
        let distance = sensors.currentLocation.distance(to: waypoint.coordinate)
        if distance <= waypoint.arrivalRadius {
            showingArrivalAlert = true
            navigationPhase = .arrived
            
            if waypoint.spotLockEnabled {
                isSpotLockEngaged = true
                spotLockPosition = waypoint.coordinate
                startSpotLockAutomation()
            } else {
                stopNavigation()
            }
            return
        }
        
        await performSteeringCorrection(sensors: sensors, waypoint: waypoint)
        
        await performSpeedControl(sensors: sensors)
    }
    
    func performSteeringCorrection(sensors: SensorData, waypoint: Waypoint) async {
        let bearing = sensors.currentLocation.bearing(to: waypoint.coordinate)
        let relativeAngle = bearing - sensors.heading
        let normalizedRelative = ((relativeAngle + 180).truncatingRemainder(dividingBy: 360)) - 180
        
        if abs(normalizedRelative) > Constants.headingToleranceDegrees {
            if normalizedRelative > 0 {
                steeringCommand = "RIGHT"
                bluetooth.sendMotorCommand("RF_RIGHT")
            } else {
                steeringCommand = "LEFT"
                bluetooth.sendMotorCommand("RF_LEFT")
            }
            await delay(0.5)
        } else {
            steeringCommand = "On Course"
        }
    }
    
    func performSpeedControl(sensors: SensorData) async {
        if currentSpeedLevel < targetSpeedLevel {
            if let lastCmd = lastSpeedCommandTime {
                let timeSinceCommand = Date().timeIntervalSince(lastCmd)
                if timeSinceCommand >= 1.5 {
                    speedCommand = "SPEED+"
                    bluetooth.sendMotorCommand("RF_UP")
                    currentSpeedLevel += 1
                    lastSpeedCommandTime = Date()
                    navigationPhase = .accelerating
                    await delay(0.5)
                }
            } else {
                speedCommand = "SPEED+"
                bluetooth.sendMotorCommand("RF_UP")
                currentSpeedLevel += 1
                lastSpeedCommandTime = Date()
                navigationPhase = .accelerating
                await delay(0.5)
            }
        } else if currentSpeedLevel > targetSpeedLevel {
            speedCommand = "SPEED-"
            bluetooth.sendMotorCommand("RF_DOWN")
            currentSpeedLevel -= 1
            lastSpeedCommandTime = Date()
            await delay(0.5)
        } else {
            navigationPhase = .cruising
            await maintainTargetSpeed(sensors: sensors)
        }
    }
    
    func maintainTargetSpeed(sensors: SensorData) async {
        let currentSpeed = sensors.speedKmh
        
        if currentSpeed < targetSpeedKmh - Constants.speedToleranceKmh && currentSpeedLevel < 10 {
            navigationPhase = .maintaining
            speedCommand = "SPEED+ (maintaining)"
            bluetooth.sendMotorCommand("RF_UP")
            currentSpeedLevel += 1
            lastSpeedCommandTime = Date()
            await delay(0.5)
        } else if currentSpeed > targetSpeedKmh + Constants.speedToleranceKmh && currentSpeedLevel > 1 {
            navigationPhase = .maintaining
            speedCommand = "SPEED- (maintaining)"
            bluetooth.sendMotorCommand("RF_DOWN")
            currentSpeedLevel -= 1
            lastSpeedCommandTime = Date()
            await delay(0.5)
        } else {
            speedCommand = "At Target"
        }
    }
    
    func shutdownMotor() async {
        guard motorOn else { return }
        
        speedCommand = "Shutting down..."
        
        while currentSpeedLevel > 0 {
            speedCommand = "SPEED-"
            bluetooth.sendMotorCommand("RF_DOWN")
            currentSpeedLevel -= 1
            await delay(1.0)
        }
        
        bluetooth.sendMotorCommand("RF_MOTOR")
        await delay(Constants.navigationCommandDelaySeconds)
        motorOn = false
        speedCommand = "Stopped"
    }
    
    func startSpotLockAutomation() {
        stopSpotLock()
        isHoldingMomentary = false
        navigationPhase = .spotLock
        
        spotLockTimer = Timer.scheduledTimer(withTimeInterval: Constants.navigationCommandDelaySeconds, repeats: true) { [self] _ in
            Task { @MainActor in
                await self.executeSpotLockCycle()
            }
        }
    }
    
    func stopSpotLock() {
        spotLockTimer?.invalidate()
        spotLockTimer = nil
        isSpotLockEngaged = false
        
        if isHoldingMomentary {
            bluetooth.sendMotorCommand("RF_RELEASE")
            isHoldingMomentary = false
        }
    }
    
    func executeSpotLockCycle() async {
        guard let sensors = bluetooth.sensorData else { return }
        guard isSpotLockEngaged else { return }
        guard let lockPosition = spotLockPosition else { return }
        
        let currentLocation = sensors.currentLocation
        let distance = currentLocation.distance(to: lockPosition)
        
        let bearing = currentLocation.bearing(to: lockPosition)
        let relativeAngle = bearing - sensors.heading
        let normalizedRelative = ((relativeAngle + 180).truncatingRemainder(dividingBy: 360)) - 180
        
        if distance > Constants.spotLockHoldRadius {
            if !isHoldingMomentary {
                bluetooth.sendMotorCommand("RF_MOMENTARY_HOLD")
                isHoldingMomentary = true
                await delay(Constants.navigationCommandDelaySeconds)
            }
            
            if abs(normalizedRelative) > Constants.headingToleranceDegrees {
                if normalizedRelative > 0 {
                    bluetooth.sendMotorCommand("RF_RIGHT")
                } else {
                    bluetooth.sendMotorCommand("RF_LEFT")
                }
                await delay(Constants.navigationCommandDelaySeconds)
            }
        } else {
            if isHoldingMomentary {
                bluetooth.sendMotorCommand("RF_RELEASE")
                isHoldingMomentary = false
                await delay(Constants.navigationCommandDelaySeconds)
            }
        }
    }
    
    func updateNavigationData(_ sensors: SensorData) {
    }
    
    func delay(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
    
    func formatEstimatedTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
    
    func steeringCommandDisplayText(_ command: String) -> String {
        switch command {
        case "LEFT": return "← LEFT"
        case "RIGHT": return "→ RIGHT"
        case "On Course": return "✓ On Course"
        case "None": return "⊗ None"
        default: return command
        }
    }

    func steeringCommandColor(for command: String) -> Color {
        switch command {
        case "LEFT", "RIGHT": return .orange
        case "On Course": return .green
        default: return .gray
        }
    }
    
    func speedCommandDisplayText(_ command: String) -> String {
        switch command {
        case "SPEED+": return "↑ SPEED +"
        case "SPEED-": return "↓ SPEED -"
        case "At Target": return "✓ At Target"
        case "Stopped": return "⊗ Stopped"
        default: return command
        }
    }
    
    func speedCommandColor(for command: String) -> Color {
        switch command {
        case "SPEED+": return .blue
        case "SPEED-": return .orange
        case "At Target": return .green
        default: return .gray
        }
    }
}