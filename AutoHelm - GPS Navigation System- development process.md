# AutoHelm Incremental Development Process

## Development Philosophy

Build the minimum viable product (MVP) through incremental, testable phases. Each phase produces a working, demonstrable feature before adding complexity. Focus on core functionality that enables autonomous GPS-guided navigation.

**MVP Definition:** The simplest system that can receive a waypoint via BLE, calculate navigation, and transmit RF commands to the trolling motor.

**Guiding Principles:**
- Deliver 20% of functionality that addresses 80% of the navigation problem
- Test each hardware component independently before integration
- Each phase must produce a working, testable outcome
- Avoid feature creep—defer non-essential features to future iterations
- Fail fast—identify technical risks early through rapid prototyping

---

## Git Workflow

### Branch Strategy

- `main` — Production-ready code only
- `develop` — Integration branch for completed features
- `feature/phase-X-description` — Feature branches for each phase

### Branch Naming

- `feature/phase-1-esp32-cc1101-rf`
- `feature/phase-2-gps-compass`
- `feature/phase-3-navigation-logic`
- `feature/phase-4-ble-communication`
- `feature/phase-5-ios-app`
- `feature/phase-6-integration`

### Workflow Per Phase

- Create feature branch from `develop`
- Implement all steps within the phase
- Test thoroughly before pull request
- Squash commits on merge
- Delete feature branch after merge

---

## Phase 1: ESP32 + CC1101 RF Control

**Goal:** Transmit RF commands that control the Watersnake trolling motor.

**Why First:** RF transmission is the core differentiator. Validating motor control early confirms the fundamental capability works before investing in navigation logic.

### Step 1.1: ESP32 Project Setup

**Objective:** Establish development environment and serial debugging.

- Create PlatformIO or Arduino IDE project for ESP32
- Configure board settings (ESP32 Dev Module, 115200 baud)
- Implement serial output for debugging
- Create `DataModels.h` with pin configuration constants
- Verify serial communication works

**Test:** Serial monitor displays startup message.

---

### Step 1.2: CC1101 SPI Communication

**Objective:** Establish reliable SPI communication with CC1101 module.

- Implement CC1101 class with SPI initialization
- Configure SPI pins (CS=5, SCK=18, MISO=19, MOSI=23)
- Implement register read/write methods
- Add chip reset sequence
- Read and verify CC1101 version register (expect 0x14 or 0x04)

**Test:** Serial output confirms CC1101 version detected.

---

### Step 1.3: CC1101 RF Configuration

**Objective:** Configure CC1101 for 433.017 MHz 2-FSK transmission.

- Set frequency registers for 433.017 MHz (FREQ2=0x10, FREQ1=0xA7, FREQ0=0x6C)
- Configure 2-FSK modulation with async serial mode
- Set deviation to ~25 kHz (DEVIATN=0x40)
- Configure GDO0 as high-Z for RMT input
- Set maximum TX power via PATABLE
- Implement TX start/stop strobes

**Test:** RTL-SDR confirms signal at 433.017 MHz when transmitting.

---

### Step 1.4: Manchester Encoding with RMT

**Objective:** Generate precise Manchester-encoded RF signals.

- Configure ESP32 RMT peripheral for TX on GPIO 4
- Set RMT clock divider for 1µs resolution
- Implement Manchester encoding (52µs half-bit timing)
- Build RMT items from hex payload strings
- Add terminator item for clean signal end

**Test:** RTL-SDR with URH shows correct Manchester waveform timing.

---

### Step 1.5: Watersnake Button Transmission

**Objective:** Transmit complete Watersnake remote button codes.

- Define button payload constants (preamble + sync + device ID + command)
- Implement single burst transmission method
- Implement hold transmission with 68ms repeat interval
- Add release code transmission
- Create serial command interface for testing (R/L/U/D/M keys)

**Test:** Trolling motor responds to transmitted commands.

---

## Phase 2: GPS + Compass Integration

**Goal:** Acquire accurate position and heading data for navigation calculations.

**Why Second:** Navigation requires reliable sensor data. GPS and compass must work independently before combining with navigation logic.

### Step 2.1: GPS Module Communication

**Objective:** Receive and parse NMEA data from GPS module.

- Configure UART2 for GPS communication (RX=16, TX=17, 9600 baud)
- Implement GPS data structure (lat, lon, altitude, satellites, fix status, DOP)
- Parse GGA sentences for position and fix quality
- Parse RMC sentences for date/time
- Parse GSA sentences for DOP values
- Handle partial sentences and buffer management

**Test:** Serial output shows parsed GPS coordinates when outdoors with fix.

---

### Step 2.2: Magnetometer Integration

**Objective:** Read compass heading from MMC5603 magnetometer.

- Initialize I2C communication (SDA=21, SCL=22)
- Verify magnetometer at address 0x30
- Read raw X, Y, Z magnetic field values
- Calculate heading from X/Y values using atan2
- Implement heading normalization (0-360 degrees)
- Store calibration offset structure for future use

**Test:** Serial output shows heading that changes when device rotated.

---

### Step 2.3: Sensor Data Validation

**Objective:** Ensure sensor data meets navigation requirements.

- Implement GPS fix quality checks (minimum 4 satellites, DOP < 5.0)
- Add GPS data age tracking (reject stale data)
- Implement heading smoothing to reduce noise
- Create combined sensor status reporting
- Add sensor initialization failure handling

**Test:** Serial reports valid/invalid sensor states correctly.

---

## Phase 3: Navigation Logic

**Goal:** Calculate bearing and distance to waypoint, determine course corrections.

**Why Third:** Core navigation algorithms must work correctly before adding wireless control. Test with hardcoded waypoints via serial.

### Step 3.1: Navigation Calculations

**Objective:** Implement accurate distance and bearing formulas.

- Implement Haversine distance calculation
- Implement bearing calculation between two coordinates
- Implement angle normalization (-180 to +180)
- Calculate relative angle between current heading and target bearing
- Unit test with known coordinate pairs

**Test:** Calculated distances match online GPS calculators.

---

### Step 3.2: Navigation State Machine

**Objective:** Manage navigation modes and waypoint targeting.

- Define navigation states (IDLE, NAVIGATING, ARRIVED)
- Implement waypoint target storage
- Calculate navigation data on each GPS update
- Implement arrival detection (within 5 meters of target)
- Track navigation enable/disable state

**Test:** Serial commands set waypoint, state transitions work correctly.

---

### Step 3.3: Heading Correction Logic

**Objective:** Determine when and which RF commands to send.

- Define heading tolerance threshold (15 degrees)
- Implement minimum correction interval (2 seconds)
- Determine left/right correction based on relative angle
- Integrate RF transmission with correction decisions
- Prevent over-correction with timing guards

**Test:** Device transmits correct L/R commands based on simulated heading errors.

---

## Phase 4: BLE Communication

**Goal:** Enable iOS app to send waypoints and receive status via Bluetooth.

**Why Fourth:** Wireless control replaces serial testing interface. BLE must work before building iOS app.

### Step 4.1: BLE Service Setup

**Objective:** Advertise as "Helm" with custom GATT service.

- Initialize ESP32 BLE stack
- Create custom service (UUID: FFE0)
- Configure device name as "Helm"
- Implement server callbacks for connect/disconnect
- Start advertising with service UUID
- Auto-restart advertising on disconnect

**Test:** Device appears as "Helm" in iOS Bluetooth settings and generic BLE scanner apps.

---

### Step 4.2: BLE Characteristics

**Objective:** Define read/write/notify characteristics for data exchange.

- Create waypoint characteristic (FFE1, Write) for receiving coordinates
- Create status characteristic (FFE2, Notify) for streaming device status
- Create command characteristic (FFE3, Write) for control commands
- Create calibration characteristic (FFE4, Notify) for calibration data
- Add BLE2902 descriptors for notify characteristics

**Test:** nRF Connect app can discover and interact with all characteristics.

---

### Step 4.3: Waypoint Reception

**Objective:** Parse incoming waypoint data and set navigation target.

- Define waypoint protocol format ($GPS,lat,lon,alt*)
- Parse received characteristic data
- Validate coordinate ranges
- Set navigation manager target on valid waypoint
- Send acknowledgment response

**Test:** Send waypoint string via nRF Connect, device sets navigation target.

---

### Step 4.4: Status Broadcasting

**Objective:** Stream navigation status to connected iOS device.

- Define JSON status format (fix, satellites, position, heading, distance, bearing, DOP)
- Build status JSON from current sensor and navigation data
- Transmit via notify characteristic at 1-2 Hz when connected
- Handle notification congestion gracefully
- Include target waypoint in status when navigating

**Test:** nRF Connect shows live JSON status updates.

---

### Step 4.5: Command Handling

**Objective:** Process control commands from iOS app.

- Implement NAV_ENABLE command with safety validation
- Implement NAV_DISABLE command for immediate stop
- Implement START_CAL / STOP_CAL for compass calibration
- Send command acknowledgment responses
- Validate GPS fix before enabling navigation

**Test:** Commands via nRF Connect control navigation state.

---

## Phase 5: iOS Companion App

**Goal:** Create minimal iOS app for waypoint creation and device control.

**Why Fifth:** Hardware functionality is complete. iOS app provides user interface for the working system.

### Step 5.1: Xcode Project Setup

**Objective:** Create iOS project with required permissions.

- Create new SwiftUI project "Waypoint"
- Set deployment target iOS 18.5+
- Add Bluetooth usage description to Info.plist
- Add location usage description to Info.plist
- Create folder structure (Models, Managers, Views)

**Test:** Project builds and runs on device.

---

### Step 5.2: Data Models

**Objective:** Define type-safe data structures.

- Create Waypoint struct (id, coordinate, name)
- Create DeviceStatus struct matching ESP32 JSON format
- Implement Codable conformance for JSON parsing
- Create CLLocationCoordinate2D extension for Codable

**Test:** JSON decoding works with sample status data.

---

### Step 5.3: Bluetooth Manager

**Objective:** Implement BLE central for device communication.

- Create BluetoothManager as ObservableObject
- Implement CBCentralManagerDelegate for scanning
- Implement CBPeripheralDelegate for characteristic access
- Scan for devices advertising FFE0 service
- Connect to discovered "Helm" device
- Discover and cache characteristic references
- Subscribe to notify characteristics
- Parse incoming status JSON updates
- Implement sendWaypoint method
- Implement sendCommand method
- Handle disconnection with auto-reconnect timer

**Test:** App connects to ESP32, receives status updates.

---

### Step 5.4: Location Manager

**Objective:** Access user location for map centering.

- Create LocationManager as ObservableObject
- Request when-in-use authorization
- Publish user location updates
- Handle authorization state changes

**Test:** App shows current location on map.

---

### Step 5.5: Map View

**Objective:** Display map with tap-to-create waypoints.

- Create MapView with MapKit
- Center on user location
- Display user location indicator
- Handle tap gesture to get coordinates
- Create waypoint annotation at tap location
- Display waypoint markers on map

**Test:** Tap map creates visible waypoint marker.

---

### Step 5.6: Helm Control View

**Objective:** Provide device status and navigation control.

- Display connection status indicator
- Show GPS fix status and satellite count
- Show current position and heading
- Display distance and bearing to target when navigating
- Add Navigation enable/disable toggle
- Add "Send Waypoint" button for selected waypoint
- Show loading state during command processing
- Display error alerts for failed commands

**Test:** Toggle navigation, send waypoint, observe device response.

---

## Phase 6: System Integration

**Goal:** Validate complete end-to-end navigation workflow.

**Why Last:** All components exist. Integration testing confirms they work together reliably.

### Step 6.1: End-to-End Navigation Test

**Objective:** Verify complete workflow from waypoint to motor command.

- Create waypoint in iOS app
- Send waypoint to ESP32 via BLE
- Verify ESP32 receives and parses waypoint
- Enable navigation via iOS app
- Verify status updates stream to iOS
- Confirm RF commands transmit for heading correction
- Test arrival detection when reaching waypoint

**Test:** Complete navigation cycle works without manual intervention.

---

### Step 6.2: Safety Validation

**Objective:** Confirm safety features prevent unsafe operation.

- Verify navigation cannot enable without GPS fix
- Verify navigation cannot enable without waypoint set
- Test navigation auto-disables on GPS fix loss
- Test navigation auto-disables on BLE disconnect
- Verify DOP threshold prevents navigation with poor GPS
- Confirm arrival auto-disables navigation

**Test:** All safety conditions enforced correctly.

---

### Step 6.3: Connection Reliability

**Objective:** Ensure robust BLE operation under real conditions.

- Test connection at various distances
- Force disconnect and verify auto-reconnect
- Test app backgrounding and foregrounding
- Verify status updates resume after reconnection
- Test multiple connect/disconnect cycles

**Test:** Connection remains stable during typical usage.

---

### Step 6.4: Field Testing

**Objective:** Validate navigation accuracy in real environment.

- Test with known waypoint locations
- Verify distance calculations match reality
- Confirm heading corrections turn motor correct direction
- Test arrival detection threshold accuracy
- Document any issues for future iteration

**Test:** System navigates to real-world targets successfully.

---

## Testing Checklist

### ESP32 Helm Device

- [ ] CC1101 detected and version confirmed
- [ ] RF signal visible on RTL-SDR at 433.017 MHz
- [ ] Manchester encoding timing correct (52µs half-bits)
- [ ] Trolling motor responds to RF commands
- [ ] GPS acquires fix outdoors
- [ ] Compass heading changes when rotated
- [ ] BLE advertises as "Helm"
- [ ] BLE characteristics accessible
- [ ] Waypoint reception works
- [ ] Status broadcasting works
- [ ] Navigation calculations accurate
- [ ] Heading corrections trigger RF commands
- [ ] Safety validations enforced

### iOS Waypoint App

- [ ] Bluetooth permission requested
- [ ] Location permission requested
- [ ] Map displays and is interactive
- [ ] User location shown on map
- [ ] Tap creates waypoint marker
- [ ] Connects to "Helm" device
- [ ] Status updates display correctly
- [ ] Send waypoint works
- [ ] Navigation toggle works
- [ ] Auto-reconnect works

### Integration

- [ ] Waypoint transmission end-to-end
- [ ] Status streaming continuous
- [ ] Navigation enables with valid GPS
- [ ] Navigation disables on safety triggers
- [ ] Motor responds to navigation corrections
- [ ] Arrival detection works

---

## Development Best Practices

### Hardware Development

- Test each peripheral independently before integration
- Use serial debugging extensively during development
- Implement graceful degradation for hardware failures
- Keep main loop non-blocking
- Use RMT peripheral for timing-critical RF operations
- Acquire PM locks when timing precision required

### iOS Development

- Use SwiftUI previews for rapid UI iteration
- Test on physical device early (BLE requires real hardware)
- Handle permission requests gracefully with clear messaging
- Use Combine/async-await for reactive data flow
- Test with nRF Connect before building custom app

### Integration

- Define clear data protocols before implementation
- Test BLE communication with generic tools first
- Log all data exchanges during development
- Handle connection state changes explicitly
- Validate received data before processing

### Version Control

- Commit after each working feature
- Write descriptive commit messages
- Tag releases with version numbers
- Keep main branch always deployable
- Review pull requests before merge