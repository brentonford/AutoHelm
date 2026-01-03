import Foundation
import CoreBluetooth
import CoreLocation
import Combine

private enum BleUuids {
    nonisolated static let service = CBUUID(string: "FFE0")
    nonisolated static let sensorStatus = CBUUID(string: "FFE2")
    nonisolated static let command = CBUUID(string: "FFE3")
    nonisolated static let calibration = CBUUID(string: "FFE4")
}

private enum BleConstants {
    nonisolated static let deviceName = "Helm"
    static let reconnectDelaySeconds: TimeInterval = 3.0
    static let rssiUpdateIntervalSeconds: TimeInterval = 2.0
}

private struct FinalCalibrationResponse: Codable {
    let ack: String
    let offsetX: Double
    let offsetY: Double
    let offsetZ: Double
    let scaleX: Double
    let scaleY: Double
    let scaleZ: Double
    let headingOffset: Double?
}

struct BLECommandHistory: Identifiable {
    let id = UUID()
    let command: String
    let timestamp: Date
}

@MainActor
class BluetoothManager: NSObject, ObservableObject {

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var sensorData: SensorData?
    @Published private(set) var lastResponse: BleResponse?
    @Published private(set) var lastError: String?
    @Published private(set) var rssi: Int = -100
    @Published private(set) var signalStrength: BLESignalStrength = .disconnected
    @Published private(set) var calibrationData: CalibrationData?
    @Published private(set) var isCalibrating: Bool = false
    @Published private(set) var commandHistory: [BLECommandHistory] = []

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var sensorStatusChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var calibrationChar: CBCharacteristic?

    private var reconnectTimer: Timer?
    private var rssiTimer: Timer?
    private var shouldReconnect = true
    
    private var locationTracker: LocationWithSpeed?
    private var lastLocationUpdate: Date?
    
    private let maxCommandHistory = 5

    override init() {
        super.init()
    }

    func initialize() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func startScanning() {
        guard let central = centralManager, central.state == .poweredOn else { return }

        connectionState = .scanning
        central.scanForPeripherals(withServices: [BleUuids.service], options: nil)
    }

    func stopScanning() {
        centralManager?.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTimer?.invalidate()
        rssiTimer?.invalidate()

        if let peripheral = peripheral, let central = centralManager {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func sendCommand(_ command: String) {
        guard let data = command.data(using: .utf8) else { return }
        writeToCharacteristic(commandChar, data: data)
        
        // Add to command history
        let historyEntry = BLECommandHistory(command: command, timestamp: Date())
        commandHistory.insert(historyEntry, at: 0)
        
        // Keep only last 5 commands
        if commandHistory.count > maxCommandHistory {
            commandHistory = Array(commandHistory.prefix(maxCommandHistory))
        }
    }

    func sendMotorCommand(_ command: String) {
        sendCommand(command)
    }

    func startCalibration() {
        sendCommand("START_CAL")
        isCalibrating = true
    }

    func stopCalibration() {
        sendCommand("STOP_CAL")
    }

    func sendCalibrationValues(_ calibration: CompassCalibration) {
        print("[BLE] sendCalibrationValues called with: offset(\(calibration.offsetX),\(calibration.offsetY),\(calibration.offsetZ)) scale(\(calibration.scaleX),\(calibration.scaleY),\(calibration.scaleZ)) headingOffset(\(calibration.headingOffset)) sampleCount=\(calibration.sampleCount) isCalibrated=\(calibration.isCalibrated)")
        
        guard calibration.isCalibrated else {
            print("[BLE] ERROR: Attempted to send uncalibrated values to device")
            return
        }
        
        guard abs(calibration.offsetX) > 0.01 || abs(calibration.offsetY) > 0.01 || abs(calibration.offsetZ) > 0.01 else {
            print("[BLE] ERROR: Attempted to send zero calibration offsets to device")
            return
        }
        
        let command = calibration.toCommandString()
        print("[BLE] Sending command: \(command)")
        sendCommand(command)
    }
    
    // MARK: - Heading Calibration Methods
    
    func getCurrentHeading() async -> Double? {
        guard let sensorData = sensorData else {
            print("[BLE] No sensor data available for heading")
            return nil
        }
        return sensorData.heading
    }
    
    func setHeadingOffset(_ offset: Double) {
        var calibration = DataStore.shared.calibration
        calibration.headingOffset = offset
        DataStore.shared.updateCalibration(calibration)
        
        print("[BLE] Heading offset set to \(offset)° - sending to device...")
        sendCalibrationValues(calibration)
    }

    private func writeToCharacteristic(_ characteristic: CBCharacteristic?, data: Data) {
        guard let char = characteristic, let peripheral = peripheral else {
            lastError = "Not connected"
            return
        }
        peripheral.writeValue(data, for: char, type: .withResponse)
    }

    private func startRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: BleConstants.rssiUpdateIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.peripheral?.readRSSI()
            }
        }
    }

    private func stopRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssi = -100
        signalStrength = .disconnected
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: BleConstants.reconnectDelaySeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startScanning()
            }
        }
    }

    private func clearCharacteristics() {
        sensorStatusChar = nil
        commandChar = nil
        calibrationChar = nil
    }
    
    private func clearDeviceData() {
        sensorData = nil
        lastResponse = nil
        locationTracker = nil
        lastLocationUpdate = nil
        isCalibrating = false
        calibrationData = nil
    }
    
    @MainActor
    private func autoUploadCalibration() {
        let calibration = DataStore.shared.calibration
        
        guard calibration.isCalibrated else {
            print("[BLE] No calibration to auto-upload")
            return
        }
        
        guard commandChar != nil else {
            print("[BLE] Command characteristic not ready for auto-upload")
            return
        }
        
        print("[BLE] Auto-uploading calibration on connect...")
        sendCalibrationValues(calibration)
    }
    
    private func parseSensorStatus(_ data: Data) {
        do {
            var status = try JSONDecoder().decode(SensorData.self, from: data)
            
            let coordinate = CLLocationCoordinate2D(
                latitude: status.currentLat,
                longitude: status.currentLon
            )
            
            if locationTracker == nil {
                locationTracker = LocationWithSpeed(coordinate: coordinate)
            } else {
                locationTracker?.updateLocation(coordinate)
            }
            
            status.calculatedSpeed = locationTracker?.speed ?? 0
            
            self.sensorData = status
            lastLocationUpdate = Date()
        } catch {
            print("Sensor status parse error: \(error)")
        }
    }

    private func parseCalibrationCharacteristic(_ data: Data) {
        // Try to decode final calibration response first (most specific)
        if let finalCal = try? JSONDecoder().decode(FinalCalibrationResponse.self, from: data) {
            print("[BLE] Received final calibration: offset(\(finalCal.offsetX),\(finalCal.offsetY),\(finalCal.offsetZ)) scale(\(finalCal.scaleX),\(finalCal.scaleY),\(finalCal.scaleZ)) headingOffset(\(finalCal.headingOffset ?? 0))")
            
            if finalCal.ack == "CAL_STOPPED" {
                isCalibrating = false
                
                let sampleCount = calibrationData?.samples ?? 0
                print("[BLE] Using sample count: \(sampleCount)")
                
                // Preserve existing headingOffset when updating magnetometer calibration
                let existingHeadingOffset = DataStore.shared.calibration.headingOffset
                
                let calibration = CompassCalibration(
                    offsetX: finalCal.offsetX,
                    offsetY: finalCal.offsetY,
                    offsetZ: finalCal.offsetZ,
                    scaleX: finalCal.scaleX,
                    scaleY: finalCal.scaleY,
                    scaleZ: finalCal.scaleZ,
                    headingOffset: finalCal.headingOffset ?? existingHeadingOffset,
                    dateCalibrated: Date(),
                    sampleCount: max(sampleCount, 1)
                )
                
                print("[BLE] Created calibration object with headingOffset: \(calibration.headingOffset)")
                
                DataStore.shared.updateCalibration(calibration)
                print("[BLE] Saved calibration to DataStore")
                
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    let commandString = calibration.toCommandString()
                    print("[BLE] Sending calibration back to device: \(commandString)")
                    self.sendCalibrationValues(calibration)
                }
                
                self.lastResponse = BleResponse(ack: finalCal.ack, error: nil)
            }
            return
        }
        
        // Only update calibration data if we're actively calibrating
        if isCalibrating {
            if let calData = try? JSONDecoder().decode(CalibrationData.self, from: data) {
                self.calibrationData = calData
                return
            }
        }
        
        if let response = try? JSONDecoder().decode(BleResponse.self, from: data) {
            self.lastResponse = response
            
            if let ack = response.ack {
                if ack == "START_CAL" || ack == "CAL_STARTED" {
                    isCalibrating = true
                } else if ack == "STOP_CAL" || ack == "CAL_STOPPED" {
                    isCalibrating = false
                }
            }
            
            if let error = response.error {
                self.lastError = error
            }
            return
        }
        
        print("[BLE] Failed to parse calibration characteristic data: \(String(data: data, encoding: .utf8) ?? "non-UTF8")")
    }
}

extension BluetoothManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                startScanning()
            case .poweredOff:
                connectionState = .disconnected
                clearDeviceData()
                lastError = "Bluetooth is off"
            case .unauthorized:
                lastError = "Bluetooth permission denied"
            case .unsupported, .resetting, .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? "Unknown"
        guard name == BleConstants.deviceName else { return }

        central.stopScan()

        Task { @MainActor in
            self.peripheral = peripheral
            peripheral.delegate = self
            self.connectionState = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionState = .connected
            shouldReconnect = true
            peripheral.discoverServices([BleUuids.service])
            startRSSIMonitoring()
            
            // AUTO-UPLOAD: Wait for characteristics to be discovered, then send calibration
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                autoUploadCalibration()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            connectionState = .disconnected
            lastError = error?.localizedDescription ?? "Connection failed"
            clearCharacteristics()
            clearDeviceData()
            stopRSSIMonitoring()
            scheduleReconnect()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            connectionState = .disconnected
            clearCharacteristics()
            clearDeviceData()
            stopRSSIMonitoring()
            scheduleReconnect()
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BleUuids.service }) else { return }

        peripheral.discoverCharacteristics([
            BleUuids.sensorStatus,
            BleUuids.command,
            BleUuids.calibration
        ], for: service)
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }

        Task { @MainActor in
            for char in characteristics {
                switch char.uuid {
                case BleUuids.sensorStatus:
                    sensorStatusChar = char
                    peripheral.setNotifyValue(true, for: char)
                case BleUuids.command:
                    commandChar = char
                case BleUuids.calibration:
                    calibrationChar = char
                    peripheral.setNotifyValue(true, for: char)
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }

        Task { @MainActor in
            switch characteristic.uuid {
            case BleUuids.sensorStatus:
                parseSensorStatus(data)
            case BleUuids.calibration:
                parseCalibrationCharacteristic(data)
            default:
                break
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            rssi = RSSI.intValue
            signalStrength = BLESignalStrength.from(rssi: RSSI.intValue)
        }
    }
}