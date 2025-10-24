# Watersnake RF Controller & GPS Navigation System

An Arduino-based GPS navigation system that automatically controls a Watersnake Fierce 2 electric motor via 433MHz RF transmission. The system provides compass-guided navigation with real-time GPS tracking and OLED display feedback.

## Project Overview

This project consists of three main components:

1. **GPS Navigation System** (`GPS_directions/`) - Complete autonomous navigation with compass, GPS, and RF control
2. **Magnetometer Calibration** (`calibration/`) - Compass calibration utility
3. **Transmitter Test** (`transmitter_test/`) - Basic RF transmission testing

### Key Features

- Real-time GPS navigation with waypoint guidance
- Digital compass with magnetometer calibration
- 128x64 OLED display showing navigation data
- Automatic motor control via 433MHz RF transmission
- Distance and bearing calculations using haversine formula
- Visual arrow pointing toward destination
- Debug output via serial console

## Hardware Requirements

### Core Components

- **Arduino UNO R4** (or compatible)
- **Adafruit RFM69HCW 433MHz Breakout** - RF transmitter
- **Adafruit MMC5603 Magnetometer** - Digital compass
- **SSD1306 OLED Display** (128x64, I2C)
- **GPS Module** (UART compatible, 9600 baud)
- **433MHz Spring Antenna**

### Target Device

- **Watersnake Fierce 2 Electric Motor** with RF remote control

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
#include <math.h>                  // Mathematical functions
```

### Additional Requirements

- **RadioHead Library** by Mike McCauley (for RF69 support)
- **GPSParser.h** - Custom GPS parsing library (not included in files)

## Setup Instructions

### 1. Magnetometer Calibration

Before using the navigation system, calibrate the magnetometer:

1. Upload `calibration/calibration.ino`
2. Open Serial Monitor (9600 baud)
3. Rotate the device in all directions for 2-3 minutes
4. Copy the calibration values from Serial Monitor
5. Update these values in `GPS_directions.ino`:

```cpp
// Update these values from calibration output
float magXmax = 31.91;
float magYmax = 101.72;
float magZmax = 54.58;
float magXmin = -73.95;
float magYmin = -6.86;
float magZmin = -55.41;
```

### 2. Configure Destination

Set your target coordinates in `GPS_directions.ino`:

```cpp
// Set your destination coordinates here (latitude, longitude)
const float DESTINATION_LAT = -32.940931;
const float DESTINATION_LON = 151.718029;
```

### 3. Test RF Transmission

1. Upload `transmitter_test/transmitter_test.ino`
2. Verify RF transmission with your Watersnake motor
3. Ensure left/right commands work correctly

### 4. Upload Main Navigation System

Upload `GPS_directions/GPS_directions.ino` for full autonomous navigation.

## RF Protocol Technical Details

### Signal Specifications
- **Frequency**: 433.032 MHz
- **Modulation**: FSK with PWM encoding
- **Deviation**: 22.5 kHz
- **Bit Rate**: 6400 bps

### Control Codes
```cpp
// RIGHT command
static const uint64_t RIGHT_CODE_HIGH = 0x8000576d76ULL;
static const uint64_t RIGHT_CODE_LOW = 0xf7e077723ba90ULL;

// LEFT command  
static const uint64_t LEFT_CODE_HIGH = 0x8000576d76ULL;
static const uint64_t LEFT_CODE_LOW = 0xf7e077723ea84ULL;
```

### Pulse Timing
- **Short Pulse**: 50μs HIGH + 52μs LOW
- **Long Pulse**: 102μs HIGH + 52μs LOW  
- **Sync Pulse**: 170μs HIGH + 114μs LOW
- **Data Bits**: 90 bits total (40 high + 50 low)

## Usage Instructions

### Navigation Parameters

Adjust these constants in `GPS_directions.ino`:

```cpp
const float HEADING_TOLERANCE = 15.0;        // Degrees of acceptable heading error
const float MIN_CORRECTION_INTERVAL = 2000; // Minimum ms between corrections
const float MIN_DISTANCE_METERS = 5.0;      // Stop navigation when this close
```

### Display Layout

The OLED shows:
- **Left**: Navigation arrow and distance
- **Top Right**: Current GPS coordinates
- **Bottom Right**: Destination coordinates  
- **Bottom Left**: Distance to destination
- **Bottom Right**: Current altitude

### Serial Debug Output

Monitor navigation via Serial Console (9600 baud):
- GPS fix status and satellite count
- Current position and altitude
- Compass heading
- Turning commands and course corrections

## File Structure

```
├── calibration/
│   └── calibration.ino              # Magnetometer calibration utility
├── GPS_directions/
│   ├── GPS_directions.ino           # Main navigation system
│   ├── WatersnakeRFController.cpp   # RF control implementation
│   ├── WatersnakeRFController.h     # RF control header
│   ├── adjust_heading.ino           # Heading correction logic
│   ├── calculate_bearing.ino        # Bearing calculation
│   ├── calculate_distance.ino       # Distance calculation (Haversine)
│   ├── draw_arrow.ino              # OLED arrow drawing
│   ├── print_debug_info.ino        # Serial debug output
│   ├── read_heading.ino            # Magnetometer reading
│   └── update_display.ino          # OLED display updates
└── transmitter_test/
    ├── transmitter_test.ino         # Basic RF transmission test
    ├── WatersnakeRFController.cpp   # Simplified RF control
    └── WatersnakeRFController.h     # Simplified RF header
```

## Navigation Algorithm

1. **GPS Fix**: Wait for valid GPS signal with satellite lock
2. **Calculate Bearing**: Determine direction to destination using great-circle navigation
3. **Read Compass**: Get current heading from calibrated magnetometer  
4. **Calculate Error**: Find difference between desired bearing and current heading
5. **Correct Course**: Send LEFT/RIGHT commands if error exceeds tolerance
6. **Update Display**: Show navigation data and directional arrow
7. **Repeat**: Continue until within minimum distance of destination

## Troubleshooting

### GPS Issues
- **No GPS fix**: Ensure clear sky view, wait 2-5 minutes for cold start
- **Poor accuracy**: Check antenna connection and avoid metal interference
- **No serial data**: Verify GPS TX/RX wiring and baud rate (9600)

### RF Transmission Issues  
- **Motor not responding**: Check antenna connection and frequency (433.032 MHz)
- **Weak signal**: Verify 5V power supply and antenna positioning
- **Wrong commands**: Re-analyze RF codes with RTL-SDR if needed

### Compass Issues
- **Erratic heading**: Re-run magnetometer calibration away from metal objects
- **Constant drift**: Check I2C wiring and magnetometer mounting
- **No compass data**: Verify MMC5603 address (0x30) and I2C bus (Wire1)

### Display Issues
- **Blank screen**: Check I2C address (0x3C) and OLED power supply
- **Garbled display**: Verify SDA/SCL connections and pull-up resistors
- **No arrow**: Ensure GPS fix and valid bearing calculation

## Safety Notes

- Test RF transmission range in safe environment before deployment
- Ensure emergency manual override capability for motor control
- Verify GPS accuracy before trusting autonomous navigation
- Monitor battery levels for all components during operation
- Keep backup navigation method available

## License

This project uses reverse-engineered RF protocols for educational and personal use. Ensure compliance with local RF transmission regulations.

## Contributing

To extend this project:
1. Add support for additional motor brands via RF analysis
2. Implement waypoint navigation with multiple destinations  
3. Add data logging to SD card
4. Include obstacle avoidance sensors
5. Create mobile app interface for remote monitoring