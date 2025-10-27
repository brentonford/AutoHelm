import SwiftUI
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var signalStrength: Int = 0
    @Published var connectionStatus: String = "Disconnected"
    @Published var arduinoStatus: ArduinoNavigationStatus? = nil
    @Published var magnetometerData: MagnetometerData? = nil
    @Published var isCalibrating: Bool = false
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var gpsCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var calibrationCommandCharacteristic: CBCharacteristic?
    private var calibrationDataCharacteristic: CBCharacteristic?
    
    private let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    private let characteristicUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    private let statusCharacteristicUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")
    private let calibrationCommandUUID = CBUUID(string: "0000FFE3-0000-1000-8000-00805F9B34FB")
    private let calibrationDataUUID = CBUUID(string: "0000FFE4-0000-1000-8000-00805F9B34FB")
    
    private var autoScanTimer: Timer?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        startAutoScanTimer()
    }
    
    private func startAutoScanTimer() {
        autoScanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isConnected && self.centralManager.state == .poweredOn {
                self.startScanning()
            }
        }
    }
    
    deinit {
        autoScanTimer?.invalidate()
    }
    
    func startScanning() {
        if centralManager.state == .poweredOn {
            print("Starting BLE scan for service UUID: \(serviceUUID)")
            discoveredDevices.removeAll()
            
            // Enhanced scanning options for better discovery
            let scanOptions: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [serviceUUID]
            ]
            
            // Scan for both the specific service and all devices
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: scanOptions)
            
            // Also scan without service filter as backup
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if let self = self, self.discoveredDevices.isEmpty {
                    print("No devices found with service filter, trying broader scan...")
                    self.centralManager.scanForPeripherals(withServices: nil, options: scanOptions)
                }
            }
            
            connectionStatus = "Scanning..."
        } else {
            print("Bluetooth not powered on, state: \(centralManager.state.rawValue)")
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        connectionStatus = "Scan stopped"
    }
    
    func connect(to peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
        connectionStatus = "Connecting..."
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func sendWaypoint(latitude: Double, longitude: Double) {
        guard let characteristic = gpsCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let dataString = String(format: "$GPS,%.6f,%.6f,0.00*\n", latitude, longitude)
        if let data = dataString.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
    
    func startCalibration() {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = "START_CAL"
        if let data = command.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            isCalibrating = true
        }
    }
    
    func stopCalibration() {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = "STOP_CAL"
        if let data = command.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            isCalibrating = false
        }
    }
    
    func saveCalibration(_ data: MagnetometerData) {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = String(format: "SAVE_CAL:%.2f,%.2f,%.2f,%.2f,%.2f,%.2f", 
                            data.maxX, data.maxY, data.maxZ, data.minX, data.minY, data.minZ)
        if let commandData = command.data(using: .utf8) {
            peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
            isCalibrating = false
        }
    }
    
    func setNavigationEnabled(_ enabled: Bool) {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = enabled ? "NAV_ENABLE" : "NAV_DISABLE"
        if let commandData = command.data(using: .utf8) {
            peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
        }
    }
    
    func startRFRemotePairing() {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = "RF_PAIR_START"
        if let commandData = command.data(using: .utf8) {
            peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
        }
    }
    
    func completeRFRemotePairing() {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = "RF_PAIR_COMPLETE"
        if let commandData = command.data(using: .utf8) {
            peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
        }
    }
    
    func cancelRFRemotePairing() {
        guard let characteristic = calibrationCommandCharacteristic, let peripheral = connectedPeripheral else {
            return
        }
        
        let command = "RF_PAIR_CANCEL"
        if let commandData = command.data(using: .utf8) {
            peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Bluetooth state changed to: \(central.state.rawValue)")
        
        switch central.state {
        case .poweredOn:
            connectionStatus = "Ready"
            print("Bluetooth is ready - starting auto scan")
            // Auto-start scanning when Bluetooth becomes available
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startScanning()
            }
        case .poweredOff:
            connectionStatus = "Bluetooth Off"
            print("Bluetooth is turned off")
        case .unauthorized:
            connectionStatus = "Unauthorized"
            print("Bluetooth access unauthorized")
        case .unsupported:
            connectionStatus = "Unsupported"
            print("Bluetooth not supported on this device")
        case .unknown:
            connectionStatus = "Unknown"
            print("Bluetooth state unknown")
        case .resetting:
            connectionStatus = "Resetting"
            print("Bluetooth is resetting")
        @unknown default:
            connectionStatus = "Unknown State"
            print("Unknown Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered device: \(peripheral.name ?? "Unknown") - \(peripheral.identifier)")
        print("RSSI: \(RSSI) dBm")
        print("Advertisement data: \(advertisementData)")
        
        // Check if this is our target device
        let isTargetDevice = peripheral.name?.contains("Helm") == true ||
                            advertisementData[CBAdvertisementDataLocalNameKey] as? String == "Helm" ||
                            advertisementData[CBAdvertisementDataServiceUUIDsKey] != nil
        
        if isTargetDevice {
            print("Found potential Helm device!")
        }
        
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
            print("Added device to discovery list")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStatus = "Connected"
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        centralManager.stopScan()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionStatus = "Disconnected"
        gpsCharacteristic = nil
        statusCharacteristic = nil
        calibrationCommandCharacteristic = nil
        calibrationDataCharacteristic = nil
        arduinoStatus = nil
        magnetometerData = nil
        isCalibrating = false
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Connection Failed"
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            return
        }
        
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID, statusCharacteristicUUID, calibrationCommandUUID, calibrationDataUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            return
        }
        
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                gpsCharacteristic = characteristic
            } else if characteristic.uuid == statusCharacteristicUUID {
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == calibrationCommandUUID {
                calibrationCommandCharacteristic = characteristic
            } else if characteristic.uuid == calibrationDataUUID {
                calibrationDataCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        signalStrength = RSSI.intValue
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == statusCharacteristicUUID {
            guard let data = characteristic.value,
                  let jsonString = String(data: data, encoding: .utf8) else {
                return
            }
            
            if let statusData = jsonString.data(using: .utf8) {
                do {
                    let status = try JSONDecoder().decode(ArduinoNavigationStatus.self, from: statusData)
                    DispatchQueue.main.async {
                        self.arduinoStatus = status
                    }
                } catch {
                    print("Failed to decode Arduino status: \(error)")
                }
            }
        } else if characteristic.uuid == calibrationDataUUID {
            guard let data = characteristic.value,
                  let jsonString = String(data: data, encoding: .utf8) else {
                return
            }
            
            if let calibrationData = jsonString.data(using: .utf8) {
                do {
                    let magData = try JSONDecoder().decode(MagnetometerData.self, from: calibrationData)
                    DispatchQueue.main.async {
                        self.magnetometerData = magData
                    }
                } catch {
                    print("Failed to decode magnetometer data: \(error)")
                }
            }
        }
    }
}
