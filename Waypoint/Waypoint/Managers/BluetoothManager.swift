import Foundation
import CoreBluetooth
import CoreLocation
import Combine

private enum BleUuids {
    static let service = CBUUID(string: "FFE0")
    static let sensorStatus = CBUUID(string: "FFE2")
    static let command = CBUUID(string: "FFE3")
    static let calibration = CBUUID(string: "FFE4")
}

private enum BleConstants {
    static let deviceName = "Helm"
    static let reconnectDelaySeconds: TimeInterval = 3.0
    static let rssiUpdateIntervalSeconds: TimeInterval = 2.0
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
    }

    func sendMotorCommand(_ command: String) {
        sendCommand(command)
    }

    func startCalibration() {
        sendCommand("START_CAL")
    }

    func stopCalibration() {
        sendCommand("STOP_CAL")
    }

    func sendCalibrationValues(_ calibration: CompassCalibration) {
        let command = calibration.toCommandString()
        sendCommand(command)
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

    private func parseResponse(_ data: Data) {
        do {
            let response = try JSONDecoder().decode(BleResponse.self, from: data)
            self.lastResponse = response
            if let error = response.error {
                self.lastError = error
            }
        } catch {
            print("Response parse error: \(error)")
        }
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
                parseResponse(data)
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