void adjustHeading(float relativeAngle) {
    // Prevent rapid corrections
    unsigned long currentTime = millis();
    if (currentTime - lastCorrectionTime < MIN_CORRECTION_INTERVAL) {
        return;
    }
    
    // Normalize relative angle to -180 to +180
    if (relativeAngle > 180.0) {
        relativeAngle -= 360.0;
    }
    
    // Determine if we need to turn and which direction
    if (abs(relativeAngle) > HEADING_TOLERANCE) {
        if (relativeAngle > 0) {
            // Turn right
            Serial.print("Turning RIGHT (off by ");
            Serial.print(relativeAngle);
            Serial.println(" degrees)");
            watersnakeRFController.transmitRight(5);
        } else {
            // Turn left
            Serial.print("Turning LEFT (off by ");
            Serial.print(abs(relativeAngle));
            Serial.println(" degrees)");
            watersnakeRFController.transmitLeft(5);
        }
        
        lastCorrectionTime = currentTime;
    } else {
        Serial.println("On course!");
    }
}