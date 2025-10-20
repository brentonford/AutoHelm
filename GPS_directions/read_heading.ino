// Get compass heading in degrees (0-360)
float read_heading() {
  // Get magnetometer event
  sensors_event_t event;
  compass.getEvent(&event);
  
  // Apply calibration (hard iron)
  float x = event.magnetic.x - magXoffset;
  float y = event.magnetic.y - magYoffset;
  float z = event.magnetic.z - magZoffset;
  
  // Apply calibration (soft iron)
  x *= magXscale;
  y *= magYscale;
  z *= magZscale;

  // Calculate heading
  float heading = (atan2(-x, y) * 180.0) / M_PI;
  
  // Normalize to 0-360
  if (heading < 0) {
    heading = 360.0 + heading;
  }
  
  return heading;
}