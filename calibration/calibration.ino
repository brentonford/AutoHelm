#include <Adafruit_MMC56x3.h>

/* Assign a unique ID to this sensor at the same time */
Adafruit_MMC5603 mag = Adafruit_MMC5603(12345);

float MagMinX, MagMaxX;
float MagMinY, MagMaxY;
float MagMinZ, MagMaxZ;

long lastDisplayTime;

void setup(void) {
  Serial.begin(9600);
  while (!Serial)
    delay(10); // will pause Zero, Leonardo, etc until serial console opens

  Serial.println("Adafruit_MMC5603 Magnetometer Calibration");
  Serial.println("");

  /* Initialise the sensor */
  if (!mag.begin(MMC56X3_DEFAULT_ADDRESS, &Wire1)) {  // I2C mode
    /* There was a problem detecting the MMC5603 ... check your connections */
    Serial.println("Ooops, no MMC5603 detected ... Check your wiring!");
    while (1) delay(10);
  }

  lastDisplayTime = millis();
  MagMinX = MagMaxX = MagMinY = MagMaxY = MagMinZ = MagMaxZ = 0;
}

void loop(void)
{
  /* Get a new sensor event */
  sensors_event_t magEvent;

  mag.getEvent(&magEvent);

  if (magEvent.magnetic.x < MagMinX) MagMinX = magEvent.magnetic.x;
  if (magEvent.magnetic.x > MagMaxX) MagMaxX = magEvent.magnetic.x;

  if (magEvent.magnetic.y < MagMinY) MagMinY = magEvent.magnetic.y;
  if (magEvent.magnetic.y > MagMaxY) MagMaxY = magEvent.magnetic.y;

  if (magEvent.magnetic.z < MagMinZ) MagMinZ = magEvent.magnetic.z;
  if (magEvent.magnetic.z > MagMaxZ) MagMaxZ = magEvent.magnetic.z;

  if ((millis() - lastDisplayTime) > 1000)  // display once/second
  {
      Serial.println("// Calibration values for magnetometer");
      Serial.print("float magXmax = "); Serial.print(MagMaxX, 2); Serial.println(";");
      Serial.print("float magYmax = "); Serial.print(MagMaxY, 2); Serial.println(";");
      Serial.print("float magZmax = "); Serial.print(MagMaxZ, 2); Serial.println(";");
      Serial.print("float magXmin = "); Serial.print(MagMinX, 2); Serial.println(";");
      Serial.print("float magYmin = "); Serial.print(MagMinY, 2); Serial.println(";");
      Serial.print("float magZmin = "); Serial.print(MagMinZ, 2); Serial.println(";");
      Serial.println();
      lastDisplayTime = millis();
  }
}