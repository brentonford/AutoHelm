# Watersnake RF Controller & GPS Navigation System

An Arduino-based GPS navigation system that automatically controls a Watersnake Fierce 2 electric motor via 433MHz RF transmission. The system provides compass-guided navigation with real-time GPS tracking, OLED display feedback, and Bluetooth Low Energy waypoint control from a mobile app.

## Project Overview

This project consists of three main components:

1. **GPS Navigation System** (`GPS_directions/`) - Complete autonomous navigation with compass, GPS, BLE waypoint receiver, and RF control
2. **Magnetometer Calibration** (`calibration/`) - Compass calibration utility
3. **Transmitter Test** (`transmitter_test/`) - Basic RF transmission testing

### Key Features

- **Mobile App Integration** - Receive GPS waypoints via Bluetooth Low Energy
- Real-time GPS navigation with waypoint guidance
- Digital compass with magnetometer calibration
- 128x64 OLED display showing navigation data
- Automatic motor control via 433MHz RF transmission
- Distance and bearing calculations using haversine formula
- Visual arrow pointing toward destination
- Debug output via serial console
- Autonomous course correction with configurable tolerance

## Hardware Requirements

### Core Components

- **Arduino UNO R4 WiFi** (or Arduino Nano 33 BLE for BLE functionality)
- **Adafruit RFM69HCW 433MHz Breakout** - RF transmitter
- **Adafruit MMC5603 Magnetometer** - Digital compass
- **SSD1306 OLED Display** (128x64, I2C)
- **GPS Module** (UART compatible, 9600 baud)
- **433MHz Spring Antenna**

### Target Device

- **Watersnake Fierce 2 Electric Motor** with RF remote control

## Mobile App Integration

The system receives GPS waypoints via Bluetooth Low Energy from a mobile app. The user can:

1. Select a position on a map in the mobile app
2. Send GPS coordinates to the Arduino via Bluetooth
3. The Arduino automatically navigates to the waypoint

### BLE Protocol

**Service UUID**: `0000FFE0-0000-1000-8000-00805F9B34FB`
**Characteristic UUID**: `0000FFE1-0000-1000-8000-00805F9B34FB`

**Data Format**: `$GPS,latitude,longitude,altitude*\n`
**Example**: `$GPS,-32.940931,151.718029,45.2*\n`

The Arduino advertises as "Watersnake" and accepts waypoint data via the BLE characteristic.

## Wiring Diagrams

### RFM69HCW RF Module
```
RFM69HCW -> Arduino UNO R4
VIN      -> 5V
GND      -> GND
SCK      -> D13 (SCK)
MISO     -> D12 (MISO)
MOSI     -> D11 (MOSI)
CS       -> D10
RST      -> D9
G0/DIO0  -> D2
ANT      -> 433MHz spring antenna
```

### OLED Display (I2C)
```
SSD1306 -> Arduino UNO R4
VCC     -> 5V
GND     -> GND
SDA     -> SDA (Wire1)
SCL     -> SCL (Wire1)
Address -> 0x3C
```

### MMC5603 Magnetometer (I2C)
```
MMC5603 -> Arduino UNO R4
VIN     -> 5V
GND     -> GND
SDA     -> SDA (Wire1)
SCL     -> SCL (Wire1)
```

### GPS Module
```
GPS Module -> Arduino UNO R4
VCC        -> 5V
GND        -> GND
TX         -> D2 (GPS_RX_PIN)
RX         -> D3 (GPS_TX_PIN)
```

## Software Dependencies

### Required Libraries

Install these libraries via Arduino IDE Library Manager:

```cpp
#include <Adafruit_GFX.h>          // OLED graphics
#include <Adafruit_SSD1306.h>      // OLED display driver
#include <Adafruit_MMC56x3.h>      // Magnetometer driver
#include <Wire.h>                  // I2C communication
#include <SoftwareSerial.h>        // GPS serial communication
#include <RH_RF69.h>               // RadioHead RF69 driver
#include <ArduinoBLE.h>            // Bluetooth Low Energy
#include <math.h>                  // Mathematical functions
```

### Additional Requirements

- **RadioHead Library** by Mike McCauley (for RFM69HCW support)
- Custom GPS parsing functionality (included in project files)

## Setup Instructions

### 1. Magnetometer Calibration

Before using the navigation system, calibrate the magnetometer:

1. Upload `calibration/calibration.ino`
2. Open Serial Monitor (9600 baud)
3. Rotate the device slowly in all directions for 2-3 minutes
4. Note the min/max values for X, Y, and Z axes
5. Copy the final calibration values from Serial Monitor
6. Update these values in `GPS_directions.ino`:

```cpp
// Update these values from calibration output
float magXmax = 31.91;
float magYmax = 101.72;
float magZmax = 54.58;
float magXmin = -73.95;
float magYmin = -6.86;
float magZmin = -55.41;
```

### 2. Configure Default Destination

Set default target coordinates in `GPS_directions.ino` (can be overridden via mobile app):

```cpp
// Default destination coordinates (overridden by BLE waypoints)
float DESTINATION_LAT = -32.940931;
float DESTINATION_LON = 151.718029;
```

### 3. Test RF Transmission

1. Upload `transmitter_test/transmitter_test.ino`
2. Open Serial Monitor to see transmission status
3. Verify RF transmission works with your Watersnake motor
4. Ensure left/right commands control the motor correctly

### 4. Upload Main Navigation System

Upload `GPS_directions/GPS_directions.ino` for full autonomous navigation with BLE waypoint capability.

## RF Protocol Technical Details

The system uses two different RF implementations:

### Main Navigation System (RFM69HCW)
- **Frequency**: 433.032 MHz
- **Modulation**: FSK with PWM encoding
- **Deviation**: 22.5 kHz
- **Bit Rate**: 6400 bps

### Test System (Simple Digital)
- **Direct digital pin control** for basic testing
- **Pulse timing based** RF generation

### Control Codes
```cpp
// RIGHT command (90-bit)
static const uint64_t RIGHT_CODE_HIGH = 0x8000576d76ULL;  // First 40 bits
static const uint64_t RIGHT_CODE_LOW = 0xf7e077723ba90ULL; // Last 50 bits

// LEFT command (90-bit)
static const uint64_t LEFT_CODE_HIGH = 0x8000576d76ULL;   // First 40 bits
static const uint64_t LEFT_CODE_LOW = 0xf7e077723ea84ULL;  // Last 50 bits
```

### Pulse Timing
- **Short Pulse**: 50μs HIGH + 52μs LOW (bit 0)
- **Long Pulse**: 102μs HIGH + 52μs LOW (bit 1)
- **Sync Pulse**: 170μs HIGH + 114μs LOW
- **Data Length**: 90 bits total (40 high + 50 low)

## Usage Instructions

### Navigation Parameters

Adjust these constants in `GPS_directions.ino` to fine-tune navigation behavior:

```cpp
const float HEADING_TOLERANCE = 15.0;        // Degrees of acceptable heading error
const float MIN_CORRECTION_INTERVAL = 2000; // Minimum ms between corrections
const float MIN_DISTANCE_METERS = 5.0;      // Stop navigation when this close
```

### Display Layout

The 128x64 OLED display shows:
- **Left Panel**: Navigation arrow and distance to target
- **Top Right**: Current GPS coordinates (latitude/longitude)
- **Middle Right**: Target destination coordinates
- **Bottom Left**: Distance to destination (meters/kilometers)
- **Bottom Right**: Current altitude
- **Status**: GPS fix status and satellite count

### Mobile App Workflow

1. Arduino advertises as "Watersnake" via BLE
2. Mobile app connects to Arduino
3. User selects waypoint on map
4. App sends GPS coordinates in format: `$GPS,lat,lon,alt*`
5. Arduino receives waypoint and begins navigation
6. System navigates autonomously to target location

### Serial Debug Output

Monitor navigation via Serial Console (9600 baud):
- BLE connection status and waypoint reception
- GPS fix status and satellite count
- Current position and altitude
- Compass heading and calibration data
- Distance and bearing to target
- Turning commands and course corrections
- Navigation status updates

## File Structure

```
├── calibration/
│   └── calibration.ino              # Magnetometer calibration utility
├── GPS_directions/
│   ├── GPS_directions.ino           # Main navigation system
│   ├── GPSReceiver.cpp              # BLE waypoint receiver implementation
│   ├── GPSReceiver.h                # BLE waypoint receiver header
│   ├── WatersnakeRFController.cpp   # RFM69HCW RF control implementation
│   ├── WatersnakeRFController.h     # RFM69HCW RF control header
│   ├── adjust_heading.ino           # Heading correction logic
│   ├── calculate_bearing.ino        # Bearing calculation (great circle)
│   ├── calculate_distance.ino       # Distance calculation (Haversine formula)
│   ├── draw_arrow.ino              # OLED navigation arrow drawing
│   ├── print_debug_info.ino        # Serial debug output formatting
│   ├── read_heading.ino            # Magnetometer reading with calibration
│   └── update_display.ino          # OLED display updates and formatting
└── transmitter_test/
    ├── transmitter_test.ino         # Basic RF transmission test
    ├── WatersnakeRFController.cpp   # Simple digital pin RF control
    └── WatersnakeRFController.h     # Simple RF control header
```

## Navigation Algorithm

1. **BLE Initialization**: Start advertising as "Watersnake" for mobile app connections
2. **Hardware Setup**: Initialize GPS, compass, OLED display, and RF transmitter
3. **Waypoint Reception**: Listen for GPS coordinates from mobile app via BLE
4. **GPS Acquisition**: Wait for valid GPS signal with satellite lock
5. **Compass Calibration**: Apply hard/soft iron corrections to magnetometer readings
6. **Navigation Loop**:
   - Calculate bearing to destination using great-circle navigation
   - Read current heading from calibrated magnetometer
   - Calculate heading error (relative angle)
   - Send LEFT/RIGHT RF commands if error exceeds tolerance
   - Update OLED display with navigation data and directional arrow
   - Output debug information via serial
7. **Arrival Detection**: Stop navigation when within minimum distance threshold

## Troubleshooting

### BLE Connection Issues
- **App won't connect**: Ensure Arduino is advertising and BLE is initialized
- **No waypoint received**: Check data format matches protocol specification
- **Connection drops**: Verify power supply stability and BLE range

### GPS Issues
- **No GPS fix**: Ensure clear sky view, wait 2-5 minutes for cold start
- **Poor accuracy**: Check antenna connection and avoid metal interference  
- **No serial data**: Verify GPS TX/RX wiring and baud rate (9600)
- **Erratic coordinates**: Ensure stable power supply to GPS module

### RF Transmission Issues
- **Motor not responding**: Check antenna connection and frequency (433.032 MHz)
- **Weak signal**: Verify 5V power supply and antenna positioning
- **Wrong commands**: Re-analyze RF codes with RTL-SDR if needed
- **RFM69HCW init failure**: Check SPI wiring and power connections

### Compass Issues
- **Erratic heading**: Re-run magnetometer calibration away from metal objects
- **Constant drift**: Check I2C wiring (Wire1 bus) and magnetometer mounting
- **No compass data**: Verify MMC5603 I2C address and bus configuration
- **Poor calibration**: Ensure full 3D rotation during calibration process

### Display Issues
- **Blank screen**: Check I2C address (0x3C) and OLED power supply
- **Garbled display**: Verify SDA/SCL connections on Wire1 bus
- **No arrow**: Ensure GPS fix and valid bearing calculation
- **Display not updating**: Check display.display() calls in update loop

## Safety and Legal Notes

- **RF Regulations**: Ensure compliance with local 433MHz transmission regulations
- **Water Safety**: Test system thoroughly in controlled environment before water deployment
- **Emergency Override**: Always maintain manual control capability for motor
- **GPS Accuracy**: Verify GPS precision before trusting autonomous navigation
- **Battery Management**: Monitor power levels for all components during operation
- **Backup Navigation**: Keep alternative navigation method available

## Performance Specifications

- **Update Rate**: 10Hz navigation loop
- **GPS Accuracy**: Typically 3-5 meters with good satellite reception
- **Compass Precision**: ±2° with proper calibration
- **RF Range**: Up to 100+ meters in open water (dependent on conditions)
- **Battery Life**: Varies with GPS fix time and RF transmission frequency
- **BLE Range**: Typically 10-30 meters for waypoint setting

## Future Enhancements

Potential improvements for this system:
1. **Multi-waypoint Navigation** - Support for route planning with multiple destinations
2. **Obstacle Avoidance** - Integration with ultrasonic or lidar sensors
3. **Data Logging** - SD card storage of navigation tracks and performance data
4. **Web Interface** - WiFi-based configuration and monitoring
5. **Motor Speed Control** - Variable speed based on distance to target
6. **Weather Integration** - Wind and current compensation
7. **Geofencing** - Automatic boundary enforcement for safe operation areas

## License

This project uses reverse-engineered RF protocols for educational and personal use. Ensure compliance with local RF transmission regulations and device warranty considerations.

## Contributing

To contribute to this project:
1. Fork the repository and create feature branches
2. Test all changes thoroughly with actual hardware
3. Document any new RF protocols or hardware integrations
4. Ensure backward compatibility with existing calibration data
5. Update documentation for any new features or requirements