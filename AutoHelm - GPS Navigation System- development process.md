# AutoHelm Incremental Development Process

## Development Philosophy

Build and test each component independently before integration. Each step produces a working, testable feature. Each phase is developed in its own feature branch with pull request review before merging.

**Context:** This approach ensures system reliability through isolated component testing and prevents integration failures that could compromise navigation safety. Each working feature provides immediate value and can be validated independently before adding complexity.

---

## Git Workflow

### Branch Strategy
- `main` - Production-ready code only
- `feature/phase-X-description` - Feature branches for each phase
- All development happens in feature branches
- Pull requests required for all merges to main
- Branches deleted after successful merge
- Commits squashed on merge to maintain clean history

### Branch Naming Convention
```
feature/phase-1-arduino-core
feature/phase-2-navigation-logic
feature/phase-3-audio-feedback
feature/phase-4-bluetooth-comm
feature/phase-5-rf-control
feature/phase-6-ios-foundation
feature/phase-7-advanced-ios
feature/phase-8-calibration
feature/phase-9-polish-testing
```

### Workflow Per Phase
1. Create feature branch from main
2. Implement all steps within the phase
3. Test thoroughly on feature branch
4. Create pull request with detailed description
5. Review and approve pull request
6. Merge with squash commits
7. Delete feature branch
8. Move to next phase

---

## Phase 1: Arduino Core Infrastructure

**Branch:** `feature/phase-1-arduino-core`

**Phase Context:** Establishing the fundamental hardware communication layer is critical because navigation accuracy depends on reliable GPS data acquisition, visual feedback through the display, and compass readings. Without these core systems working independently, subsequent navigation logic cannot be trusted. Each component must gracefully handle initialization failures to ensure the system remains operational even with partial hardware availability.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-1-arduino-core
```

### Step 1.1: Serial Communication & Basic Structure

**Goal:** Establish a reliable development and debugging foundation with consistent system startup behavior that enables real-time monitoring of all subsequent hardware initialization and operational states.

**Context:** Serial communication is the primary debugging interface for embedded navigation systems. Without reliable serial output, diagnosing GPS acquisition issues, compass calibration problems, or navigation calculation errors becomes nearly impossible. This foundation enables developers to monitor system health and troubleshoot issues in real-time during field testing.

**Implementation:**
1. Create `Helm.ino` with minimal setup/loop
2. Initialize Serial at 115200 baud
3. Create `DataModels.h` with `SystemConfig` constants class
4. Test serial output with diagnostic messages

**Testing:**
```cpp
// Serial Monitor should show:
// "=== Helm System Starting ==="
```

**Commit:** "feat: initialize project structure and serial communication"

---

### Step 1.2: OLED Display Initialization

**Goal:** Establish immediate visual feedback capability with graceful degradation to ensure users can monitor system status even when the display hardware fails, providing confidence that the navigation system is operational.

**Context:** Visual feedback is crucial for autonomous navigation systems because users need to verify GPS acquisition, monitor satellite count, and confirm navigation status without relying on external devices. The display serves as the primary user interface during field operation where serial monitoring isn't available. Graceful degradation ensures the system continues to function for navigation even if display hardware fails.

**Files Created:**
- `DisplayManager.h` - Class declaration
- `DisplayManager.cpp` - Implementation

**Implementation:**
```cpp
class DisplayManager {
private:
    Adafruit_SSD1306 display;
    bool initialized;
    
public:
    DisplayManager();
    bool begin();
    void showStartupScreen();
    void showStatus(const char* message);
};
```

**Key Methods:**
- `begin()` - Initialize I2C display at 0x3C
- `showStartupScreen()` - Display "Helm System Starting..."
- Implement graceful degradation if display unavailable

**Testing:**
- Display shows "Helm System Starting..." on boot
- Serial confirms initialization success/failure

**Commit:** "feat: implement OLED display manager with startup screen"

---

### Step 1.3: GPS Module Communication

**Goal:** Achieve reliable position fix acquisition and NMEA parsing to provide accurate real-time location data that forms the foundation for all navigation calculations and waypoint guidance.

**Context:** GPS accuracy directly impacts navigation safety and effectiveness. The system must reliably parse NMEA sentences to extract position, satellite count, and fix quality. Poor GPS implementation leads to navigation errors that could result in missed waypoints or incorrect course corrections. Real-time position data is essential for calculating accurate bearing and distance to targets.

**Files Created:**
- `GPSManager.h` - GPS interface class
- `GPSManager.cpp` - NMEA parsing logic
- Update `DataModels.h` with `GPSData` struct

**Implementation:**
```cpp
struct GPSData {
    float latitude;
    float longitude;
    float altitude;
    int satellites;
    bool hasFix;
    unsigned long timestamp;
};

class GPSManager {
private:
    SoftwareSerial gpsSerial;
    GPSData currentData;
    
    void parseNMEA(const char* sentence);
    void parseGGA(const char* data);
    void parseRMC(const char* data);
    
public:
    GPSManager(int rxPin, int txPin);
    bool begin();
    void update();
    GPSData getData() const;
};
```

**Testing:**
- Serial output shows parsed GPS sentences
- Display shows satellite count
- Display shows coordinates when fix achieved

**Commit:** "feat: implement GPS manager with NMEA parsing"

---

### Step 1.4: Display GPS Data

**Goal:** Provide real-time visual confirmation of GPS performance and position data to enable users to assess navigation system readiness and monitor GPS signal quality during operation.

**Context:** Users need immediate visual feedback about GPS status to determine when the system is ready for navigation. Displaying satellite count helps assess signal quality, while showing coordinates confirms accurate position acquisition. This visual feedback is critical during system startup and helps users understand when GPS conditions are suitable for reliable navigation.

**Updates:**
- Extend `DisplayManager` with GPS display methods

**Implementation:**
```cpp
void updateGPSDisplay(const GPSData& data);
void drawCoordinates(float lat, float lon);
void drawSatelliteCount(int count);
```

**Layout:**
```
GPS: 8 sats
-32.940931
151.718029
Alt: 45.2m
```

**Testing:**
- Coordinates update in real-time
- Satellite count displays correctly
- Altitude shown when available

**Commit:** "feat: display real-time GPS data on OLED"

---

### Step 1.5: Magnetometer Integration

**Goal:** Establish accurate compass heading determination with calibration support to provide reliable directional reference for navigation calculations and course correction commands.

**Context:** Compass accuracy is fundamental to navigation effectiveness. Magnetic interference from electronics or metal objects can cause significant heading errors, leading to incorrect navigation directions. The magnetometer provides the heading reference needed to calculate relative bearing to waypoints and determine when course corrections are required. Proper calibration procedures are essential for maintaining navigation accuracy in different magnetic environments.

**Files Created:**
- `CompassManager.h` - Magnetometer interface
- `CompassManager.cpp` - Heading calculation

**Implementation:**
```cpp
struct CompassCalibration {
    float minX, minY, minZ;
    float maxX, maxY, maxZ;
    float offsetX, offsetY, offsetZ;
};

class CompassManager {
private:
    Adafruit_MMC5603 mmc;
    CompassCalibration calibration;
    bool initialized;
    
    float calculateHeading(float x, float y, float z);
    void applyCalibration(float& x, float& y, float& z);
    
public:
    bool begin();
    float readHeading();
    CompassCalibration getCalibration() const;
    void setCalibration(const CompassCalibration& cal);
};
```

**Testing:**
- Serial output shows raw magnetometer values
- Display shows compass heading in degrees
- Rotate device and verify heading changes

**Commit:** "feat: implement magnetometer with heading calculation"

---

**Phase 1 Completion:**
```bash
git push origin feature/phase-1-arduino-core
# Create pull request: "Phase 1: Arduino Core Infrastructure"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-1-arduino-core
```

---

## Phase 2: Navigation Logic

**Branch:** `feature/phase-2-navigation-logic`

**Phase Context:** Navigation calculations are the core intelligence of the autonomous guidance system. Accurate distance and bearing calculations using proven mathematical formulas ensure the system provides correct directional guidance. The visual navigation arrow gives users immediate understanding of the required heading, while the navigation manager coordinates all guidance logic to provide consistent, reliable waypoint navigation.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-2-navigation-logic
```

### Step 2.1: Navigation Calculator

**Goal:** Implement proven mathematical algorithms for precise distance and bearing calculations that provide accurate navigation guidance regardless of geographic location or coordinate system variations.

**Context:** Navigation accuracy depends entirely on correct mathematical calculations. The Haversine formula provides accurate distance calculations across the Earth's curved surface, while bearing calculations determine the correct direction to travel. These calculations must account for coordinate system edge cases and provide consistent results across all geographic locations where the system might operate.

**Files Created:**
- `NavigationUtils.h` - Math utility functions
- `NavigationUtils.cpp` - Haversine and bearing calculations

**Implementation:**
```cpp
class NavigationUtils {
public:
    static float calculateDistance(float lat1, float lon1, float lat2, float lon2);
    static float calculateBearing(float lat1, float lon1, float lat2, float lon2);
    static float normalizeAngle(float angle);
    static float calculateRelativeAngle(float currentHeading, float targetBearing);
};
```

**Testing:**
- Unit test with known coordinate pairs
- Verify distance calculations match online tools
- Test bearing calculations in all quadrants

**Commit:** "feat: implement navigation calculation utilities"

---

### Step 2.2: Navigation Manager

**Goal:** Create a centralized navigation controller that manages waypoint targeting, tracks navigation state, and coordinates between GPS position updates and compass heading to provide consistent guidance logic.

**Context:** The navigation manager serves as the central coordination point for all navigation decisions. It must track navigation state, detect arrival at waypoints, and provide consistent guidance calculations. This centralization ensures that navigation logic remains consistent and can be easily modified or enhanced without affecting multiple system components.

**Files Created:**
- `NavigationManager.h` - Navigation controller
- `NavigationManager.cpp` - Core navigation logic

**Implementation:**
```cpp
enum class NavigationMode {
    IDLE,
    NAVIGATING,
    ARRIVED
};

struct NavigationState {
    NavigationMode mode;
    float targetLatitude;
    float targetLongitude;
    float distanceToTarget;
    float bearingToTarget;
    float relativeAngle;
};

class NavigationManager {
private:
    NavigationState state;
    bool navigationEnabled;
    unsigned long lastUpdateTime;
    
public:
    void setTarget(float latitude, float longitude);
    void update(const GPSData& gpsData, float heading);
    void setNavigationEnabled(bool enabled);
    NavigationState getState() const;
    bool hasArrived() const;
};
```

**Testing:**
- Set test waypoint via serial command
- Verify distance/bearing calculations
- Test arrival detection threshold

**Commit:** "feat: implement navigation manager with waypoint tracking"

---

### Step 2.3: Navigation Arrow Display

**Goal:** Provide intuitive visual direction indication through a dynamic arrow display that clearly shows the required heading adjustment to reach the target waypoint, updating in real-time as position and heading change.

**Context:** Visual navigation feedback is critical for user understanding and confidence in the system. The navigation arrow provides immediate, intuitive direction guidance that users can follow without interpreting numerical bearing data. Real-time updates ensure the arrow accurately reflects current navigation requirements as the user's position and heading change during travel.

**Updates:**
- Extend `DisplayManager` with arrow drawing

**Implementation:**
```cpp
void drawNavigationArrow(float relativeAngle);
void drawCompass(float heading);
void updateNavigationDisplay(const NavigationState& nav, float heading);
```

**Arrow Logic:**
- Calculate arrow rotation based on relative angle
- Draw arrow pointing toward target
- Update display at 5Hz minimum

**Testing:**
- Arrow points correct direction
- Rotates smoothly as heading changes
- Distance updates in real-time

**Commit:** "feat: add navigation arrow to display"

---

**Phase 2 Completion:**
```bash
git push origin feature/phase-2-navigation-logic
# Create pull request: "Phase 2: Navigation Logic"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-2-navigation-logic
```

---

## Phase 3: Audio Feedback

**Branch:** `feature/phase-3-audio-feedback`

**Phase Context:** Audio feedback provides critical user notification for navigation events when visual attention is focused elsewhere. Different audio patterns help users distinguish between navigation states, GPS status changes, and system events without requiring constant visual monitoring of the display. This enhances usability and provides confirmation of important navigation milestones.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-3-audio-feedback
```

### Step 3.1: Buzzer System

**Goal:** Implement distinctive audio notifications that provide immediate user feedback for critical navigation events and system status changes, enabling operation without constant visual monitoring.

**Context:** Audio feedback is essential for navigation systems because users need to focus attention on their surroundings rather than constantly monitoring displays. Distinctive sound patterns allow users to understand system status changes, navigation events, and GPS conditions through audio cues. This improves safety by reducing the need for visual attention on the device display during operation.

**Updates:**
- Add buzzer functions to `NavigationUtils.cpp`

**Implementation:**
```cpp
class BuzzerController {
private:
    int buzzerPin;
    
    void playTone(int frequency, int duration);
    
public:
    BuzzerController(int pin);
    void playNavigationEnabled();
    void playWaypointSet();
    void playGpsFixLost();
    void playGpsFixed();
    void playDestinationReached();
};
```

**Sound Design:**
- Navigation enabled: Ascending tone
- GPS fix acquired: Triple beep
- Destination reached: Celebration melody
- Fix lost: Descending tone

**Testing:**
- Trigger each sound via serial command
- Verify tones are distinct and recognizable

**Commit:** "feat: implement audio feedback system"

---

**Phase 3 Completion:**
```bash
git push origin feature/phase-3-audio-feedback
# Create pull request: "Phase 3: Audio Feedback"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-3-audio-feedback
```

---

## Phase 4: Bluetooth Communication

**Branch:** `feature/phase-4-bluetooth-comm`

**Phase Context:** Bluetooth Low Energy communication enables wireless waypoint management and real-time status monitoring through the iOS companion app. This wireless interface eliminates the need for physical connections while providing comprehensive remote control and monitoring capabilities. Reliable BLE communication is essential for practical field use and enhances user experience through seamless device integration.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-4-bluetooth-comm
```

### Step 4.1: BLE Service Setup

**Goal:** Establish robust Bluetooth Low Energy advertising and connection handling that enables reliable wireless communication with iOS devices while maintaining stable connections during navigation operations.

**Context:** BLE connectivity is the primary interface between the navigation device and user control systems. Reliable connection establishment and maintenance are critical for waypoint transmission and status monitoring. The BLE service must handle connection events gracefully and provide clear indication of connection status to ensure users understand when wireless control is available.

**Files Created:**
- `BluetoothController.h` - BLE communication class
- `BluetoothController.cpp` - BLE service implementation

**Implementation:**
```cpp
class BluetoothController {
private:
    BLEService bluetoothService;
    BLECharacteristic waypointCharacteristic;
    BLECharacteristic statusCharacteristic;
    
    bool initialized;
    bool connected;
    
    void onConnect();
    void onDisconnect();
    
public:
    bool begin(const char* deviceName);
    void update();
    bool isConnected() const;
    void sendStatus(const char* jsonData);
};
```

**Service Configuration:**
- Service UUID: `0000FFE0-0000-1000-8000-00805F9B34FB`
- Waypoint Characteristic: Write (waypoint data)
- Status Characteristic: Notify (device status)

**Testing:**
- Verify device advertises as "Helm"
- Test connection from iPhone's Bluetooth settings
- Confirm connection status on display

**Commit:** "feat: implement BLE service for iOS connection"

---

### Step 4.2: Waypoint Reception

**Goal:** Implement reliable waypoint data reception and parsing that seamlessly integrates received coordinates into the navigation system, enabling wireless waypoint setting from the iOS app.

**Context:** Wireless waypoint transmission eliminates the need for manual coordinate entry and enables dynamic navigation planning. The protocol must be robust enough to handle transmission errors while providing immediate navigation system integration. Successful waypoint reception should trigger navigation system updates and provide user confirmation of received targets.

**Implementation:**
```cpp
void handleWaypointWrite(BLEDevice central, BLECharacteristic characteristic);
bool parseWaypointData(const char* data, float& lat, float& lon);
```

**Protocol:**
```
Format: $GPS,latitude,longitude,altitude*
Example: $GPS,-32.940931,151.718029,45.2*
```

**Testing:**
- Send test waypoint via BLE testing app
- Verify navigation manager receives coordinates
- Confirm arrow points to received waypoint

**Commit:** "feat: implement waypoint reception via BLE"

---

### Step 4.3: Status Broadcasting

**Goal:** Transmit comprehensive navigation and system status data to iOS devices in real-time, providing remote monitoring capability and enabling advanced features in the companion app.

**Context:** Real-time status broadcasting enables the iOS app to display current navigation progress, GPS quality, and system health. This information helps users make informed navigation decisions and troubleshoot system issues. The JSON format provides structured data that can support current and future iOS app features while maintaining compatibility.

**Implementation:**
```cpp
void broadcastStatus(const GPSData& gps, const NavigationState& nav, float heading);
String createStatusJSON(const GPSData& gps, const NavigationState& nav, float heading);
```

**JSON Format:**
```json
{
  "hasGpsFix": true,
  "satellites": 8,
  "currentLat": -32.940931,
  "currentLon": 151.718029,
  "altitude": 45.2,
  "heading": 127.5,
  "distance": 245.8,
  "bearing": 89.2
}
```

**Testing:**
- Monitor BLE notifications with testing app
- Verify JSON structure is valid
- Confirm update rate ~1Hz

**Commit:** "feat: implement status broadcasting to iOS app"

---

**Phase 4 Completion:**
```bash
git push origin feature/phase-4-bluetooth-comm
# Create pull request: "Phase 4: Bluetooth Communication"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-4-bluetooth-comm
```

---

## Phase 5: RF Control System

**Branch:** `feature/phase-5-rf-control`

**Phase Context:** RF control enables autonomous course correction by transmitting commands to compatible trolling motors or steering systems. The 433MHz system provides reliable wireless control with sufficient range for marine applications. Integration with navigation logic enables automatic heading corrections, making the system truly autonomous rather than just providing guidance information.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-5-rf-control
```

### Step 5.1: RFM69 Module Initialization

**Goal:** Configure the RFM69HCW radio module for reliable 433MHz FSK transmission with optimal power and modulation settings for trolling motor remote control compatibility.

**Context:** RF control is what makes the navigation system truly autonomous rather than just a guidance display. The RFM69 module must be configured to match the specific modulation and timing requirements of trolling motor remote controls. Proper RF configuration ensures reliable command transmission over marine distances while avoiding interference with other radio systems.

**Files Created:**
- `RfController.h` - RF controller class
- `RfController.cpp` - FSK transmission implementation

**Implementation:**
```cpp
class RfController {
private:
    RFM69 radio;
    bool initialized;
    
    const float FREQUENCY = 433.032;
    const int TX_POWER = 20;
    
    void configureForFSK();
    void transmitBurst(const uint8_t* data, int length);
    
public:
    bool begin(int csPin, int resetPin);
    void transmitRightButton();
    void transmitLeftButton();
    bool isInitialized() const;
};
```

**Testing:**
- Verify radio initialization via serial
- Use RTL-SDR to confirm 433.032 MHz signal
- Test burst pattern timing

**Commit:** "feat: implement RFM69 radio controller"

---

### Step 5.2: Motor Control Integration

**Goal:** Integrate RF control with navigation logic to provide automated heading corrections based on calculated bearing errors, enabling true autonomous navigation with intelligent correction timing.

**Context:** The integration of RF control with navigation calculations creates the autonomous behavior that distinguishes this system from simple GPS displays. The system must intelligently determine when heading corrections are needed and avoid over-correction that could cause oscillatory behavior. Proper timing and tolerance settings ensure smooth navigation while maintaining course accuracy.

**Updates:**
- Integrate RF controller with navigation manager

**Implementation:**
```cpp
void NavigationManager::adjustHeading(float relativeAngle) {
    if (abs(relativeAngle) < HEADING_TOLERANCE) {
        return;
    }
    
    if (shouldCorrectHeading(relativeAngle)) {
        if (relativeAngle > 0) {
            rfController.transmitRightButton();
        } else {
            rfController.transmitLeftButton();
        }
        lastCorrectionTime = millis();
    }
}
```

**Testing:**
- Verify RF commands sent at correct times
- Test minimum correction interval
- Validate heading tolerance logic

**Commit:** "feat: integrate RF control with navigation system"

---

**Phase 5 Completion:**
```bash
git push origin feature/phase-5-rf-control
# Create pull request: "Phase 5: RF Control System"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-5-rf-control
```

---

## Phase 6: iOS App Foundation

**Branch:** `feature/phase-6-ios-foundation`

**Phase Context:** The iOS companion app transforms the navigation system from a standalone device into a comprehensive navigation solution. The app provides intuitive waypoint creation, real-time device monitoring, and enhanced user interface capabilities that would be impossible on the Arduino's limited display. This foundation enables advanced features while maintaining the autonomous operation of the core navigation system.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-6-ios-foundation
```

### Step 6.1: Xcode Project Setup

**Goal:** Establish a properly configured iOS project with required permissions and capabilities that provides a stable foundation for BLE communication and location services integration.

**Context:** Proper project configuration is critical for iOS app functionality, especially for location and Bluetooth features that require specific permissions and capabilities. The deployment target and capability settings ensure the app can access necessary system services while maintaining compatibility across supported iOS versions.

**Project Setup:**
1. Create new iOS App project "Waypoint"
2. Set deployment target: iOS 18.5+
3. Enable required capabilities: Location, Bluetooth

**File Structure:**
```
Waypoint/
├── Models/
│   └── DataModels.swift
├── Managers/
├── Views/
└── Components/
```

**Info.plist Configuration:**
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connect to Helm navigation device</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Navigation and mapping</string>
```

**Commit:** "feat: initialize iOS app project structure"

---

### Step 6.2: Data Models

**Goal:** Define robust data structures that ensure type-safe communication between iOS app components and provide consistent data representation for waypoints and device status.

**Context:** Well-defined data models prevent data corruption and communication errors between the iOS app and Arduino device. The Codable conformance enables reliable JSON serialization for BLE communication, while proper data typing ensures coordinates and navigation data maintain precision throughout the system.

**Files Created:**
- `Models/DataModels.swift`

**Implementation:**
```swift
struct Waypoint: Identifiable, Codable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    var name: String
    var comments: String
    var photoData: Data?
    var iconName: String
    let createdDate: Date
    var lastUpdatedDate: Date
}

struct DeviceStatus: Codable {
    let hasGpsFix: Bool
    let satellites: Int
    let currentLat: Double
    let currentLon: Double
    let altitude: Double
    let heading: Double
    let distance: Double
    let bearing: Double
}
```

**Testing:**
- Verify Codable encoding/decoding
- Test coordinate handling

**Commit:** "feat: define iOS data models"

---

### Step 6.3: Bluetooth Manager

**Goal:** Implement robust BLE communication with automatic reconnection and thread-safe data handling that provides reliable wireless connectivity to the navigation device under varying connection conditions.

**Context:** BLE connectivity can be intermittent in mobile environments, so the manager must handle connection drops gracefully and attempt automatic reconnection. Thread-safe operations ensure UI updates occur properly while maintaining stable communication with the navigation device. Auto-scanning improves user experience by eliminating manual connection management.

**Files Created:**
- `Managers/BluetoothManager.swift`

**Implementation:**
```swift
@MainActor
class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var deviceStatus: DeviceStatus?
    
    private var centralManager: CBCentralManager!
    private var helmPeripheral: CBPeripheral?
    private var autoScanTimer: Timer?
    
    private let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    private let waypointCharacteristicUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    
    func startScanning()
    func connect(peripheral: CBPeripheral)
    func sendWaypoint(latitude: Double, longitude: Double)
}
```

**Features:**
- Auto-scan and reconnect
- Status parsing and publishing
- Thread-safe characteristic writes

**Testing:**
- Connect to Arduino device
- Verify status updates received
- Test auto-reconnection

**Commit:** "feat: implement Bluetooth manager with auto-reconnect"

---

### Step 6.4: Location Manager

**Goal:** Implement comprehensive location services management that handles permissions gracefully and provides accurate user positioning for map centering and waypoint creation relative to current location.

**Context:** Location services are fundamental to navigation app functionality, but iOS requires careful permission handling and user privacy consideration. The location manager must provide accurate position data for map centering and waypoint creation while respecting user privacy settings and providing clear permission requests.

**Files Created:**
- `Managers/LocationManager.swift`

**Implementation:**
```swift
@MainActor
class LocationManager: NSObject, ObservableObject {
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let locationManager = CLLocationManager()
    
    func requestPermission()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}
```

**Testing:**
- Request location permissions
- Verify location updates
- Test permission states

**Commit:** "feat: implement location manager"

---

### Step 6.5: Basic Map View

**Goal:** Create an interactive map interface that provides intuitive navigation and waypoint visualization with standard map controls and user location display.

**Context:** The map view is the primary user interface for waypoint creation and navigation visualization. It must be responsive, intuitive, and provide clear visual feedback about waypoints and navigation status. Map interaction capabilities enable users to explore areas and create waypoints through natural touch interfaces.

**Files Created:**
- `Views/WaypointViews/MapView.swift`
- `ContentView.swift` - Main app interface

**Implementation:**
```swift
struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion()
    @State private var mapType: MKMapType = .standard
    
    var body: some View {
        Map(coordinateRegion: $region, showsUserLocation: true)
            .edgesIgnoringSafeArea(.all)
    }
}
```

**Features:**
- Center on user location
- Switch map types (standard/satellite)
- Pinch to zoom

**Testing:**
- Map loads and displays
- User location shown (blue dot)
- Map interactions work

**Commit:** "feat: implement basic map view"

---

### Step 6.6: Waypoint Creation

**Goal:** Enable intuitive waypoint creation through map tap gestures that immediately creates waypoints at selected coordinates and provides visual confirmation through map markers.

**Context:** Touch-based waypoint creation provides the most natural interface for navigation planning. Users can quickly select destinations by tapping the map, which is more intuitive than entering coordinates manually. Immediate visual feedback through markers confirms waypoint creation and enables users to see all planned navigation points at once.

**Updates:**
- Extend `MapView` with tap gesture

**Implementation:**
```swift
struct MapView: View {
    @State private var waypoints: [Waypoint] = []
    @State private var selectedWaypoint: Waypoint?
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: waypoints) { waypoint in
            MapMarker(coordinate: waypoint.coordinate)
        }
        .onTapGesture { location in
            let coordinate = convertToCoordinate(location)
            createWaypoint(at: coordinate)
        }
    }
}
```

**Testing:**
- Tap map to create waypoint
- Verify waypoint appears as marker
- Test multiple waypoints

**Commit:** "feat: implement tap-to-create waypoints"

---

### Step 6.7: Send Waypoint to Device

**Goal:** Complete the navigation workflow by transmitting selected waypoints to the navigation device, enabling immediate autonomous navigation to user-selected destinations.

**Context:** Waypoint transmission completes the connection between iOS app planning and Arduino device execution. This integration enables users to plan navigation on the large, high-resolution iOS display while having the navigation device autonomously execute the planned route. Successful transmission should trigger immediate navigation updates on the device display.

**Integration:**
- Connect map selection to BluetoothManager

**Implementation:**
```swift
Button("Send to Helm") {
    if let waypoint = selectedWaypoint {
        bluetoothManager.sendWaypoint(
            latitude: waypoint.coordinate.latitude,
            longitude: waypoint.coordinate.longitude
        )
    }
}
```

**Testing:**
- Create waypoint in app
- Send to Helm device
- Verify Arduino receives and navigates

**Commit:** "feat: implement waypoint transmission to device"

---

**Phase 6 Completion:**
```bash
git push origin feature/phase-6-ios-foundation
# Create pull request: "Phase 6: iOS App Foundation"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-6-ios-foundation
```

---

## Phase 7: Advanced iOS Features

**Branch:** `feature/phase-7-advanced-ios`

**Phase Context:** Advanced iOS features enhance the navigation system's usability and reliability through persistent waypoint storage, comprehensive device monitoring, location search capabilities, and offline operation support. These features transform the app from a basic waypoint sender into a comprehensive navigation planning and monitoring tool that supports complex navigation scenarios and field use requirements.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-7-advanced-ios
```

### Step 7.1: Waypoint Persistence

**Goal:** Implement reliable waypoint storage and retrieval that preserves navigation plans between app sessions, enabling users to build and maintain waypoint libraries for recurring navigation routes.

**Context:** Persistent waypoint storage is essential for practical navigation use, where users need to return to the same locations repeatedly or build complex navigation routes over time. The storage system must maintain waypoint integrity and handle app lifecycle events while providing efficient access to stored navigation data.

**Files Created:**
- `Managers/WaypointManager.swift`

**Implementation:**
```swift
class WaypointManager: ObservableObject {
    @Published var waypoints: [Waypoint] = []
    
    private let storageKey = "saved_waypoints"
    
    func saveWaypoint(_ waypoint: Waypoint)
    func deleteWaypoint(id: UUID)
    func updateWaypoint(id: UUID, name: String?, comments: String?)
    func loadWaypoints()
}
```

**Storage:**
- Use UserDefaults for simple storage
- JSON encoding/decoding
- Auto-save on changes

**Testing:**
- Create waypoints
- Kill and relaunch app
- Verify waypoints persist

**Commit:** "feat: implement waypoint persistence"

---

### Step 7.2: Waypoint Detail View

**Goal:** Provide comprehensive waypoint editing capabilities including names, descriptions, photos, and custom icons that enable detailed navigation planning and waypoint identification.

**Context:** Detailed waypoint information helps users organize navigation plans and identify specific locations. Photos provide visual confirmation of destinations, while custom icons and descriptions help distinguish between different types of waypoints. This detail capability supports complex navigation scenarios with multiple waypoint types.

**Files Created:**
- `Views/WaypointViews/WaypointDetailView.swift`

**Implementation:**
```swift
struct WaypointDetailView: View {
    @Binding var waypoint: Waypoint
    @State private var name: String
    @State private var comments: String
    
    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $name)
                TextEditor(text: $comments)
            }
            
            Section("Photo") {
                PhotoPicker(photoData: $waypoint.photoData)
            }
            
            Section("Icon") {
                IconPicker(iconName: $waypoint.iconName)
            }
        }
    }
}
```

**Testing:**
- Select waypoint from map
- Edit name and comments
- Add photo to waypoint

**Commit:** "feat: implement waypoint detail editor"

---

### Step 7.3: Device Status View

**Goal:** Create comprehensive device monitoring interface that displays real-time navigation progress, GPS quality metrics, and connection status to enable informed navigation decisions and system troubleshooting.

**Context:** Real-time device monitoring enables users to assess navigation system performance and make informed decisions about route changes or system operation. GPS quality indicators help users understand when conditions are suitable for accurate navigation, while connection status ensures users know when device control is available.

**Files Created:**
- `Views/StatusViews/DeviceStatusView.swift`

**Implementation:**
```swift
struct DeviceStatusView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack {
            ConnectionStatusBadge(isConnected: bluetoothManager.isConnected)
            
            if let status = bluetoothManager.deviceStatus {
                GPSStatusCard(status: status)
                NavigationStatusCard(status: status)
                CompassCard(heading: status.heading)
            }
        }
    }
}
```

**Testing:**
- View updates with real device data
- GPS fix status shown correctly
- Navigation distance displays

**Commit:** "feat: implement device status view"

---

### Step 7.4: Search Functionality

**Goal:** Integrate location search capabilities that enable users to find and navigate to named locations, addresses, and points of interest without requiring manual coordinate entry or map exploration.

**Context:** Location search dramatically improves navigation planning efficiency by allowing users to find destinations by name rather than manual map exploration. Integration with mapping services provides access to comprehensive location databases while maintaining the ability to create custom waypoints for locations not in standard databases.

**Files Created:**
- `Managers/SearchManager.swift`

**Implementation:**
```swift
class SearchManager: ObservableObject {
    @Published var searchResults: [MKMapItem] = []
    
    func search(query: String, region: MKCoordinateRegion) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        let response = try? await search.start()
        
        await MainActor.run {
            searchResults = response?.mapItems ?? []
        }
    }
}
```

**Testing:**
- Search for "Sydney Opera House"
- Results appear as list
- Select result to center map

**Commit:** "feat: implement location search"

---

### Step 7.5: Offline Map Tiles

**Goal:** Enable offline navigation capability through map tile caching that ensures navigation planning remains available without internet connectivity, critical for marine and remote area navigation.

**Context:** Offline map capability is essential for navigation systems used in remote areas or marine environments where internet connectivity is unreliable. Pre-cached map tiles ensure users can continue navigation planning and device monitoring even without connectivity, improving system reliability and field usability.

**Files Created:**
- `Managers/OfflineTileManager.swift`

**Implementation:**
```swift
class OfflineTileManager: ObservableObject {
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading: Bool = false
    
    func downloadTiles(region: MKCoordinateRegion, minZoom: Int, maxZoom: Int) async {
        let tiles = calculateTileRange(region: region, minZoom: minZoom, maxZoom: maxZoom)
        
        for tile in tiles {
            let url = constructTileURL(tile)
            await downloadAndCache(url: url)
            updateProgress()
        }
    }
    
    func clearCache()
    func getCacheSize() -> Int64
}
```

**Features:**
- Progress tracking
- Cancel download option
- Cache size management

**Testing:**
- Download tiles for small region
- Verify tiles cached locally
- Test offline map display

**Commit:** "feat: implement offline map tile downloading"

---

**Phase 7 Completion:**
```bash
git push origin feature/phase-7-advanced-ios
# Create pull request: "Phase 7: Advanced iOS Features"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-7-advanced-ios
```

---

## Phase 8: Calibration System

**Branch:** `feature/phase-8-calibration`

**Phase Context:** Compass calibration is critical for navigation accuracy, as magnetic interference from electronics, metal objects, or local magnetic anomalies can cause significant heading errors. The calibration system provides both the Arduino capability to collect calibration data and the iOS interface to guide users through the calibration process while visualizing the quality of calibration data collection.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-8-calibration
```

### Step 8.1: Arduino Calibration Mode

**Goal:** Implement calibration data collection mode that streams real-time magnetometer readings via BLE to enable comprehensive calibration data analysis and storage on the iOS device.

**Context:** Accurate compass calibration requires collecting magnetometer data across a full range of device orientations to map magnetic distortions and interference patterns. The Arduino must stream raw magnetometer data to the iOS device where more sophisticated analysis and visualization can be performed with greater computational resources and display capabilities.

**Updates:**
- Add calibration characteristics to BLE service
- Implement calibration state in CompassManager

**Implementation:**
```cpp
class CompassManager {
private:
    bool calibrationMode;
    CompassCalibration liveCalibration;
    
public:
    void startCalibration();
    void stopCalibration();
    void updateCalibration(float x, float y, float z);
    String getCalibrationJSON();
};
```

**Testing:**
- Start calibration mode
- Verify raw data streaming
- Confirm min/max tracking

**Commit:** "feat: implement compass calibration mode"

---

### Step 8.2: iOS Calibration View

**Goal:** Create intuitive calibration interface with real-time 3D visualization that guides users through proper calibration procedures and provides immediate feedback on calibration quality and completeness.

**Context:** Compass calibration success depends on user technique and data collection completeness. The iOS interface can provide visual feedback that helps users understand calibration progress and ensures they rotate the device through all necessary orientations. Real-time visualization helps users see the effect of their calibration movements and achieve better calibration results.

**Files Created:**
- `Views/SettingsViews/CalibrationView.swift`

**Implementation:**
```swift
struct CalibrationView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var isCalibrating: Bool = false
    @State private var calibrationData: CalibrationData?
    
    var body: some View {
        VStack {
            CalibrationVisualization(data: calibrationData)
            
            Button(isCalibrating ? "Stop" : "Start Calibration") {
                if isCalibrating {
                    bluetoothManager.stopCalibration()
                } else {
                    bluetoothManager.startCalibration()
                }
                isCalibrating.toggle()
            }
        }
    }
}
```

**Features:**
- 3D visualization of magnetometer readings
- Min/max indicator for each axis
- Completion percentage estimate

**Testing:**
- Start calibration
- Rotate device in all directions
- Verify min/max values update

**Commit:** "feat: implement compass calibration UI"

---

**Phase 8 Completion:**
```bash
git push origin feature/phase-8-calibration
# Create pull request: "Phase 8: Calibration System"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-8-calibration
```

---

## Phase 9: Polish & Testing

**Branch:** `feature/phase-9-polish-testing`

**Phase Context:** System polish and comprehensive testing ensure the navigation system performs reliably under real-world conditions and handles edge cases gracefully. Error handling, power optimization, and thorough documentation are essential for field deployment, while comprehensive testing validates system integration and performance across various scenarios and conditions.

**Branch Creation:**
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-9-polish-testing
```

### Step 9.1: Error Handling

**Goal:** Implement comprehensive error recovery and graceful degradation that ensures the navigation system continues to operate safely even when individual components fail or connectivity is lost.

**Context:** Navigation systems must handle failures gracefully because users depend on them for safety and accurate guidance. Error handling should provide clear feedback about system status while maintaining operation of functional components. Graceful degradation ensures users can continue navigation even with partial system functionality.

**Arduino Updates:**
```cpp
void handleGPSError() {
    displayManager.showError("GPS ERROR");
    buzzer.playError();
}

void handleBLEDisconnect() {
    displayManager.showStatus("BLE DISCONNECTED");
    navigationManager.setNavigationEnabled(false);
}
```

**iOS Updates:**
```swift
func handleConnectionLost() {
    showAlert(title: "Connection Lost", message: "Attempting to reconnect...")
    startAutoReconnect()
}
```

**Commit:** "feat: implement comprehensive error handling"

---

### Step 9.2: Power Optimization

**Goal:** Optimize system power consumption to maximize field operation time while maintaining navigation performance and responsiveness for extended autonomous operation.

**Context:** Power efficiency is critical for portable navigation systems that must operate for extended periods on battery power. Intelligent power management should reduce consumption during idle periods while maintaining full performance during active navigation. Optimization strategies should balance power savings with system responsiveness and navigation accuracy.

**Arduino Optimizations:**
- Lower GPS update rate when not navigating
- Reduce OLED refresh rate
- Sleep BLE when no connection

**iOS Optimizations:**
- Background location updates
- Reduce BLE polling frequency
- Cache map tiles aggressively

**Commit:** "perf: optimize power consumption"

---

### Step 9.3: Documentation & Comments

**Goal:** Provide comprehensive code documentation that enables future development, troubleshooting, and system modification by clearly explaining system architecture, component interactions, and implementation decisions.

**Context:** Thorough documentation is essential for maintaining and enhancing navigation systems over time. Clear documentation helps developers understand component interactions, troubleshoot issues, and implement modifications safely. Hardware documentation helps with deployment and field maintenance.

**Tasks:**
- Add class-level documentation
- Document public APIs
- Add inline comments for complex logic
- Create wiring diagram
- Update README with troubleshooting

**Commit:** "docs: add comprehensive code documentation"

---

### Step 9.4: Integration Testing

**Goal:** Validate complete system functionality through comprehensive end-to-end testing that covers normal operation, error conditions, and edge cases to ensure reliable field performance.

**Context:** Integration testing validates that all system components work together correctly under various conditions. Comprehensive testing scenarios help identify issues that might not appear during individual component testing but could cause problems during real-world operation. Systematic testing ensures the navigation system performs reliably across different environmental conditions and use cases.

**Test Scenarios:**
1. Power on device → Connect app → Send waypoint → Navigate
2. Lose GPS fix → Regain fix → Continue navigation
3. BLE disconnect → Auto-reconnect → Resume navigation
4. Arrive at destination → Audio feedback → Clear waypoint
5. Calibrate compass → Save → Verify improved accuracy

**Commit:** "test: complete end-to-end integration testing"

---

**Phase 9 Completion:**
```bash
git push origin feature/phase-9-polish-testing
# Create pull request: "Phase 9: Polish & Testing"
# Review and merge with squash
git checkout main
git pull origin main
git branch -d feature/phase-9-polish-testing
```

---

## Development Best Practices

### Git Workflow
- Always work in feature branches
- Never commit directly to main
- Squash commits on merge for clean history
- Delete branches after successful merge
- Use descriptive commit messages following conventional commits
- Test thoroughly before creating pull requests

### Pull Request Requirements
- Clear description of changes made
- Link to any relevant issues
- Include testing notes
- Screenshots/videos for UI changes
- Approval required before merge
- All CI checks must pass

### Arduino
- Test each hardware component independently before integration
- Use serial debugging extensively
- Implement graceful degradation for missing hardware
- Keep loop() non-blocking
- Commit after each working feature

### iOS
- Use SwiftUI previews for rapid UI development
- Test on physical device early and often
- Handle permission requests gracefully
- Use Combine for reactive data flow
- Commit after each complete feature

### Version Control
- Feature branches for each phase
- Descriptive commit messages following conventional commits
- Tag releases with version numbers
- Maintain CHANGELOG.md
- Squash commits on merge to keep main clean

---

## Testing Checklist

**Arduino:**
- [ ] GPS acquires fix outdoors
- [ ] Compass calibration completes successfully
- [ ] Display shows all data correctly
- [ ] BLE connects and stays connected
- [ ] RF commands transmit on correct frequency
- [ ] Audio feedback works for all events
- [ ] Navigation calculations are accurate

**iOS:**
- [ ] App requests permissions correctly
- [ ] Map loads and is interactive
- [ ] Waypoints can be created and edited
- [ ] Photos attach to waypoints
- [ ] Search finds locations
- [ ] Offline tiles download and display
- [ ] Device status updates in real-time
- [ ] Calibration view guides user effectively

**Integration:**
- [ ] Waypoint transmission works reliably
- [ ] Status data streams continuously
- [ ] Auto-reconnection works after disconnect
- [ ] Navigation completes successfully
- [ ] System handles errors gracefully

**Branch Management:**
- [ ] All phases developed in feature branches
- [ ] Pull requests created for each phase
- [ ] Commits squashed on merge
- [ ] Branches deleted after merge
- [ ] Main branch always contains working code