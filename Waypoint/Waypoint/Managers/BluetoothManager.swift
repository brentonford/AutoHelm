import Foundation
import CoreBluetooth
import Combine

// MARK: - Constants (outside MainActor class)

private enum BleUuids {
    static let service = CBUUID(string: "FFE0")
    static let waypoint = CBUUID(string: "FFE1")
    static let status = CBUUID(string: "FFE2")
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

    // MARK: - Published Properties
    
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var deviceStatus: DeviceStatus?
    @Published private(set) var lastResponse: BleResponse?
    @Published private(set) var lastError: String?
    @Published private(set) var rssi: Int = -100
    @Published private(set) var signalStrength: BLESignalStrength = .disconnected

    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var waypointChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var calibrationChar: CBCharacteristic?

    private var reconnectTimer: Timer?
    private var rssiTimer: Timer?
    private var shouldReconnect = true

    // MARK: - Initialization
    
    override init() {
        super.init()
    }

    // MARK: - Public Methods
    
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

    func sendWaypoint(_ waypoint: Waypoint) {
        guard let data = waypoint.toGpsString().data(using: .utf8) else { return }
        writeToCharacteristic(waypointChar, data: data)
    }

    func sendCommand(_ command: String) {
        guard let data = command.data(using: .utf8) else { return }
        writeToCharacteristic(commandChar, data: data)
    }

    func sendRawData(_ data: String) {
        guard let dataBytes = data.data(using: .utf8) else { return }
        writeToCharacteristic(waypointChar, data: dataBytes)
    }

    // MARK: - Navigation Control

    func enableNavigation() {
        sendCommand("NAV_ENABLE")
    }

    func disableNavigation() {
        sendCommand("NAV_DISABLE")
    }

    func enableManualMode() {
        sendCommand("MANUAL_MODE")
    }

    // MARK: - Calibration

    func startCalibration() {
        sendCommand("START_CAL")
    }

    func stopCalibration() {
        sendCommand("STOP_CAL")
    }

    // MARK: - Spot Lock

    func engageSpotLock() {
        sendCommand("SPOT_LOCK")
    }

    func disengageSpotLock() {
        sendCommand("SPOT_RELEASE")
    }

    func jogSpotLock(direction: JogDirection) {
        let command: String
        switch direction {
        case .forward:
            command = "JOG_FWD"
        case .back:
            command = "JOG_BACK"
        case .left:
            command = "JOG_LEFT"
        case .right:
            command = "JOG_RIGHT"
        }
        sendCommand(command)
    }

    // MARK: - Path Control

    func startPath() {
        sendCommand("PATH_START")
    }

    func stopPath() {
        sendCommand("PATH_STOP")
    }

    func sendPath(_ path: Path) {
        let pathStr = "$PATH,\(path.name),\(path.defaultSpeed),\(path.loop ? 1 : 0)*"
        sendRawData(pathStr)

        for wp in path.waypoints {
            sendWaypoint(wp)
        }
    }

    // MARK: - Speed Control

    func setSpeed(_ kmh: Double) {
        sendCommand("SPEED:\(String(format: "%.1f", kmh))")
    }

    // MARK: - Private Methods

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
        waypointChar = nil
        statusChar = nil
        commandChar = nil
        calibrationChar = nil
    }
    
    private func parseStatus(_ data: Data) {
        do {
            let status = try JSONDecoder().decode(DeviceStatus.self, from: data)
            self.deviceStatus = status
        } catch {
            print("Status parse error: \(error)")
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

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                startScanning()
            case .poweredOff:
                connectionState = .disconnected
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
            stopRSSIMonitoring()
            scheduleReconnect()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BleUuids.service }) else { return }

        peripheral.discoverCharacteristics([
            BleUuids.waypoint,
            BleUuids.status,
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
                case BleUuids.waypoint:
                    waypointChar = char
                case BleUuids.status:
                    statusChar = char
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
            case BleUuids.status:
                parseStatus(data)
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