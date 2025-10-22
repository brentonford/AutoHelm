void adjustHeading(float relativeAngle, WatersnakeRFController& remote) {
    static unsigned long lastAdjustment = 0;
    unsigned long currentTime = millis();
    
    if (currentTime - lastAdjustment < 5000) {
        return;
    }
    
    if (relativeAngle > 5 && relativeAngle < 181) {
        Serial.println("Adjust Heading: sendRight. ");
        remote.sendRight();
        lastAdjustment = currentTime;
        return;
    }
    
    if (relativeAngle < 355 && relativeAngle > 180) {
        Serial.println("Adjust Heading: sendLeft. ");
        remote.sendLeft();
        lastAdjustment = currentTime;
        return;
    }
}