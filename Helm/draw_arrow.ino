// Draw an arrow pointing in the specified angle (in degrees)
void draw_arrow(float angle, int center_x, int center_y, int size) {
  // Convert angle to radians
  float rad_angle = angle * M_PI / 180.0;
  
  // Calculate arrow tip
  int tip_x = center_x + size * sin(rad_angle);
  int tip_y = center_y - size * cos(rad_angle);
  
  // Calculate base points for arrow
  float base_angle_1 = rad_angle + 150.0 * M_PI / 180.0;
  float base_angle_2 = rad_angle - 150.0 * M_PI / 180.0;
  
  int base_x1 = center_x + (size/2) * sin(base_angle_1);
  int base_y1 = center_y - (size/2) * cos(base_angle_1);
  
  int base_x2 = center_x + (size/2) * sin(base_angle_2);
  int base_y2 = center_y - (size/2) * cos(base_angle_2);
  
  // Draw the arrow
  display.drawLine(center_x, center_y, tip_x, tip_y, SSD1306_WHITE);
  display.drawLine(tip_x, tip_y, base_x1, base_y1, SSD1306_WHITE);
  display.drawLine(tip_x, tip_y, base_x2, base_y2, SSD1306_WHITE);
}