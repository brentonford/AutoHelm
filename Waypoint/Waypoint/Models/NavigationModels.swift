    import Foundation

enum SteeringDirection {
    case left
    case right
    case none
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

enum MotorVerificationStatus {
    case unverified
    case clearing
    case verifying
    case verified
    case failed
}