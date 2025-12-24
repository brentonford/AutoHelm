import Foundation
import Combine

@MainActor
class SpeedController: ObservableObject {
    
    @Published private(set) var targetSpeedKmh: Double = 3.6
    @Published private(set) var targetSpeedLevel: Int = 10
    @Published private(set) var speedCommand: String = "Stopped"
    
    private let bluetooth: BluetoothManager
    private let motorController: MotorController
    
    private var lastSpeedCommandTime: Date?
    private let accelerationIntervalSeconds: Double = 1.5
    private let speedToleranceKmh: Double = 0.5
    
    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        self.motorController = MotorController(bluetooth: bluetooth)
    }
    
    func setTargetSpeed(_ speedKmh: Double) {
        targetSpeedKmh = speedKmh
        targetSpeedLevel = calculateTargetSpeedLevel(for: speedKmh)
    }
    
    func updateSpeed(currentSpeed: Double) async {
        let currentLevel = motorController.currentSpeedLevel
        
        if currentLevel < targetSpeedLevel {
            await accelerate(currentSpeed: currentSpeed)
        } else if currentLevel > targetSpeedLevel {
            await decelerate(currentSpeed: currentSpeed)
        } else {
            await maintainSpeed(currentSpeed: currentSpeed)
        }
    }
    
    private func accelerate(currentSpeed: Double) async {
        guard canSendSpeedCommand() else {
            speedCommand = "Accelerating..."
            return
        }
        
        speedCommand = "SPEED+"
        await motorController.increaseSpeed()
        lastSpeedCommandTime = Date()
    }
    
    private func decelerate(currentSpeed: Double) async {
        guard canSendSpeedCommand() else {
            speedCommand = "Decelerating..."
            return
        }
        
        speedCommand = "SPEED-"
        await motorController.decreaseSpeed()
        lastSpeedCommandTime = Date()
    }
    
    private func maintainSpeed(currentSpeed: Double) async {
        let currentLevel = motorController.currentSpeedLevel
        
        if currentSpeed < targetSpeedKmh - speedToleranceKmh && currentLevel < 10 {
            guard canSendSpeedCommand() else { return }
            
            speedCommand = "SPEED+ (maintaining)"
            await motorController.increaseSpeed()
            lastSpeedCommandTime = Date()
            
        } else if currentSpeed > targetSpeedKmh + speedToleranceKmh && currentLevel > 1 {
            guard canSendSpeedCommand() else { return }
            
            speedCommand = "SPEED- (maintaining)"
            await motorController.decreaseSpeed()
            lastSpeedCommandTime = Date()
            
        } else {
            speedCommand = "At Target"
        }
    }
    
    private func canSendSpeedCommand() -> Bool {
        guard let lastTime = lastSpeedCommandTime else {
            return true
        }
        return Date().timeIntervalSince(lastTime) >= accelerationIntervalSeconds
    }
    
    private func calculateTargetSpeedLevel(for speedKmh: Double) -> Int {
        let speedMs = speedKmh / 3.6
        let level = Int(round(speedMs / 0.36))
        return min(max(level, 1), 10)
    }
}