import Foundation
import Combine

@MainActor
class MotorController: ObservableObject {
    
    @Published private(set) var currentSpeedLevel: Int = 0
    @Published private(set) var isMotorOn: Bool = false
    @Published private(set) var verificationStatus: MotorVerificationStatus = .unverified
    
    private let bluetooth: BluetoothManager
    private var verificationAttempts: Int = 0
    
    var sensorData: SensorData? {
        bluetooth.sensorData
    }
    
    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
    }
    
    func initialize() async throws {
        verificationStatus = .clearing
        await clearPowerLevels()
        
        verificationStatus = .verifying
        let verified = await verifyMotorResponse()
        
        if verified {
            verificationStatus = .verified
            isMotorOn = true
            currentSpeedLevel = 1
        } else {
            verificationStatus = .failed
            throw NavigationError.motorNotResponding
        }
    }
    
    func shutdown() async {
        while currentSpeedLevel > 0 {
            await sendCommand(.speedDown)
            currentSpeedLevel -= 1
            await delay(1.0)
        }
        
        if isMotorOn {
            await sendCommand(.motorToggle)
            isMotorOn = false
        }
        
        verificationStatus = .unverified
    }
    
    func increaseSpeed() async {
        guard currentSpeedLevel < 10 else { return }
        await sendCommand(.speedUp)
        currentSpeedLevel += 1
    }
    
    func decreaseSpeed() async {
        guard currentSpeedLevel > 0 else { return }
        await sendCommand(.speedDown)
        currentSpeedLevel -= 1
    }
    
    func sendSteeringCommand(_ direction: SteeringDirection) async {
        switch direction {
        case .left:
            await sendCommand(.left)
        case .right:
            await sendCommand(.right)
        case .none:
            break
        }
    }
    
    private func clearPowerLevels() async {
        for _ in 0..<10 {
            await sendCommand(.speedDown)
            await delay(0.5)
        }
        await delay(1.0)
    }
    
    private func verifyMotorResponse() async -> Bool {
        verificationAttempts = 0
        
        while verificationAttempts < 3 {
            guard let initialSpeed = sensorData?.speedKmh else {
                await delay(1.0)
                continue
            }
            
            await sendCommand(.motorToggle)
            await delay(2.0)
            
            await sendCommand(.speedUp)
            await delay(3.0)
            
            guard let currentSpeed = sensorData?.speedKmh else {
                verificationAttempts += 1
                continue
            }
            
            let speedIncrease = currentSpeed - initialSpeed
            
            if speedIncrease > 0.2 {
                return true
            }
            
            verificationAttempts += 1
            
            if verificationAttempts < 3 {
                await sendCommand(.motorToggle)
                await delay(2.0)
            }
        }
        
        return false
    }
    
    private func sendCommand(_ command: MotorCommand) async {
        let rfCommand = command.rfCommand
        bluetooth.sendMotorCommand(rfCommand)
        await delay(0.1)
    }
    
    private func delay(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

enum MotorCommand {
    case left
    case right
    case speedUp
    case speedDown
    case motorToggle
    case momentary
    case momentaryHold
    case release
    
    var rfCommand: String {
        switch self {
        case .left: return "RF_LEFT"
        case .right: return "RF_RIGHT"
        case .speedUp: return "RF_UP"
        case .speedDown: return "RF_DOWN"
        case .motorToggle: return "RF_MOTOR"
        case .momentary: return "RF_MOMENTARY"
        case .momentaryHold: return "RF_MOMENTARY_HOLD"
        case .release: return "RF_RELEASE"
        }
    }
}

enum SteeringDirection {
    case left
    case right
    case none
}

enum MotorVerificationStatus {
    case unverified
    case clearing
    case verifying
    case verified
    case failed
}