import Foundation
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var deviceStatus: DeviceStatus?
    @Published var lastResponse: BleResponse?
    @Published var lastError: String?
    
    // MARK: - BLE UUIDs
    
    private let serviceUuid = CBUUID(string: "FFE0")
    private let waypointCharUuid = CBUUID(string: "FFE1")
    private let statusCharUuid = CBUUID(string: "FFE2")
    private let commandCharUuid = CBUUID(string: "FFE3")
    private let calibrationCharUuid = CBUUID(string: "FFE4")
    
    // MARK: - BLE Objects
    
    private var centralManager: CBCentralManager!
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
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: [serviceUuid], options: nil)
    }
    
    func stopScanning() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }
    
    func disconnect() {
        shouldReconnect = false
        reconnectTimer?.invalidate()
        
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
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
            self?.startScanning()
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
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
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
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        let name = peripheral.name ?? "Unknown"
        guard name == "Helm" else { return }
        
        centralManager.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        
        connectionState = .connecting
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        shouldReconnect = true
        peripheral.discoverServices([serviceUuid])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        lastError = error?.localizedDescription ?? "Connection failed"
        clearCharacteristics()
        scheduleReconnect()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        clearCharacteristics()
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUuid }) else { return }
        
        peripheral.discoverCharacteristics([
            waypointCharUuid,
            statusCharUuid,
            commandCharUuid,
            calibrationCharUuid
        ], for: service)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            switch char.uuid {
            case waypointCharUuid:
                waypointChar = char
            case statusCharUuid:
                statusChar = char
                peripheral.setNotifyValue(true, for: char)
            case commandCharUuid:
                commandChar = char
            case calibrationCharUuid:
                calibrationChar = char
                peripheral.setNotifyValue(true, for: char)
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        switch characteristic.uuid {
        case statusCharUuid:
            parseStatus(data)
        case calibrationCharUuid:
            parseResponse(data)
        default:
            break
        }
    }
    
    private func parseStatus(_ data: Data) {
        do {
            let status = try JSONDecoder().decode(DeviceStatus.self, from: data)
            DispatchQueue.main.async {
                self.deviceStatus = status
            }
        } catch {
            print("Status parse error: \(error)")
        }
    }
    
    private func parseResponse(_ data: Data) {
        do {
            let response = try JSONDecoder().decode(BleResponse.self, from: data)
            DispatchQueue.main.async {
                self.lastResponse = response
                if let error = response.error {
                    self.lastError = error
                }
            }
        } catch {
            print("Response parse error: \(error)")
        }
    }
}