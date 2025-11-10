import Foundation
import CoreBluetooth
import Combine

// Non-isolated UUID constants for thread-safe access
private let serviceUUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
private let waypointCharacteristicUUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")
private let statusCharacteristicUUID = CBUUID(string: "19B10002-E8F2-537E-4F6C-D104768A1214")

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var deviceStatus: DeviceStatus?
    @Published var isScanning: Bool = false
    
    private var centralManager: CBCentralManager!
    private var helmPeripheral: CBPeripheral?
    private var autoScanTimer: Timer?
    
    private var waypointCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        startAutoScanTimer()
    }
    
    deinit {
        autoScanTimer?.invalidate()
        autoScanTimer = nil
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn, !isScanning else { return }
        
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
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
        guard let characteristic = waypointCharacteristic else { return }
        
        let waypointData = String(format: "$GPS,%.6f,%.6f,0.0*", latitude, longitude)
        let data = waypointData.data(using: .utf8)!
        
        helmPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    private func startAutoScanTimer() {
        autoScanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.isConnected && self.centralManager.state == .poweredOn {
                    self.startScanning()
                }
            }
        }
    }
    
    private func stopAutoScanTimer() {
        autoScanTimer?.invalidate()
        autoScanTimer = nil
    }
    
    private func parseDeviceStatus(from data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let status = try decoder.decode(DeviceStatus.self, from: jsonData)
            self.deviceStatus = status
        } catch {
            print("Failed to parse device status: \(error)")
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
                isConnected = false
                isScanning = false
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
            isConnected = true
        }
        peripheral.discoverServices([serviceUUID])
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isConnected = false
            waypointCharacteristic = nil
            statusCharacteristic = nil
            helmPeripheral = nil
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isConnected = false
            helmPeripheral = nil
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([waypointCharacteristicUUID, statusCharacteristicUUID], for: service)
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
            print("Failed to write waypoint: \(error)")
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Failed to enable notifications: \(error)")
        }
    }
}