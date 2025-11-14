import Foundation
import CoreBluetooth
import Combine

// BLE Service and Characteristic UUIDs following README architecture exactly
private let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
private let waypointCharacteristicUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
private let statusCharacteristicUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")
private let commandCharacteristicUUID = CBUUID(string: "0000FFE3-0000-1000-8000-00805F9B34FB")
private let calibrationDataCharacteristicUUID = CBUUID(string: "0000FFE4-0000-1000-8000-00805F9B34FB")
private let configCharacteristicUUID = CBUUID(string: "0000FFE5-0000-1000-8000-00805F9B34FB")

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var deviceStatus: DeviceStatus?
    @Published var isScanning: Bool = false
    
    private var centralManager: CBCentralManager!
    private var helmPeripheral: CBPeripheral?
    private var cancellables = Set<AnyCancellable>()
    
    // All 5 characteristics per README architecture
    private var waypointCharacteristic: CBCharacteristic?      // FFE1 - Send GPS waypoints
    private var statusCharacteristic: CBCharacteristic?        // FFE2 - Receive status data
    private var commandCharacteristic: CBCharacteristic?       // FFE3 - Send commands
    private var calibrationDataCharacteristic: CBCharacteristic? // FFE4 - Receive calibration data
    private var configCharacteristic: CBCharacteristic?        // FFE5 - Device configuration
    
    // FIXED: Enhanced MTU Management with proper negotiation tracking
    private var negotiatedMTU: Int = 23
    private var effectivePayload: Int = 20
    private var isNegotiating: Bool = false
    private let headerSize: Int = 4 // Fragment header: seq(1) + total(1) + length_high(1) + length_low(1)
    
    // FIXED: Corrected Fragment Reassembly with proper buffer management
    private var fragmentBuffer = Data()
    private var expectedFragments: UInt8 = 0
    private var expectedTotalLength: UInt16 = 0
    private var receivedFragments: Set<UInt8> = []
    private var fragmentTimeout: Timer?
    private var currentMessageId: String?
    private var lastProcessedMessageHash: Int?
    
    // Combine publishers for reactive data streams
    private let connectionStateSubject = PassthroughSubject<Bool, Never>()
    private let deviceStatusSubject = PassthroughSubject<DeviceStatus, Never>()
    private let scanningStateSubject = PassthroughSubject<Bool, Never>()
    private let logger = AppLogger.shared
    
    // Public publishers following README reactive architecture
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
        fragmentTimeout?.invalidate()
        cancellables.removeAll()
    }
    
    private func setupReactiveDataPipeline() {
        // Auto-reconnection every 2 seconds per README
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
        
        // Debounced device status updates (300ms per README)
        deviceStatusSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates { previous, current in
                previous.hasGpsFix == current.hasGpsFix &&
                previous.satellites == current.satellites &&
                abs(previous.distance - current.distance) < 1.0
            }
            .sink { [weak self] status in
                self?.deviceStatus = status
            }
            .store(in: &cancellables)
        
        // Scanning state updates
        scanningStateSubject
            .removeDuplicates()
            .sink { [weak self] isScanning in
                self?.isScanning = isScanning
            }
            .store(in: &cancellables)
        
        // Scanning timeout (10 seconds per README)
        scanningStateSubject
            .filter { $0 }
            .flatMap { _ in
                Timer.publish(every: 10.0, on: .main, in: .common)
                    .autoconnect()
                    .prefix(1)
            }
            .sink { [weak self] _ in
                if self?.isScanning == true && !(self?.isConnected ?? false) {
                    self?.stopScanning()
                }
            }
            .store(in: &cancellables)
        
        // Connection health monitoring (30 second intervals per README)
        connectionStateSubject
            .filter { $0 }
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
        logger.debug("Scanning for Helm devices", category: .bluetooth)
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
    
    // MARK: - FIXED MTU Management per README specification
    
    private func requestHigherMTU() {
        guard let peripheral = helmPeripheral, !isNegotiating else { return }
        
        isNegotiating = true
        
        // Get actual write length for characteristic (this is the real payload capacity)
        let maxWriteLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        
        // MTU is write length + ATT overhead (3 bytes)
        let actualMTU = maxWriteLength + 3
        
        logger.debug("MTU negotiation: max write length \(maxWriteLength), calculated MTU \(actualMTU)", category: .bluetooth)
        
        updateEffectiveMTU(actualMTU)
        isNegotiating = false
    }
    
    private func updateEffectiveMTU(_ mtu: Int) {
        // Ensure minimum MTU compliance
        negotiatedMTU = max(mtu, 23)
        
        // Calculate effective payload: MTU - ATT overhead - fragment header
        let attOverhead = 3
        effectivePayload = max(negotiatedMTU - attOverhead - headerSize, 16) // Minimum 16 bytes payload
        
        logger.debug("MTU updated: negotiated=\(negotiatedMTU), effective payload=\(effectivePayload), header=\(headerSize)", category: .bluetooth)
    }
    
    // MARK: - FIXED Fragment Reassembly with Correct Buffer Management
    
    private func handleFragmentedData(_ data: Data) {
        // First check if this is a complete JSON message (no fragmentation)
        if data.count > 10, let jsonString = String(data: data, encoding: .utf8),
           jsonString.hasPrefix("{") && jsonString.hasSuffix("}") && isValidCompleteJSON(jsonString) {
            
            let messageHash = jsonString.hashValue
            if lastProcessedMessageHash == messageHash {
                logger.debug("Skipping duplicate complete message", category: .bluetooth)
                return
            }
            
            logger.debug("Complete JSON received (\(data.count) bytes)", category: .bluetooth)
            lastProcessedMessageHash = messageHash
            parseDeviceStatus(from: data)
            return
        }
        
        // FIXED: Validate minimum fragment size
        guard data.count >= headerSize else {
            logger.warning("Fragment too small (\(data.count) < \(headerSize)), discarding", category: .bluetooth)
            return
        }
        
        // FIXED: Parse fragment header with bounds checking
        let sequenceNum = data[0]
        let totalFragments = data[1]
        let totalLengthHigh = UInt16(data[2])
        let totalLengthLow = UInt16(data[3])
        let totalLength = (totalLengthHigh << 8) | totalLengthLow
        
        // FIXED: Validate fragment parameters
        guard sequenceNum < totalFragments else {
            logger.warning("Invalid fragment sequence: \(sequenceNum) >= \(totalFragments)", category: .bluetooth)
            return
        }
        
        guard totalLength > 0 && totalLength <= 4096 else { // Reasonable upper limit
            logger.warning("Invalid total length: \(totalLength)", category: .bluetooth)
            return
        }
        
        // Extract payload with bounds checking
        let payloadStart = headerSize
        guard payloadStart < data.count else {
            logger.warning("No payload in fragment", category: .bluetooth)
            return
        }
        
        let payload = data.subdata(in: payloadStart..<data.count)
        let messageId = "\(totalFragments)_\(totalLength)"
        
        logger.debug("Fragment \(sequenceNum + 1)/\(totalFragments) (\(payload.count) bytes payload)", category: .bluetooth)
        
        // Handle new fragmented message
        if sequenceNum == 0 || currentMessageId != messageId {
            resetFragmentBuffer()
            expectedFragments = totalFragments
            expectedTotalLength = totalLength
            currentMessageId = messageId
            
            // FIXED: Calculate correct buffer size based on fragment structure
            // Buffer size = total message length, NOT fragment count * payload size
            let bufferSize = Int(totalLength)
            fragmentBuffer = Data(count: bufferSize)
            
            logger.debug("Starting new fragmented message: \(totalFragments) fragments, \(totalLength) bytes total", category: .bluetooth)
            
            // Start timeout timer
            fragmentTimeout = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.handleFragmentTimeout()
                }
            }
        }
        
        // Check for duplicate fragment
        if receivedFragments.contains(sequenceNum) {
            logger.debug("Skipping duplicate fragment \(sequenceNum + 1)", category: .bluetooth)
            return
        }
        
        // Mark fragment as received
        receivedFragments.insert(sequenceNum)
        
        // FIXED: Calculate offset using actual payload capacity, not hardcoded values
        let fragmentPayloadCapacity = effectivePayload
        let offset = Int(sequenceNum) * fragmentPayloadCapacity
        let endOffset = offset + payload.count
        
        // FIXED: Comprehensive bounds validation before writing
        guard offset >= 0 && offset < fragmentBuffer.count else {
            logger.warning("Fragment \(sequenceNum + 1) offset \(offset) out of bounds [0..\(fragmentBuffer.count))", category: .bluetooth)
            resetFragmentBuffer()
            return
        }
        
        guard endOffset <= fragmentBuffer.count else {
            logger.warning("Fragment \(sequenceNum + 1) end offset \(endOffset) exceeds buffer size \(fragmentBuffer.count)", category: .bluetooth)
            resetFragmentBuffer()
            return
        }
        
        // Safe to write to buffer
        fragmentBuffer.replaceSubrange(offset..<endOffset, with: payload)
        logger.debug("Fragment \(sequenceNum + 1) written at offset \(offset)-\(endOffset-1)", category: .bluetooth)
        
        // Check if message is complete
        if receivedFragments.count >= expectedFragments {
            fragmentTimeout?.invalidate()
            
            // FIXED: Validate we have all required fragments
            let expectedSequences = Set(0..<expectedFragments)
            guard receivedFragments == expectedSequences else {
                let missing = expectedSequences.subtracting(receivedFragments).sorted()
                logger.warning("Missing fragments: \(missing), got: \(receivedFragments.sorted())", category: .bluetooth)
                resetFragmentBuffer()
                return
            }
            
            // FIXED: Use actual total length, not buffer size
            let finalData = fragmentBuffer.prefix(Int(expectedTotalLength))
            
            logger.info("Message reassembled successfully (\(finalData.count)/\(expectedTotalLength) bytes)", category: .bluetooth)
            
            // Duplicate detection for reassembled message
            if let jsonString = String(data: finalData, encoding: .utf8) {
                let messageHash = jsonString.hashValue
                if let lastHash = lastProcessedMessageHash, lastHash == messageHash {
                    logger.debug("Skipping duplicate reassembled message", category: .bluetooth)
                    resetFragmentBuffer()
                    return
                }
                lastProcessedMessageHash = messageHash
            }
            
            parseDeviceStatus(from: finalData)
            resetFragmentBuffer()
        }
    }
    
    private func resetFragmentBuffer() {
        fragmentBuffer = Data()
        expectedFragments = 0
        expectedTotalLength = 0
        currentMessageId = nil
        receivedFragments.removeAll()
        fragmentTimeout?.invalidate()
        fragmentTimeout = nil
        logger.debug("Fragment buffer reset", category: .bluetooth)
    }
    
    private func handleFragmentTimeout() {
        logger.warning("Fragment reassembly timeout - received \(receivedFragments.count)/\(expectedFragments) fragments", category: .bluetooth)
        resetFragmentBuffer()
    }
    
    private func isValidCompleteJSON(_ jsonString: String) -> Bool {
        guard !jsonString.isEmpty else { return false }
        guard jsonString.hasPrefix("{") && jsonString.hasSuffix("}") else { return false }
        
        var braceCount = 0
        var inString = false
        var escapeNext = false
        
        for char in jsonString {
            if escapeNext {
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                escapeNext = true
                continue
            }
            
            if char == "\"" {
                inString.toggle()
                continue
            }
            
            if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
            }
        }
        
        return braceCount == 0 && !inString
    }
    
    // MARK: - Public API following README specification
    
    func sendWaypoint(latitude: Double, longitude: Double) {
        guard let characteristic = waypointCharacteristic else {
            logger.warning("Waypoint characteristic not available", category: .bluetooth)
            return
        }
        
        // NMEA-like format per README: $GPS,lat,lon,alt*
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
    
    func startCalibration() {
        sendCommand("START_CAL")
    }
    
    func stopCalibration() {
        sendCommand("STOP_CAL")
    }
    
    private func sendCommand(_ command: String) {
        guard let characteristic = commandCharacteristic else {
            logger.warning("Command characteristic not available", category: .bluetooth)
            return
        }
        
        guard let data = command.data(using: .utf8) else {
            logger.error("Failed to encode command: \(command)", category: .bluetooth)
            return
        }
        
        helmPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
        logger.info("Command sent: \(command)", category: .bluetooth)
    }
    
    private func checkConnectionHealth() {
        guard isConnected, let peripheral = helmPeripheral else { return }
        
        if peripheral.state != .connected {
            logger.warning("Connection health check failed", category: .bluetooth)
            connectionStateSubject.send(false)
        }
    }
    
    private func cleanJSONString(_ jsonString: String) -> String {
        // Remove control characters
        let cleaned = jsonString.unicodeScalars.filter { scalar in
            return scalar.value >= 32 && scalar.value < 127
        }
        
        let cleanedString = String(String.UnicodeScalarView(cleaned))
        var correctedString = cleanedString
        
        // Fix corruption patterns per README
        correctedString = correctedString.replacingOccurrences(
            of: #""false\.[0-9]+""#,
            with: "false",
            options: .regularExpression
        )
        correctedString = correctedString.replacingOccurrences(
            of: #""true\.[0-9]+""#,
            with: "true",
            options: .regularExpression
        )
        correctedString = correctedString.replacingOccurrences(
            of: #""null\.[0-9]+""#,
            with: "null",
            options: .regularExpression
        )
        correctedString = correctedString.replacingOccurrences(
            of: #"([0-9]+)\.+([0-9]+)"#,
            with: "$1.$2",
            options: .regularExpression
        )
        
        // Extract JSON object
        guard let firstBrace = correctedString.firstIndex(of: "{"),
              let lastBrace = correctedString.lastIndex(of: "}") else {
            return correctedString
        }
        
        return String(correctedString[firstBrace...lastBrace])
    }
    
    private func parseDeviceStatus(from data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            logger.error("Failed to decode device status data", category: .bluetooth)
            return
        }
        
        let cleanedJsonString = cleanJSONString(jsonString)
        logger.debug("Device status received (\(cleanedJsonString.count) chars)", category: .bluetooth)
        
        guard isValidCompleteJSON(cleanedJsonString) else {
            logger.warning("Incomplete or invalid JSON received", category: .bluetooth)
            return
        }
        
        if let status = DeviceStatus.fromJSONString(cleanedJsonString) {
            deviceStatusSubject.send(status)
        } else {
            logger.error("Device status parsing failed", category: .bluetooth)
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
            // Look for device named "Helm" per README
            if peripheral.name?.contains("Helm") == true {
                stopScanning()
                connect(peripheral: peripheral)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionStateSubject.send(true)
            logger.bluetoothConnected(peripheral.name ?? "Helm")
        }
        peripheral.discoverServices([serviceUUID])
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionStateSubject.send(false)
            // Clear all characteristics
            waypointCharacteristic = nil
            statusCharacteristic = nil
            commandCharacteristic = nil
            calibrationDataCharacteristic = nil
            configCharacteristic = nil
            helmPeripheral = nil
            negotiatedMTU = 23
            effectivePayload = 20
            isNegotiating = false
            resetFragmentBuffer()
            logger.bluetoothDisconnected(peripheral.name ?? "Helm", error: error)
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
            // Discover all 5 characteristics per README architecture
            let characteristicUUIDs = [
                waypointCharacteristicUUID,
                statusCharacteristicUUID,
                commandCharacteristicUUID,
                calibrationDataCharacteristicUUID,
                configCharacteristicUUID
            ]
            peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
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
                case calibrationDataCharacteristicUUID:
                    calibrationDataCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                case configCharacteristicUUID:
                    configCharacteristic = characteristic
                default:
                    break
                }
            }
            
            // FIXED: Perform MTU negotiation after characteristics are discovered
            requestHigherMTU()
            logger.info("BLE characteristics configured, MTU negotiated", category: .bluetooth)
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        Task { @MainActor in
            if characteristic.uuid == statusCharacteristicUUID {
                // Handle status data with improved fragmentation support
                handleFragmentedData(data)
            } else if characteristic.uuid == calibrationDataCharacteristicUUID {
                // Handle calibration responses per README
                if let responseString = String(data: data, encoding: .utf8) {
                    logger.debug("Calibration response: \(responseString)", category: .bluetooth)
                }
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Write error: \(error)")
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Notification error: \(error)")
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        Task { @MainActor in
            logger.warning("BLE services invalidated, reconnecting", category: .bluetooth)
            disconnect()
        }
    }
}