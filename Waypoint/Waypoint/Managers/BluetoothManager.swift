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
    
    // MTU Management
    private var negotiatedMTU: Int = 23
    private var effectivePayload: Int = 20
    
    // Enhanced Fragment Reassembly
    private var fragmentBuffer = Data()
    private var expectedFragments: UInt8 = 0
    private var expectedTotalLength: UInt16 = 0
    private var receivedSequence: UInt8 = 0
    private var fragmentTimeout: Timer?
    private var currentMessageId: String? // Track current message being assembled
    private var lastProcessedMessage: String? // Track last processed complete message
    private var receivedFragments: Set<UInt8> = [] // Track which fragments we've received
    private var lastMessageHash: Int? // Hash-based duplicate detection
    private var fragmentReceptionTimes: [UInt8: Date] = [:] // Track fragment timing
    
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
        logger.info("BluetoothManager initialized with MTU negotiation support", category: .bluetooth)
    }
    
    deinit {
        fragmentTimeout?.invalidate()
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
            .filter { $0 }
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
    
    // MARK: - MTU Management
    
    private func requestHigherMTU() {
        guard let peripheral = helmPeripheral else { return }
        
        // Request maximum MTU immediately after connection
        // iOS supports up to 512 bytes, but practical limit is often ~185-247
        let requestedMTU = 512
        
        // Check the actual negotiated MTU using maximumWriteValueLength
        let maxWriteLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let actualMTU = maxWriteLength + 3 // Add ATT overhead back
        
        updateEffectiveMTU(actualMTU)
        
        logger.info("MTU negotiation - Requested: \(requestedMTU), Actual: \(actualMTU), Write Length: \(maxWriteLength)", category: .bluetooth)
    }
    
    private func updateEffectiveMTU(_ mtu: Int) {
        negotiatedMTU = max(mtu, 23) // Ensure minimum MTU
        effectivePayload = negotiatedMTU - 3 // Account for ATT overhead
        
        // Optimize fragmentation threshold based on actual MTU
        let fragmentThreshold = effectivePayload - 4 // Reserve space for fragment header
        
        logger.info("MTU optimized: \(negotiatedMTU) bytes, payload: \(effectivePayload) bytes, fragment threshold: \(fragmentThreshold) bytes", category: .bluetooth)
        
        // Test MTU with a small message to verify
        testMTUCapacity()
    }
    
    private func testMTUCapacity() {
        guard let peripheral = helmPeripheral,
              let characteristic = statusCharacteristic else { return }
        
        // Send a test message to verify actual MTU capacity
        let testMessage = String(repeating: "X", count: min(effectivePayload - 10, 100))
        let testData = testMessage.data(using: .utf8)!
        
        peripheral.writeValue(testData, for: characteristic, type: .withoutResponse)
        logger.debug("MTU capacity test: sent \(testData.count) bytes", category: .bluetooth)
    }
    
    // MARK: - Fragment Reassembly
    
    private func handleFragmentedData(_ data: Data) {
        // First check if this might be a complete JSON message
        if data.count > 10, let jsonString = String(data: data, encoding: .utf8),
           jsonString.hasPrefix("{") && jsonString.hasSuffix("}") && isValidCompleteJSON(jsonString) {
            // Hash-based duplicate detection for complete messages
            let messageHash = jsonString.hashValue
            if lastMessageHash == messageHash {
                logger.debug("Ignoring duplicate complete JSON message (hash match)", category: .bluetooth)
                return
            }
            // This appears to be a complete JSON, try parsing directly
            logger.debug("Received complete JSON message (\(data.count) bytes), parsing directly", category: .bluetooth)
            lastMessageHash = messageHash
            lastProcessedMessage = jsonString
            parseDeviceStatus(from: data)
            return
        }
        
        guard data.count >= 4 else {
            logger.warning("Received fragment too small for header", category: .bluetooth)
            return
        }
        
        let sequenceNum = data[0]
        let totalFragments = data[1]
        let totalLengthBytes = data.subdata(in: 2..<4)
        let totalLength = UInt16(totalLengthBytes[0]) << 8 | UInt16(totalLengthBytes[1])
        let payload = data.subdata(in: 4..<data.count)

        // Create unique message identifier
        let messageId = "\(totalFragments)_\(totalLength)"
        
        // Check for duplicate fragments
        if let currentId = currentMessageId, currentId == messageId {
            if receivedFragments.contains(sequenceNum) {
                logger.debug("Ignoring duplicate fragment \(sequenceNum + 1)/\(totalFragments)", category: .bluetooth)
                return
            }
        }

        // Check if we're already processing a different message
        if let currentId = currentMessageId, currentId != messageId {
            logger.warning("New message started before previous completed, resetting", category: .bluetooth)
            resetFragmentBuffer()
        }
        
        logger.debug("Received fragment \(sequenceNum + 1)/\(totalFragments), payload: \(payload.count) bytes", category: .bluetooth)
        
        // First fragment - initialize reassembly
        if sequenceNum == 0 {
            resetFragmentBuffer()
            expectedFragments = totalFragments
            expectedTotalLength = totalLength
            receivedSequence = 0
            currentMessageId = messageId
            receivedFragments = [0]
            fragmentReceptionTimes = [0: Date()]
            
            logger.debug("Starting new fragmented message: \(totalFragments) fragments, \(totalLength) bytes total", category: .bluetooth)
            
            // Start timeout timer for incomplete messages
            fragmentTimeout = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleFragmentTimeout()
                }
            }
        } else if currentMessageId != messageId {
            logger.warning("Fragment belongs to different message, ignoring", category: .bluetooth)
            return
        }
        
        // Mark fragment as received
        receivedFragments.insert(sequenceNum)
        fragmentReceptionTimes[sequenceNum] = Date()
        
        // Append payload to buffer at correct position (handle out-of-order fragments)
        let expectedOffset = Int(sequenceNum) * (effectivePayload - 4)
        if fragmentBuffer.count < expectedOffset + payload.count {
            fragmentBuffer.count = expectedOffset + payload.count
        }
        fragmentBuffer.replaceSubrange(expectedOffset..<(expectedOffset + payload.count), with: payload)
        
        logger.debug("Fragment \(sequenceNum + 1)/\(totalFragments) processed, buffer now \(fragmentBuffer.count) bytes", category: .bluetooth)
        
        // Check if message is complete (all fragments received)
        if receivedFragments.count >= expectedFragments {
            fragmentTimeout?.invalidate()
            
            // Validate that we have all sequence numbers
            let expectedSequences = Set(0..<expectedFragments)
            guard receivedFragments == expectedSequences else {
                logger.warning("Missing fragments: expected \(expectedSequences), got \(receivedFragments)", category: .bluetooth)
                resetFragmentBuffer()
                return
            }
            
            // Trim buffer to expected length
            if fragmentBuffer.count > expectedTotalLength {
                fragmentBuffer = fragmentBuffer.prefix(Int(expectedTotalLength))
            }
            
            logger.info("Successfully reassembled message from \(expectedFragments) fragments (\(fragmentBuffer.count) bytes)", category: .bluetooth)
            
            // Hash-based duplicate detection for reassembled messages
            if let jsonString = String(data: fragmentBuffer, encoding: .utf8) {
                let messageHash = jsonString.hashValue
                if lastMessageHash == messageHash {
                    logger.debug("Ignoring duplicate reassembled message (hash match)", category: .bluetooth)
                    resetFragmentBuffer()
                    return
                }
                lastMessageHash = messageHash
                lastProcessedMessage = jsonString
            }
            
            // Process complete message
            parseDeviceStatus(from: fragmentBuffer)
            resetFragmentBuffer()
        }
    }
    
    private func resetFragmentBuffer() {
        fragmentBuffer = Data()
        expectedFragments = 0
        expectedTotalLength = 0
        receivedSequence = 0
        currentMessageId = nil
        receivedFragments.removeAll()
        fragmentReceptionTimes.removeAll()
        fragmentTimeout?.invalidate()
        fragmentTimeout = nil
    }
    
    private func handleFragmentTimeout() async {
        logger.warning("Fragment reassembly timeout - discarding incomplete message", category: .bluetooth)
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
        
        if peripheral.state != .connected {
            logger.warning("Connection health check failed - peripheral disconnected", category: .bluetooth)
            connectionStateSubject.send(false)
        }
    }
    
    private func cleanJSONString(_ jsonString: String) -> String {
        // Remove control characters and non-printable characters
        let cleaned = jsonString.unicodeScalars.filter { scalar in
            // Keep printable ASCII characters and common JSON characters
            return scalar.value >= 32 && scalar.value < 127
        }
        
        let cleanedString = String(String.UnicodeScalarView(cleaned))
        
        // Fix common data corruption patterns
        var correctedString = cleanedString
        
        // Fix corrupted boolean values like "false.9" -> "false"
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
        
        // Fix corrupted null values like "null.0" -> "null"
        correctedString = correctedString.replacingOccurrences(
            of: #""null\.[0-9]+""#,
            with: "null",
            options: .regularExpression
        )
        
        // Fix corrupted numbers like "123..45" -> "123.45"
        correctedString = correctedString.replacingOccurrences(
            of: #"([0-9]+)\.+([0-9]+)"#,
            with: "$1.$2",
            options: .regularExpression
        )
        
        // Find the first { and last } to extract JSON object
        guard let firstBrace = correctedString.firstIndex(of: "{"),
              let lastBrace = correctedString.lastIndex(of: "}") else {
            return correctedString
        }
        
        return String(correctedString[firstBrace...lastBrace])
    }
    
    private func parseDeviceStatus(from data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            logger.error("Failed to decode device status data as UTF8", category: .bluetooth)
            return
        }
        
        // Clean the JSON string to remove control characters and corruption
        let cleanedJsonString = cleanJSONString(jsonString)
        logger.debug("Received device status JSON: \(cleanedJsonString)", category: .bluetooth)
        
        // Check if JSON is complete before parsing
        guard isValidCompleteJSON(cleanedJsonString) else {
            logger.warning("Received incomplete or malformed JSON, ignoring: \(cleanedJsonString.prefix(50))...", category: .bluetooth)
            return
        }
        
        if let status = DeviceStatus.fromJSONString(cleanedJsonString) {
            deviceStatusSubject.send(status)
        } else {
            logger.error("Device status parsing failed for JSON: \(cleanedJsonString)", category: .bluetooth)
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
            
            // iOS will auto-negotiate MTU during service discovery
            requestHigherMTU()
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
        negotiatedMTU = 23
        effectivePayload = 20
        resetFragmentBuffer()
        lastProcessedMessage = nil
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
                // Improved data handling logic
                if let dataString = String(data: data, encoding: .utf8), dataString.hasPrefix("{") {
                    // Looks like JSON - check if complete
                    if isValidCompleteJSON(dataString) {
                        logger.debug("Received complete JSON (\(data.count) bytes)", category: .bluetooth)
                        parseDeviceStatus(from: data)
                    } else {
                        logger.debug("Received incomplete JSON, treating as fragment", category: .bluetooth)
                        handleFragmentedData(data)
                    }
                } else if data.count >= 4 {
                    // Binary data with header - likely fragmented
                    logger.debug("Received binary data with header, treating as fragment", category: .bluetooth)
                    handleFragmentedData(data)
                } else {
                    logger.warning("Received unknown data format (\(data.count) bytes)", category: .bluetooth)
                }
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
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        Task { @MainActor in
            logger.warning("BLE services invalidated, reconnecting", category: .bluetooth)
            disconnect()
        }
    }
    
    // MARK: - MTU Update Handling
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateMTU mtu: Int, error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("MTU negotiation failed", error: error, category: .bluetooth)
                updateEffectiveMTU(23) // Fall back to default MTU
            } else {
                updateEffectiveMTU(mtu)
            }
        }
    }
}