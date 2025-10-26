// Nautical-themed notification sounds for Helm device
// Piezo buzzer connected to digital pin 8

const int BUZZER_PIN = 8;

// Note frequencies (in Hz) for nautical themes
const int NOTE_C4 = 262;
const int NOTE_D4 = 294;
const int NOTE_E4 = 330;
const int NOTE_F4 = 349;
const int NOTE_G4 = 392;
const int NOTE_A4 = 440;
const int NOTE_B4 = 494;
const int NOTE_C5 = 523;
const int NOTE_D5 = 587;
const int NOTE_E5 = 659;

// Low frequency tones for ship horn effects
const int HORN_LOW = 150;
const int HORN_MID = 200;
const int HORN_HIGH = 250;

// Sonar ping frequency
const int SONAR_PING = 800;

void playTone(int frequency, int duration) {
    if (frequency > 0) {
        tone(BUZZER_PIN, frequency, duration);
    }
    delay(duration);
}

void playNavigationEnabled() {
    // Positive ascending nautical horn sequence (like ship departure)
    playTone(HORN_LOW, 200);
    delay(50);
    playTone(HORN_MID, 200);
    delay(50);
    playTone(HORN_HIGH, 400);
    delay(100);
    playTone(NOTE_G4, 150);
    playTone(NOTE_C5, 300);
}

void playWaypointSet() {
    // Confirmation sequence like sonar acknowledgment
    playTone(SONAR_PING, 100);
    delay(100);
    playTone(SONAR_PING, 100);
    delay(50);
    playTone(NOTE_A4, 150);
    playTone(NOTE_C5, 200);
    playTone(NOTE_E5, 250);
}

void playGpsFixLost() {
    // Descending alarm like fog horn warning
    playTone(NOTE_C5, 300);
    delay(100);
    playTone(NOTE_A4, 300);
    delay(100);
    playTone(NOTE_F4, 300);
    delay(100);
    playTone(HORN_LOW, 800);
    delay(200);
    playTone(HORN_LOW, 400);
}

void playGpsFixed() {
    // Recovery sequence like lighthouse beacon
    for (int i = 0; i < 3; i++) {
        playTone(SONAR_PING, 80);
        delay(120);
    }
    delay(100);
    playTone(NOTE_C4, 150);
    playTone(NOTE_E4, 150);
    playTone(NOTE_G4, 150);
    playTone(NOTE_C5, 300);
}

void playAppConnected() {
    // Positive connection tune like ship's bell sequence
    playTone(NOTE_G4, 120);
    playTone(NOTE_C5, 120);
    delay(80);
    playTone(NOTE_E5, 120);
    playTone(NOTE_G4, 120);
    delay(80);
    playTone(NOTE_C5, 200);
    playTone(NOTE_E5, 300);
}

void playAppDisconnected() {
    // Negative disconnection like ship horn farewell
    playTone(NOTE_E4, 200);
    delay(50);
    playTone(NOTE_C4, 200);
    delay(100);
    playTone(HORN_MID, 400);
    delay(100);
    playTone(HORN_LOW, 600);
}

void playDestinationReached() {
    // Victory sequence like harbor arrival
    playTone(NOTE_C5, 150);
    playTone(NOTE_D5, 150);
    playTone(NOTE_E5, 150);
    delay(100);
    playTone(NOTE_C5, 150);
    playTone(NOTE_D5, 150);
    playTone(NOTE_E5, 150);
    delay(100);
    playTone(NOTE_G4, 200);
    playTone(NOTE_C5, 400);
}