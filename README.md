# AutoHelm - GPS Navigation System

An Arduino-based autonomous GPS navigation system with user control and configuration via Bluetooth connect app. The system provides compass-guided navigation with real-time GPS tracking, OLED display feedback, and wireless waypoint management through a companion iOS app.

## Project Overview

**Project Name**: AutoHelm  
**App Name**: Waypoint  
**Arduino Device Name**: Helm  

This project consists of three main components:

1. **Helm** (`Helm/`) - Complete autonomous navigation system with compass, GPS, BLE waypoint receiver, and RF control
2. **Magnetometer Calibration** (`calibration/`) - Compass calibration utility
3. **Waypoint** (`Waypoint/`) - Full-featured iOS app with offline maps and BLE waypoint control

The system enables users to select waypoints on their mobile device and wirelessly transmit GPS coordinates to the Helm device via Bluetooth Low Energy. The Helm device then autonomously navigates to the waypoint using automatic motor control, compass guidance, and real-time feedback through its OLED display.

### Key Features

- **Mobile App Integration** - iOS app with offline maps and BLE waypoint transmission for remote control
- **User-Controlled Navigation** - Set waypoints, enable/disable navigation, and monitor status via Bluetooth app
- **Real-time GPS Navigation** - Autonomous waypoint guidance with distance/bearing calculations
- **Digital Compass** - MMC5603 magnetometer with hard/soft iron calibration via mobile app
- **OLED Display** - 128x64 display showing navigation data and directional arrow
- **RF Motor Control** - 433MHz transmission to Watersnake motor remote
- **Offline Maps** - Download and cache OpenStreetMap tiles for offline use
- **BLE Communication** - Wireless waypoint transfer and device control from mobile app to Helm device

## Hardware Requirements

### Helm Device Components

- **Arduino UNO R4 WiFi** (required for BLE functionality)
- **Adafruit RFM69HCW 433MHz Breakout** - RF transmitter module
- **Adafruit MMC5603 Magnetometer** - Digital compass sensor
- **SSD1306 OLED Display** (128x64, I2C interface)
- **GPS Module** (UART compatible, 9600 baud rate)
- **Piezo Buzzer** - Audio feedback for navigation events
- **433MHz Spring Antenna** - For RF transmission

### Target Device

- **Watersnake Fierce 2 Electric Motor** with RF remote control capability

### Mobile Device

- **iOS Device** (iPhone/iPad) with Bluetooth Low Energy support
- **iOS 15.0+** required for SwiftUI MapKit features

## Software Dependencies

### Helm Device Libraries (Install via Library Manager)

```cpp
#include <Adafruit_GFX.h>          // OLED graphics library
#include <Adafruit_SSD1306.h>      // OLED display driver
#include <Adafruit_MMC56x3.h>      // MMC5603 magnetometer driver
#include <Wire.h>                  // I2C communication
#include <SoftwareSerial.h>        // GPS UART communication
#include <RH_RF69.h>               // RadioHead RF69 driver
#include <ArduinoBLE.h>            // Bluetooth Low Energy
#include <math.h>                  // Mathematical functions
```

### Additional Requirements

- **RadioHead Library** by Mike McCauley (for RFM69HCW RF transmission)
- **Xcode 15.0+** (for iOS app compilation)

## Wiring Diagrams

### Adafruit RFM69HCW Transceiver Radio Breakout - 433 MHz
```
RFM69HCW -> Arduino UNO R4 WiFi
VIN      -> 5V (5V tolerant)
GND      -> GND  
SCK      -> D13 (SCK)
MISO     -> D12 (MISO)
MOSI     -> D11 (MOSI)
CS       -> D10
RST      -> D9
G0/DIO0  -> D8
G2/DIO2  -> D7 (Direct modulation)
ANT      -> 433MHz spring antenna
```

### OLED Display (I2C on Wire1)
```
SSD1306 -> Arduino UNO R4 WiFi
VCC     -> 5V
GND     -> GND
SDA     -> SDA (Wire1 bus)
SCL     -> SCL (Wire1 bus)
Address -> 0x3C
```

### MMC5603 Magnetometer (I2C on Wire1)
```
MMC5603 -> Arduino UNO R4 WiFi
VIN     -> 5V
GND     -> GND
SDA     -> SDA (Wire1 bus)
SCL     -> SCL (Wire1 bus)
```

### GPS Module (Software Serial)
```
GPS Module -> Arduino UNO R4 WiFi
VCC        -> 5V
GND        -> GND
TX         -> D2 (GPS_RX_PIN)
RX         -> D3 (GPS_TX_PIN)
Baud Rate  -> 9600
```

### Piezo Buzzer
```
Piezo Buzzer -> Arduino UNO R4 WiFi
Positive (+) -> D4 (BUZZER_PIN)
Negative (-) -> GND
```

## Mobile App Features

### Waypoint iOS App

The Waypoint app provides comprehensive navigation and mapping functionality with complete user control over the Helm device:

#### Core Features
- **Interactive Map Interface** - Tap anywhere to set waypoints and control navigation remotely
- **Bluetooth Low Energy** - Connect to Arduino "Helm" device for wireless control
- **Real-time Location** - GPS positioning with accuracy indicators
- **Waypoint Transmission** - Send coordinates directly to Arduino via Bluetooth
- **Navigation Control** - Enable/disable autonomous navigation remotely
- **Device Status Monitoring** - Real-time feedback from Helm device via Bluetooth

#### Offline Maps System
- **Download Map Tiles** - Cache OpenStreetMap data for offline use
- **Configurable Areas** - Select download radius (1-20 km)
- **Region Management** - Name, edit, and delete cached regions
- **Storage Monitoring** - Track cache size and manage storage
- **Background Downloads** - Progress tracking with cancel capability

#### Connection Management  
- **Device Discovery** - Scan for nearby Arduino devices
- **Signal Strength** - Monitor BLE connection quality
- **Status Indicators** - Real-time connection feedback
- **Auto-reconnect** - Maintain stable connections

## Setup Instructions

### 1. Magnetometer Calibration (Required First)

Before using navigation, calibrate the compass via the mobile app:

1. Upload `Helm/Helm.ino` to Arduino UNO R4 WiFi
2. Install and launch Waypoint app on iOS device
3. Connect to "Helm" device via Bluetooth
4. Navigate to Calibration tab in app
5. Tap "Start Calibration"
6. Rotate device slowly in all directions for 2-3 minutes
7. Monitor real-time magnetometer readings in app
8. Tap "Save Calibration" when readings stabilize

### 2. Helm Device Navigation System Setup

1. Install all required libraries via Arduino IDE Library Manager
2. Upload `Helm/Helm.ino` to Arduino UNO R4 WiFi
3. Open Serial Monitor to verify GPS fix and component initialization
4. Device will begin advertising as "Helm" for Bluetooth connections

### 3. iOS App Installation

1. Open `Waypoint/Waypoint.xcodeproj` in Xcode
2. Update Development Team in project settings
3. Build and install to iOS device
4. Grant Location and Bluetooth permissions when prompted

### 4. System Integration

1. Power on Helm device and wait for GPS fix
2. Launch Waypoint app on iOS device
3. Go to "Helm" tab and scan for "Helm" device
4. Connect to Helm device (signal strength should appear)
5. Enable navigation in the app's navigation controls
6. Switch to "Waypoint" tab to set navigation targets
7. Tap anywhere on map to create waypoint
8. Tap "Send to Helm" to begin autonomous navigation

## BLE Communication Protocol

### Service Configuration
- **Service UUID**: `0000FFE0-0000-1000-8000-00805F9B34FB`
- **GPS Characteristic**: `0000FFE1-0000-1000-8000-00805F9B34FB`
- **Status Characteristic**: `0000FFE2-0000-1000-8000-00805F9B34FB`
- **Calibration Command**: `0000FFE3-0000-1000-8000-00805F9B34FB`
- **Calibration Data**: `0000FFE4-0000-1000-8000-00805F9B34FB`
- **Device Name**: "Helm"

### Data Format
```
$GPS,latitude,longitude,altitude*\n
```

### Example Transmission
```
$GPS,-32.940931,151.718029,45.2*\n
```

### Control Commands
- `NAV_ENABLE` - Enable autonomous navigation
- `NAV_DISABLE` - Disable autonomous navigation
- `START_CAL` - Begin compass calibration mode
- `STOP_CAL` - End compass calibration mode

The Helm device parses incoming data and extracts coordinates for autonomous navigation, with all control managed via the mobile app.

## RF Control Protocol

### Technical Specifications
- **Frequency**: 433.032 MHz
- **Modulation**: FSK with PWM encoding  
- **Deviation**: 22.5 kHz
- **Bit Rate**: 6400 bps
- **Data Length**: 90 bits total

### Control Codes (90-bit format)
```cpp
// RIGHT command
static const uint64_t RIGHT_CODE_HIGH = 0x8000576d76ULL;  // First 40 bits
static const uint64_t RIGHT_CODE_LOW = 0xf7e077723ba90ULL; // Last 50 bits

// LEFT command  
static const uint64_t LEFT_CODE_HIGH = 0x8000576d76ULL;   // First 40 bits
static const uint64_t LEFT_CODE_LOW = 0xf7e077723ea84ULL;  // Last 50 bits
```

### Pulse Timing
- **Short Pulse**: 50μs HIGH + 52μs LOW (represents bit 0)
- **Long Pulse**: 102μs HIGH + 52μs LOW (represents bit 1) 
- **Sync Pulse**: 170μs HIGH + 114μs LOW (frame start)
- **Gap Duration**: 114μs between transmissions

## Navigation Algorithm

### Core Navigation Loop

1. **BLE Initialization** - Advertise as "Helm" for app connections
2. **Hardware Startup** - Initialize GPS, compass, OLED display, RF transmitter
3. **GPS Acquisition** - Wait for satellite lock and valid position data
4. **Mobile App Connection** - Wait for Bluetooth connection from Waypoint app
5. **User-Controlled Operation**:
   - Receive waypoints from mobile app via BLE
   - Monitor navigation enable/disable commands from app
   - Execute compass calibration when requested via app
6. **Autonomous Navigation Execution**:
   - Calculate bearing to destination using great-circle formulas
   - Read current heading from calibrated magnetometer
   - Determine heading error and required correction
   - Send LEFT/RIGHT RF commands if error exceeds tolerance
   - Update OLED display with navigation data and directional arrow
   - Provide real-time status feedback to mobile app via BLE
   - Provide audio feedback via piezo buzzer for navigation events
7. **Arrival Detection** - Stop navigation when within minimum distance threshold and notify app

### Navigation Parameters

Adjust these constants in `Helm/DataModels.cpp`:

```cpp
const float HEADING_TOLERANCE = 15.0;        // Acceptable heading error (degrees)
const float MIN_CORRECTION_INTERVAL = 2000; // Minimum time between corrections (ms)
const float MIN_DISTANCE_METERS = 5.0;      // Stop navigation distance threshold (m)
const int BUZZER_PIN = 7;                   // Piezo buzzer pin
```

### Display Layout

The 128x64 OLED shows:
- **Left Panel**: Directional arrow pointing toward target + distance
- **Top Right**: Current GPS coordinates (lat/lon)  
- **Middle Right**: Target destination coordinates
- **Bottom Left**: Distance to target (meters/kilometers)
- **Bottom Right**: Current altitude
- **Status Icons**: GPS fix status, BLE connection, and navigation state
- **Status Messages**: GPS fix status and satellite count

## Usage Instructions

### Mobile App Workflow

1. **Connect to Arduino**:
   - Open Waypoint app
   - Go to "Helm" tab
   - Tap "Scan" to discover devices
   - Select "Helm" device to connect
   - Verify connection status shows "Connected"

2. **Enable Navigation**:
   - In "Helm" tab, toggle "Navigation Control" to enabled
   - Helm device will activate autonomous navigation mode
   - Status indicator shows "Navigation Active"

3. **Set Navigation Waypoint**:
   - Switch to "Waypoint" tab  
   - Tap anywhere on map to select destination
   - Coordinates appear in waypoint card
   - Tap "Send to Helm" to transmit waypoint
   - Helm device begins autonomous navigation
   - Monitor progress in real-time via "Helm" status tab

4. **Download Offline Maps** (Optional):
   - Go to "Settings" tab, then "Offline Maps"
   - Tap map location to select download center
   - Adjust radius slider (1-20 km)
   - Tap "Download Maps for Selected Area"  
   - Monitor download progress
   - Maps work without internet connection

5. **Compass Calibration**:
   - Go to "Settings" tab, then "Calibration"
   - Ensure Arduino is connected
   - Tap "Start Calibration"
   - Rotate device slowly in all directions
   - Monitor real-time magnetometer readings
   - Tap "Save" when calibration is complete

### Helm Device Operation

1. **Startup Sequence**:
   - Power on Helm device
   - Wait for component initialization messages
   - GPS will search for satellite signals (2-5 minutes initially)
   - Display shows "NO FIX!" until GPS locks
   - BLE begins advertising for mobile app connections
   - Piezo buzzer plays startup tone sequence

2. **Navigation Modes**:
   - **Standby**: GPS coordinates displayed, awaiting app connection and waypoint
   - **Ready**: Connected to app, navigation disabled, awaiting commands
   - **Navigating**: Arrow points toward target, distance shown, autonomous control active
   - **Arrived**: "Destination reached!" when within 5m threshold, plays arrival tone
   - **Calibration**: Real-time magnetometer data display during app-controlled calibration

3. **Audio Feedback**:
   - **App Connected**: Ascending tone sequence
   - **App Disconnected**: Descending tone sequence
   - **Navigation Started**: Multi-tone startup melody
   - **Waypoint Set**: Confirmation beep sequence
   - **GPS Fix Acquired**: Triple beep + ascending melody
   - **GPS Fix Lost**: Descending alarm sequence
   - **Destination Reached**: Victory melody sequence

4. **Manual Override**:
   - System sends RF commands automatically based on compass heading
   - Commands repeat every 2+ seconds if heading error persists
   - Navigation can be disabled remotely via mobile app
   - No manual controls on Helm device - all control via mobile app

### Serial Debug Output

Monitor system via Serial Console (9600 baud):

```
GPS Navigation Starting...
OLED initialised!
GPS initialised! 
Magnetometer initialised!
BLE GPS Receiver initialized successfully
Test Transmitter
sending RIGHT...
sending LEFT...
Setup complete!
BLE: Device connected!
Navigation enabled
New waypoint received from mobile app!
Target: -32.940931, 151.718029
Time: 12:34:56, Satellites: 8, Position: -32.940500, 151.717800, Altitude: 45.2 m, Fix: Yes, Heading: 127.5
Turning RIGHT (off by 23.2 degrees)
On course!
Destination reached!
```

## File Structure

```
├── Helm/
│   ├── Helm.ino                     # Main navigation system
│   ├── GPSReceiver.cpp              # BLE waypoint receiver implementation  
│   ├── GPSReceiver.h                # BLE receiver header with calibration support
│   ├── DeviceRFController.cpp       # RF transmission implementation
│   ├── DeviceRFController.h         # RF controller header
│   ├── NavigationManager.cpp        # Navigation logic and waypoint management
│   ├── NavigationManager.h          # Navigation manager header
│   ├── DisplayManager.cpp           # OLED display management
│   ├── DisplayManager.h             # Display manager header
│   ├── CompassManager.cpp           # Magnetometer control and calibration
│   ├── CompassManager.h             # Compass manager header
│   ├── GPSManager.cpp               # GPS data processing
│   ├── GPSManager.h                 # GPS manager header
│   ├── NavigationUtils.cpp          # Navigation calculations and audio feedback
│   ├── NavigationUtils.h            # Navigation utilities header
│   ├── DataModels.cpp               # System configuration constants
│   └── DataModels.h                 # Data structures and system config
├── Waypoint/
│   ├── Waypoint/
│   │   ├── Views/
│   │   │   ├── ContentView.swift            # Main app interface
│   │   │   ├── WaypointViews/              # Map and waypoint management
│   │   │   └── SettingsViews/              # Device configuration and controls
│   │   ├── Managers/
│   │   │   ├── BluetoothManager.swift       # BLE device communication
│   │   │   ├── LocationManager.swift       # iOS location services
│   │   │   ├── OfflineTileManager.swift    # Map caching system
│   │   │   └── WaypointManager.swift       # Waypoint data management
│   │   ├── Components/                      # Reusable UI components
│   │   ├── Models/                          # Data models and structures
│   │   ├── Utilities/                       # Helper functions and extensions
│   │   ├── Assets.xcassets/                 # App icons and resources
│   │   └── Info.plist                       # App permissions and settings
│   └── Waypoint.xcodeproj/                  # Xcode project files
└── README.md                                # This documentation
```

## Troubleshooting

### Helm Device Issues

**GPS Problems**:
- **No GPS fix**: Ensure clear sky view, wait 2-5 minutes for satellite acquisition
- **Poor accuracy**: Check antenna connection, avoid indoor/metal interference
- **No serial data**: Verify GPS TX→D2, RX→D3 wiring and 9600 baud rate
- **Erratic coordinates**: Confirm stable 5V power supply to GPS module

**BLE Connection Issues**:
- **App won't connect**: Verify Helm device is powered and advertising "Helm"
- **No waypoints received**: Check BLE protocol format matches specification
- **Connection drops**: Ensure stable power supply and maintain <30m range
- **Commands not working**: Verify navigation is enabled in mobile app

**RF Transmission Problems**:
- **Motor not responding**: Verify antenna connection and 433.032 MHz frequency
- **Weak signal**: Check 5V power supply stability and antenna positioning  
- **Wrong direction**: Re-run calibration via mobile app or verify motor LEFT/RIGHT codes
- **RFM69HCW init failure**: Check SPI wiring (D10→CS, D9→RST, D8→G0)

**Compass/Display Issues**:
- **Erratic heading**: Re-calibrate magnetometer via mobile app away from metal objects
- **Blank OLED**: Verify I2C address 0x3C and Wire1 bus connections (SDA/SCL)
- **No compass data**: Check MMC5603 power and I2C wiring
- **Display not updating**: Ensure display.display() calls in main loop

**Audio Issues**:
- **No buzzer sounds**: Verify piezo buzzer connections (D7→+, GND→-)
- **Weak audio**: Check buzzer polarity and power connections

### iOS App Issues

**Connection Problems**:
- **No devices found**: Enable Bluetooth, ensure Helm device is powered and nearby
- **Connection fails**: Restart both app and Helm device, check distance <10m
- **Permissions denied**: Grant Bluetooth and Location access in iOS Settings

**Map Issues**:
- **No location shown**: Enable Location Services for Waypoint app
- **Map won't load**: Check internet connection for online tile loading
- **Offline maps not working**: Verify download completed successfully
- **Poor GPS accuracy**: Use device outdoors with clear sky view

**Control Issues**:
- **Navigation won't start**: Ensure navigation is enabled in Helm tab
- **Waypoints not sending**: Verify Bluetooth connection is active
- **No status updates**: Check BLE connection stability

**App Performance**:
- **Slow map loading**: Clear cache or reduce offline map area size
- **App crashes**: Restart app, check iOS version compatibility (15.0+)
- **High storage usage**: Delete unused offline map regions

## Performance Specifications

- **Navigation Update Rate**: 10Hz main loop frequency
- **GPS Accuracy**: 3-5 meters with good satellite reception (8+ satellites)
- **Compass Precision**: ±2° with proper magnetometer calibration via mobile app
- **RF Range**: 100+ meters in open water conditions
- **BLE Range**: 10-30 meters for waypoint transmission and device control
- **Battery Life**: Varies with GPS acquisition time and RF transmission frequency
- **Offline Map Storage**: ~2-5MB per km² depending on zoom levels (10-15)

## Safety and Legal Considerations

- **RF Regulations**: Ensure 433MHz transmission compliance with local regulations
- **Water Safety**: Test system thoroughly in controlled environment before deployment
- **Emergency Override**: Always maintain manual motor control capability as backup
- **GPS Dependency**: Keep alternative navigation methods available
- **Battery Management**: Monitor power levels during extended operation
- **Range Limitations**: Maintain visual contact with remote device when possible
- **Mobile App Dependency**: Ensure mobile device battery and connectivity for system control

## Future Enhancement Possibilities

- **Multi-waypoint Routes** - Support sequential navigation through multiple points via mobile app
- **Obstacle Avoidance** - Integration with ultrasonic or radar sensors
- **Data Logging** - SD card storage of navigation tracks and performance metrics accessible via mobile app
- **Web Interface** - WiFi-based configuration and remote monitoring as alternative to mobile app
- **Speed Control** - Variable motor speed based on distance and conditions, controlled via app
- **Weather Compensation** - Wind and current drift correction algorithms
- **Geofencing** - Automatic boundary enforcement for operational safety configured via app
- **Voice Commands** - Audio control integration with mobile app
- **Multi-device Support** - Control multiple Helm devices from single mobile app

## License and Compliance

This project uses reverse-engineered RF protocols for educational and personal use. Users must ensure compliance with local RF transmission regulations and respect device warranty considerations. The OpenStreetMap tile usage in the mobile app follows OSM usage policies for personal/educational applications.

## Contributing

Contributions welcome! Please:
1. Fork repository and create feature branches  
2. Test changes thoroughly with actual hardware
3. Document RF protocol modifications or new hardware integrations
4. Ensure backward compatibility with existing mobile app functionality
5. Update documentation for new features or requirements
6. Test BLE communication protocols with both Arduino and iOS components