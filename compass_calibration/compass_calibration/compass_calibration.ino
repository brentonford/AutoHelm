#include <Adafruit_MMC56x3.h>
#include <algorithm>

/* Assign a unique ID to this sensor at the same time */
Adafruit_MMC5603 mag = Adafruit_MMC5603(12345);

// // Calibration values for magnetometer 
// float magMinX;
// float magMaxX;
// float magMinY;
// float magMaxY;
// float magMinZ;
// float magMaxZ;
// float magXoffset;
// float magYoffset;
// float magZoffset;
// float avgDelta;
// float magXscale;
// float magYscale;
// float magZscale;

// Calibration values for magnetometer 
float magMinX = -68.86;
float magMaxX = 2.74;
float magMinY = 9.46;
float magMaxY = 96.35;
float magMinZ = -60.94;
float magMaxZ = -39.06;
float magXoffset = -33.06;
float magYoffset = 52.90;
float magZoffset = -50.00;
float avgDelta = 30.06;
float magXscale = 0.84;
float magYscale = 0.69;
float magZscale = 2.75;

float headingOffset = 104;

// Variables to store the latest GPS information
float latest_bearing = 0;

long lastDisplayTime;

bool calibrating;
bool heading;

void calibrate() {

  static unsigned long startTime = 0;
  static int samples = 0;

  if (startTime == 0) {
    Serial.println("Calibrating... Rotate sensor in full circles and figure-8 for 20 seconds.");
    startTime = millis();
    // Initialize to extreme values for proper min/max detection
    magMinX = magMinY = magMinZ = 10000;
    magMaxX = magMaxY = magMaxZ = -10000;
    samples = 0;
  }

  // ~400 samples over 20s
  if (millis() - startTime < 20000) {
    sensors_event_t magEvent;
    if (mag.getEvent(&magEvent)) {
      float x = magEvent.magnetic.x;
      float y = magEvent.magnetic.y;
      float z = magEvent.magnetic.z;
      
      // Reject obvious outliers (valid magnetometer readings are typically -150 to +150 uT)
      // These glitch values are usually > 1000 uT
      bool validReading = (abs(x) < 500 && abs(y) < 500 && abs(z) < 500);
      
      if (validReading) {
        // Debug: print raw values
        if (samples % 50 == 0) {
          Serial.print("Raw: X="); Serial.print(x);
          Serial.print(" Y="); Serial.print(y);
          Serial.print(" Z="); Serial.println(z);
        }
        
        magMinX = std::min(magMinX, x);
        magMaxX = std::max(magMaxX, x);
        magMinY = std::min(magMinY, y);
        magMaxY = std::max(magMaxY, y);
        magMinZ = std::min(magMinZ, z);
        magMaxZ = std::max(magMaxZ, z);
        samples++;
      } else {
        // Log rejected outliers
        Serial.print("REJECTED outlier: X="); Serial.print(x);
        Serial.print(" Y="); Serial.print(y);
        Serial.print(" Z="); Serial.println(z);
      }
    } else {
      Serial.println("Failed to read sensor during calibration!");
    }
    delay(50);
  } else {
    // Check if we got valid ranges
    if ((magMaxX - magMinX) < 5 || (magMaxY - magMinY) < 5) {
      Serial.println("ERROR: Calibration failed - sensor not responding correctly!");
      Serial.println("Check wiring and I2C connection.");
      calibrating = false;
      startTime = 0;
      samples = 0;
      return;
    }

    // Compute offsets and scales
    magXoffset = (magMaxX + magMinX) / 2.0;
    magYoffset = (magMaxY + magMinY) / 2.0;
    magZoffset = (magMaxZ + magMinZ) / 2.0;

    float avgX = (magMaxX - magMinX) / 2.0;
    float avgY = (magMaxY - magMinY) / 2.0;
    float avgZ = (magMaxZ - magMinZ) / 2.0;
    avgDelta = (avgX + avgY + avgZ) / 3.0;

    magXscale = (avgX > 0.1) ? avgDelta / avgX : 1.0;
    magYscale = (avgY > 0.1) ? avgDelta / avgY : 1.0;
    magZscale = (avgZ > 0.1) ? avgDelta / avgZ : 1.0;

    Serial.print("Samples collected: "); Serial.println(samples);
    Serial.println("// Calibration values for magnetometer ");
    Serial.print("float magMinX = "); Serial.print(magMinX); Serial.println(";");
    Serial.print("float magMaxX = "); Serial.print(magMaxX); Serial.println(";");
    Serial.print("float magMinY = "); Serial.print(magMinY); Serial.println(";");
    Serial.print("float magMaxY = "); Serial.print(magMaxY); Serial.println(";");
    Serial.print("float magMinZ = "); Serial.print(magMinZ); Serial.println(";");
    Serial.print("float magMaxZ = "); Serial.print(magMaxZ); Serial.println(";");
    Serial.print("float magXoffset = "); Serial.print(magXoffset); Serial.println(";");
    Serial.print("float magYoffset = "); Serial.print(magYoffset); Serial.println(";");
    Serial.print("float magZoffset = "); Serial.print(magZoffset); Serial.println(";");
    Serial.print("float avgDelta = "); Serial.print(avgDelta); Serial.println(";");
    Serial.print("float magXscale = "); Serial.print(magXscale); Serial.println(";");
    Serial.print("float magYscale = "); Serial.print(magYscale); Serial.println(";");
    Serial.print("float magZscale = "); Serial.print(magZscale); Serial.println(";");

    if ((magMaxX - magMinX) < 40) Serial.println("Warning: Insufficient X range - redo with more rotation!");
    if ((magMaxY - magMinY) < 40) Serial.println("Warning: Insufficient Y range - redo with more rotation!");

    Serial.println("Calibration complete!");
    calibrating = false;
    startTime = 0;
    samples = 0;
  }
}

// Get compass heading in degrees (0-360)
float read_heading() {
  // Get magnetometer event
  sensors_event_t magEvent;
  if (!mag.getEvent(&magEvent)) {
    Serial.println("Sensor read failed!");
    return -1;  // Error
  }
  
  // Apply calibration (hard iron)
  float x = magEvent.magnetic.x - magXoffset;
  float y = magEvent.magnetic.y - magYoffset;
  float z = magEvent.magnetic.z - magZoffset;
  
  // Apply calibration (soft iron)
  x *= magXscale;
  y *= magYscale;
  z *= magZscale;

  // Basic validity check (magnitude should be ~25-65 uT, relaxed range)
  float magnitude = sqrt(x * x + y * y + z * z);
  if (magnitude < 15 || magnitude > 100) {
    Serial.print("Invalid magnitude: "); 
    Serial.print(magnitude);
    Serial.print(" uT (Raw: X="); Serial.print(magEvent.magnetic.x);
    Serial.print(" Y="); Serial.print(magEvent.magnetic.y);
    Serial.print(" Z="); Serial.print(magEvent.magnetic.z);
    Serial.println(")");
    return -1;  // Invalid
  }

  // Calculate heading (atan2 expects y, x for proper quadrant)
  float heading = ((atan2(y, x) * 180.0) / M_PI) - headingOffset;
  
  // Normalize to 0-360
  if (heading < 0) {
    heading = 360.0 + heading;
  }
  
  return heading;
}

void setup(void) {
  Serial.begin(115200);
  while (!Serial)
    delay(10); // will pause Zero, Leonardo, etc until serial console opens

  Serial.println("Adafruit_MMC5603 Magnetometer Test");
  Serial.println("");

  /* Initialise the sensor */
  if (!mag.begin(MMC56X3_DEFAULT_ADDRESS, &Wire)) {  // I2C mode
    /* There was a problem detecting the MMC5603 ... check your connections */
    Serial.println("Ooops, no MMC5603 detected ... Check your wiring!");
    while (1) delay(10);
  }

  Serial.println("MMC5603 initialized successfully!");
  
  // Test read to verify sensor is working
  sensors_event_t testEvent;
  if (mag.getEvent(&testEvent)) {
    Serial.print("Initial sensor test - X: "); Serial.print(testEvent.magnetic.x);
    Serial.print(" Y: "); Serial.print(testEvent.magnetic.y);
    Serial.print(" Z: "); Serial.println(testEvent.magnetic.z);
  } else {
    Serial.println("Warning: Initial sensor read failed!");
  }

  Serial.println("\nCommands:");
  Serial.println("  c - Start/stop calibration");
  Serial.println("  h - Start/stop heading display");
  Serial.println("  r - Show raw sensor values");

  lastDisplayTime = millis();
  calibrating = false;
  heading = false;
}

void loop(void)
{
  if (Serial.available() > 0) {
    char command = Serial.read();
    
    if (command == 'c') {
      calibrating = !calibrating;
      if (!calibrating) {
        Serial.println("Calibration stopped.");
      }
    }
    
    if (command == 'h') {
      heading = !heading;
      if (heading) {
        Serial.println("Starting heading display...");
      } else {
        Serial.println("Heading display stopped.");
      }
    }
    
    if (command == 'r') {
      // Show raw values for debugging
      sensors_event_t magEvent;
      if (mag.getEvent(&magEvent)) {
        Serial.print("Raw values - X: "); Serial.print(magEvent.magnetic.x);
        Serial.print(" Y: "); Serial.print(magEvent.magnetic.y);
        Serial.print(" Z: "); Serial.println(magEvent.magnetic.z);
      }
    }
  }

  if (calibrating) {
    calibrate();
  }
  
  if (heading) {
    float h = read_heading();
    if (h >= 0) {
      Serial.print("Heading: "); Serial.print(h, 1); Serial.println("°");
    }
    delay(500);
  }
}