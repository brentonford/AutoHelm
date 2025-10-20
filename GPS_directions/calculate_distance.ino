// Function to calculate distance between two GPS coordinates
float calculate_distance(float lat1, float lon1, float lat2, float lon2) {
  // Convert decimal degrees to radians
  lat1 = lat1 * M_PI / 180.0;
  lon1 = lon1 * M_PI / 180.0;
  lat2 = lat2 * M_PI / 180.0;
  lon2 = lon2 * M_PI / 180.0;
  
  // Haversine formula
  float dlat = lat2 - lat1;
  float dlon = lon2 - lon1;
  float a = sin(dlat/2) * sin(dlat/2) + cos(lat1) * cos(lat2) * sin(dlon/2) * sin(dlon/2);
  float c = 2 * atan2(sqrt(a), sqrt(1-a));
  
  // Earth radius in meters
  float r = 6371000;
  float distance = c * r;
  return distance;
}