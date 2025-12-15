import Foundation
import CoreBluetooth
import Combine

// UUIDs defined as nonisolated to avoid MainActor isolation issues
private nonisolated(unsafe) let helmServiceUuid = CBUUID(string: "FFE0")
private nonisolated(unsafe) let helmWaypointCharUuid = CBUUID(string: "FFE1")
private nonisolated(unsafe) let helmStatusCharUuid = CBUUID(string: "FFE2")
private nonisolated(unsafe) let helmCommandCharUuid = CBUUID(string: "FFE3")
private nonisolated(unsafe) let helmCalibrationCharUuid = CBUUID(string: "FFE4")

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var deviceStatus: DeviceStatus?
    @Published var lastResponse: BleResponse?
    @Published var lastError: String?
    
    // MARK: - BLE Objects
    
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var waypointChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var calibrationChar: CBCharacteristic?
    
    // MARK: - Reconnection
    
    private var reconnectTimer: Timer?
    private var shouldReconnect = true
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    func initialize() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        
        connectionState = .scanning
        central.scanForPeripherals(withServices: [helmServiceUuid], options: nil)
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
        
        if let peripheral = peripheral, let central = centralManager {
            central.cancelPeripheralConnection(peripheral)
        }
    }
    
    func sendWaypoint(_ waypoint: Waypoint) {
        guard let char = waypointChar, let peripheral = peripheral else {
            lastError = "Not connected"
            return
        }
        
        let data = waypoint.toGpsString().data(using: .utf8)!
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func sendCommand(_ command: String) {
        guard let char = commandChar, let peripheral = peripheral else {
            lastError = "Not connected"
            return
        }
        
        let data = command.data(using: .utf8)!
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func enableNavigation() {
        sendCommand("NAV_ENABLE")
    }
    
    func disableNavigation() {
        sendCommand("NAV_DISABLE")
    }
    
    func startCalibration() {
        sendCommand("START_CAL")
    }
    
    func stopCalibration() {
        sendCommand("STOP_CAL")
    }
    
    // MARK: - Private Methods
    
    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.startScanning()
            }
        }
    }
    
    private func clearCharacteristics() {
        waypointChar = nil
        statusChar = nil
        commandChar = nil
        calibrationChar = nil
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
            default:
                break
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        let name = peripheral.name ?? "Unknown"
        guard name == "Helm" else { return }
        
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
            peripheral.discoverServices([helmServiceUuid])
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionState = .disconnected
            lastError = error?.localizedDescription ?? "Connection failed"
            clearCharacteristics()
            scheduleReconnect()
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionState = .disconnected
            clearCharacteristics()
            scheduleReconnect()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == helmServiceUuid }) else { return }
        
        peripheral.discoverCharacteristics([
            helmWaypointCharUuid,
            helmStatusCharUuid,
            helmCommandCharUuid,
            helmCalibrationCharUuid
        ], for: service)
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        Task { @MainActor in
            for char in characteristics {
                switch char.uuid {
                case helmWaypointCharUuid:
                    waypointChar = char
                case helmStatusCharUuid:
                    statusChar = char
                    peripheral.setNotifyValue(true, for: char)
                case helmCommandCharUuid:
                    commandChar = char
                case helmCalibrationCharUuid:
                    calibrationChar = char
                    peripheral.setNotifyValue(true, for: char)
                default:
                    break
                }
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        Task { @MainActor in
            switch characteristic.uuid {
            case helmStatusCharUuid:
                parseStatus(data)
            case helmCalibrationCharUuid:
                parseResponse(data)
            default:
                break
            }
        }
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