// Function to calculate bearing between two GPS coordinates
float calculate_bearing(float lat1, float lon1, float lat2, float lon2) {
  // Convert decimal degrees to radians
  lat1 = lat1 * M_PI / 180.0;
  lon1 = lon1 * M_PI / 180.0;
  lat2 = lat2 * M_PI / 180.0;
  lon2 = lon2 * M_PI / 180.0;
  
  // Calculate the bearing
  float dlon = lon2 - lon1;
  float y = sin(dlon) * cos(lat2);
  float x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon);
  float initial_bearing = atan2(y, x);
  
  // Convert from radians to degrees
  initial_bearing = initial_bearing * 180.0 / M_PI;
  float bearing = fmod((initial_bearing + 360.0), 360.0);
  return bearing;
}