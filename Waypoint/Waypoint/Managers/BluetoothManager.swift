import Foundation
import CoreBluetooth
import Combine

// Non-isolated UUID constants for thread-safe access
private let serviceUUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
private let waypointCharacteristicUUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")
private let statusCharacteristicUUID = CBUUID(string: "19B10002-E8F2-537E-4F6C-D104768A1214")
private let commandCharacteristicUUID = CBUUID(string: "19B10003-E8F2-537E-4F6C-D104768A1214")

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var deviceStatus: DeviceStatus?
    @Published var isScanning: Bool = false
    
    private var centralManager: CBCentralManager!
    private var helmPeripheral: CBPeripheral?
    private var cancellables = Set<AnyCancellable>()
    
    private var waypointCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var commandCharacteristic: CBCharacteristic?
    
    // Combine publishers for reactive data streams
    private let connectionStateSubject = PassthroughSubject<Bool, Never>()
    private let deviceStatusSubject = PassthroughSubject<DeviceStatus, Never>()
    private let scanningStateSubject = PassthroughSubject<Bool, Never>()
    private let logger = AppLogger.shared
    
    // Public publishers for external consumption
    var connectionStatePublisher: AnyPublisher<Bool, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    
    var deviceStatusPublisher: AnyPublisher<DeviceStatus, Never> {
        deviceStatusSubject
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
    
    var scanningStatePublisher: AnyPublisher<Bool, Never> {
        scanningStateSubject.eraseToAnyPublisher()
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupReactiveDataPipeline()
        logger.info("BluetoothManager initialized", category: .bluetooth)
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func setupReactiveDataPipeline() {
        // Automatic reconnection using Combine Timer publisher
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .filter { [weak self] _ in
                guard let self = self else { return false }
                return !self.isConnected && self.centralManager.state == .poweredOn
            }
            .sink { [weak self] _ in
                self?.startScanning()
            }
            .store(in: &cancellables)
        
        // Reactive connection state updates
        connectionStateSubject
            .removeDuplicates()
            .sink { [weak self] isConnected in
                self?.isConnected = isConnected
            }
            .store(in: &cancellables)
        
        // Debounced device status updates
        deviceStatusSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates { previous, current in
                // Compare key properties to avoid unnecessary updates
                previous.hasGpsFix == current.hasGpsFix &&
                previous.satellites == current.satellites &&
                abs(previous.distance - current.distance) < 1.0
            }
            .sink { [weak self] status in
                self?.deviceStatus = status
            }
            .store(in: &cancellables)
        
        // Scanning state reactive updates
        scanningStateSubject
            .removeDuplicates()
            .sink { [weak self] isScanning in
                self?.isScanning = isScanning
            }
            .store(in: &cancellables)
        
        // Automatic scanning timeout using Combine
        scanningStateSubject
            .filter { $0 } // Only when scanning starts
            .flatMap { _ in
                Timer.publish(every: 10.0, on: .main, in: .common)
                    .autoconnect()
                    .prefix(1)
            }
            .sink { [weak self] _ in
                if self?.isScanning == true && !(self?.isConnected ?? false) {
                    self?.stopScanning()
                    print("Scanning timeout - will retry automatically")
                }
            }
            .store(in: &cancellables)
        
        // Connection health monitoring
        connectionStateSubject
            .filter { $0 } // Only when connected
            .flatMap { _ in
                Timer.publish(every: 30.0, on: .main, in: .common)
                    .autoconnect()
            }
            .sink { [weak self] _ in
                self?.checkConnectionHealth()
            }
            .store(in: &cancellables)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn, !isScanning else { return }
        
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanningStateSubject.send(true)
        logger.info("Started scanning for Helm devices", category: .bluetooth)
    }
    
    func stopScanning() {
        centralManager.stopScan()
        scanningStateSubject.send(false)
    }
    
    func connect(peripheral: CBPeripheral) {
        helmPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral)
    }
    
    func disconnect() {
        if let peripheral = helmPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func sendWaypoint(latitude: Double, longitude: Double) {
        guard let characteristic = waypointCharacteristic else { 
            print("Waypoint characteristic not available")
            return 
        }
        
        let waypointData = String(format: "$GPS,%.6f,%.6f,0.0*", latitude, longitude)
        let data = waypointData.data(using: .utf8)!
        
        helmPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
        logger.waypointSent("GPS Waypoint", coordinate: String(format: "%.6f, %.6f", latitude, longitude))
    }
    
    func enableNavigation() {
        sendCommand("NAV_ENABLE")
    }
    
    func disableNavigation() {
        sendCommand("NAV_DISABLE")
    }
    
    private func sendCommand(_ command: String) {
        guard let characteristic = commandCharacteristic else {
            print("Command characteristic not available")
            return
        }
        
        guard let data = command.data(using: .utf8) else {
            print("Failed to encode command: \(command)")
            return
        }
        
        helmPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
        logger.info("Sent command to device: \(command)", category: .bluetooth)
    }
    
    private func checkConnectionHealth() {
        guard isConnected, let peripheral = helmPeripheral else { return }
        
        // Check if peripheral is still connected
        if peripheral.state != .connected {
            logger.warning("Connection health check failed - peripheral disconnected", category: .bluetooth)
            connectionStateSubject.send(false)
        }
    }
    
    private func parseDeviceStatus(from data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let status = try decoder.decode(DeviceStatus.self, from: jsonData)
            deviceStatusSubject.send(status)
        } catch {
            logger.error("Failed to parse device status", error: error, category: .bluetooth)
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
            case .poweredOff, .resetting, .unauthorized, .unknown, .unsupported:
                connectionStateSubject.send(false)
                scanningStateSubject.send(false)
                helmPeripheral = nil
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            if peripheral.name?.contains("Helm") == true {
                stopScanning()
                connect(peripheral: peripheral)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionStateSubject.send(true)
            logger.bluetoothConnected(peripheral.name ?? "Unknown Device")
        }
        peripheral.discoverServices([serviceUUID])
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionStateSubject.send(false)
            waypointCharacteristic = nil
            statusCharacteristic = nil
            commandCharacteristic = nil
            helmPeripheral = nil
            logger.bluetoothDisconnected(peripheral.name ?? "Unknown Device", error: error)
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionStateSubject.send(false)
            helmPeripheral = nil
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([waypointCharacteristicUUID, statusCharacteristicUUID, commandCharacteristicUUID], for: service)
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        Task { @MainActor in
            for characteristic in characteristics {
                switch characteristic.uuid {
                case waypointCharacteristicUUID:
                    waypointCharacteristic = characteristic
                case statusCharacteristicUUID:
                    statusCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                case commandCharacteristicUUID:
                    commandCharacteristic = characteristic
                default:
                    break
                }
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == statusCharacteristicUUID {
            Task { @MainActor in
                parseDeviceStatus(from: data)
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Failed to write to characteristic: \(error)")
        } else {
            print("Successfully wrote to characteristic: \(characteristic.uuid)")
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Failed to enable notifications: \(error)")
        }
    }
}