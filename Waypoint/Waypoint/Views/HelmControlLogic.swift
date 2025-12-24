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
    }
    
    func startNavigation(to waypoint: Waypoint) {
        guard let sensors = bluetooth.sensorData else { return }
        
        totalDistance = sensors.currentLocation.distance(to: waypoint.coordinate)
        motorOn = false
        currentSpeedLevel = 0
        targetSpeedLevel = 4
        lastSpeedCommandTime = nil
        accelerationStartTime = Date()
        steeringCommand = "None"
        speedCommand = "Stopped"
        navigationEnabled = true
        
        startNavigationAutomation()
    }
    
    func stopNavigation() {
        navigationEnabled = false
        stopNavigationAutomation()
        
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
            stopNavigation()
            return
        }
        
        if !motorOn && currentSpeedLevel == 0 {
            if let accelStart = accelerationStartTime {
                let timeSinceStart = Date().timeIntervalSince(accelStart)
                if timeSinceStart >= Constants.initialAccelDelaySeconds {
                    bluetooth.sendMotorCommand("RF_MOTOR")
                    await delay(Constants.navigationCommandDelaySeconds)
                    motorOn = true
                }
            }
        }
        
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
            await delay(Constants.navigationCommandDelaySeconds)
        } else {
            steeringCommand = "On Course"
        }
        
        if currentSpeedLevel < targetSpeedLevel && motorOn {
            if let lastCmd = lastSpeedCommandTime {
                let timeSinceCommand = Date().timeIntervalSince(lastCmd)
                if timeSinceCommand >= Constants.accelIntervalSeconds {
                    speedCommand = "SPEED+"
                    bluetooth.sendMotorCommand("RF_UP")
                    currentSpeedLevel += 1
                    lastSpeedCommandTime = Date()
                    await delay(Constants.navigationCommandDelaySeconds)
                }
            } else {
                speedCommand = "SPEED+"
                bluetooth.sendMotorCommand("RF_UP")
                currentSpeedLevel += 1
                lastSpeedCommandTime = Date()
                await delay(Constants.navigationCommandDelaySeconds)
            }
        } else if currentSpeedLevel == targetSpeedLevel {
            speedCommand = "At Target"
        }
    }
    
    func shutdownMotor() async {
        guard motorOn else { return }
        
        while currentSpeedLevel > 0 {
            speedCommand = "SPEED-"
            bluetooth.sendMotorCommand("RF_DOWN")
            currentSpeedLevel -= 1
            await delay(Constants.navigationCommandDelaySeconds)
        }
        
        bluetooth.sendMotorCommand("RF_MOTOR")
        await delay(Constants.navigationCommandDelaySeconds)
        motorOn = false
        speedCommand = "Stopped"
    }
    
    func startSpotLockAutomation() {
        stopSpotLock()
        isHoldingMomentary = false
        
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