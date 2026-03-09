# Spot Lock Field Test Protocol

**Purpose:** Prove that Spot Lock engages correctly, maintains position within tolerance, responds to disturbances, and disengages safely.
**Pass criterion:** All PASS conditions are met. Any FAIL halts testing until root cause is resolved.

---

## Equipment Required

- Boat with electric motor fitted
- Phone running Waypoint app (BLE connected to Helm device)
- GPS-clear open water (min. 20 m clearance from structures)
- Calm conditions (< 5 knot wind, < 0.3 m swell) for initial runs
- A fixed visual reference on shore (dock piling, buoy, marker)
- Tape measure or rangefinder optional but useful
- Second person to observe and record (recommended)

---

## Pre-Test Checklist

Before running any test case, confirm ALL of the following:

| # | Check | Expected |
|---|-------|----------|
| 1 | BLE connection status | **Connected** (green dot on Helm tab) |
| 2 | GPS signal quality | **Good** or **Excellent** (GPS indicator in toolbar) |
| 3 | Satellite count | ≥ 6 satellites |
| 4 | HDOP | < 2.0 |
| 5 | Motor is ON | Confirmed physically |
| 6 | Motor speed at 0 | Confirmed before each engagement |
| 7 | Spot Lock settings | All defaults (tap Reset All in Settings → Spot Lock) |
| 8 | App is on Helm tab | Spot Lock section visible |

---

## Test Cases

---

### TC-01 — Engagement & Initial State

**Objective:** Confirm Spot Lock engages at the current position and reports correctly.

**Steps:**
1. Bring the boat to a complete stop.
2. Note the boat's position relative to the visual shore reference.
3. Tap **Engage at Current Position** → confirm alert → tap **Continue**.
4. Observe the app for 10 seconds without touching anything.

**Expected / PASS:**
- Status changes to **Active** (green dot).
- Distance from Lock reads **< 1.5 m** immediately after engage.
- Thrust shows **Inactive** (boat is within dead zone).
- Log prints: `ENGAGED at [lat], [lon]`
- No motor commands are sent in the first 10 seconds (boat is stationary within dead zone).

**FAIL indicators:**
- Status stays Inactive.
- Distance from Lock reads > 3 m at engage (GPS drift — wait for better fix).
- Motor starts immediately after engage when boat is stationary.

---

### TC-02 — Dead Zone Hold (No Thrust)

**Objective:** Confirm the motor stays off while the boat remains inside the 2 m dead zone.

**Steps:**
1. With Spot Lock active, allow the boat to drift naturally for 60 seconds.
2. Watch the Distance from Lock readout continuously.

**Expected / PASS:**
- If Distance from Lock stays ≤ 2.0 m for the full 60 seconds:
  - Thrust remains **Inactive** the entire time.
  - Motor makes no sound/movement.
- Note the maximum drift distance observed.

**FAIL indicators:**
- Motor activates while Distance from Lock < 2.0 m.
- Distance from Lock immediately reads > 4 m (GPS jump — retest after signal stabilises).

---

### TC-03 — Drift Correction (Thrust Activation)

**Objective:** Confirm the motor activates when the boat drifts beyond the activation threshold and returns the boat to the lock point.

**Steps:**
1. With Spot Lock active, manually push the boat ~5 m away from the lock point (use a pole, paddle, or motor off-axis — not the Spot Lock motor).
2. Release. Do not touch the boat.
3. Observe for up to 90 seconds.

**Expected / PASS:**
- Once Distance from Lock exceeds **4.0 m**, Thrust changes to **Active**.
- Motor engages and boat begins moving toward the lock point.
- Distance from Lock decreases over time.
- Within 90 seconds, Distance from Lock returns to **< 2.0 m**.
- Thrust then changes back to **Inactive**.

**FAIL indicators:**
- Motor does not engage after crossing 4.0 m threshold.
- Boat moves away from lock point instead of toward it (check compass calibration).
- Distance from Lock does not decrease after 30 seconds of active thrust.

---

### TC-04 — Proportional Speed Scaling

**Objective:** Confirm that motor speed is lower when close to the lock point and higher when far away.

**Steps:**
1. With Spot Lock active, note Speed Level when Distance from Lock is 4–5 m.
2. Push the boat to ~8 m from lock point.
3. Note Speed Level.

**Expected / PASS:**
- Speed Level at 4–5 m: **3–5** (near minimum).
- Speed Level at 8 m: **higher than at 4–5 m** (proportional scaling).
- Speed Level never exceeds **10** (maximum).

**FAIL indicators:**
- Speed Level is identical regardless of distance.
- Speed Level immediately jumps to maximum at any distance.

---

### TC-05 — Heading Correction (Steering)

**Objective:** Confirm Spot Lock steers the boat toward the lock bearing, not just applies thrust.

**Steps:**
1. Engage Spot Lock facing directly away from the lock point (180° off bearing).
2. Observe the Relative Angle readout on the Helm tab.
3. Allow Spot Lock to correct for 30 seconds.

**Expected / PASS:**
- Relative Angle starts near ±180°.
- A steering command fires within the first correction interval (1 second).
- Log shows `RF_LEFT_HOLD` or `RF_RIGHT_HOLD` followed by `RF_RELEASE`.
- Relative Angle decreases toward 0° over subsequent cycles.
- Bearing to Lock indicator points toward the lock position.

**FAIL indicators:**
- No steering commands in Recent Commands.
- Boat applies thrust in wrong direction (compass calibration issue).
- Relative Angle does not change after multiple correction cycles.

---

### TC-06 — Jog Controls

**Objective:** Confirm the jog buttons move the lock point in the correct compass direction.

**Steps:**
1. With Spot Lock active and boat stationary, note current lock point coordinates (lat/lon shown in active header).
2. Press and hold **N** (forward) jog button for 1 second. Release.
3. Note new lock point coordinates.
4. Repeat for **S**, **E**, **W** buttons.

**Expected / PASS:**
- Jog N: latitude **increases** by ~0.000013° (~1.5 m).
- Jog S: latitude **decreases**.
- Jog E: longitude **increases**.
- Jog W: longitude **decreases**.
- Each jog moves the lock point by approximately **1.5 m**.
- Position history clears after jog (boat will re-approach new point).

**FAIL indicators:**
- Lock point coordinates do not change after jog.
- Movement direction does not match compass direction (N/S/E/W mislabelled).

---

### TC-07 — GPS Quality Failure Handling

**Objective:** Confirm Spot Lock disengages safely when GPS quality drops below threshold.

> ⚠️ This test requires temporarily blocking the GPS antenna. Conduct in a safe location where motor activation will not cause danger.

**Steps:**
1. With Spot Lock active, cover the Helm device's GPS antenna (hand, metal sheet, or move it inside a shielded enclosure) to cause a GPS loss.
2. Observe the app.

**Expected / PASS:**
- App logs `GPS quality check failed` once per second.
- After **5 consecutive failures** (default tolerance), app logs `GPS quality insufficient - disengaging`.
- Spot Lock **disengages** (status goes Inactive).
- Motor stops.

**FAIL indicators:**
- Spot Lock remains active with no GPS data for > 10 seconds.
- Motor continues running after disengage.

---

### TC-08 — BLE Disconnect Grace Period

**Objective:** Confirm Spot Lock continues running through a brief BLE dropout and disengages after the grace period expires.

**Steps:**
1. With Spot Lock active, turn off Bluetooth on the phone (Settings → Bluetooth off) to simulate a BLE disconnect.
2. Immediately note the time.
3. After 3 seconds, turn Bluetooth back on. Observe reconnection.
4. Repeat step 1, but this time wait 8 seconds before reconnecting.

**Expected / PASS (3-second drop):**
- App shows BLE as disconnected.
- Spot Lock status **remains Active** (grace period not expired).
- When BLE reconnects, grace period timer is cancelled. Normal operation resumes.

**Expected / PASS (8-second drop, exceeds 5 s grace period):**
- After 5 seconds, log prints `Grace period expired - disengaging`.
- Spot Lock **disengages** and motor stops.
- Reconnecting BLE does not re-engage Spot Lock automatically.

**FAIL indicators:**
- Spot Lock disengages immediately on BLE disconnect (< 1 s).
- Spot Lock remains active 10+ seconds after BLE disconnect.

---

### TC-09 — Manual Override Disengagement

**Objective:** Confirm that pressing any manual motor control button immediately disengages Spot Lock.

**Steps:**
1. With Spot Lock active, press the **+** (speed up) button in Manual Remote Control.
2. Observe Spot Lock status.

**Expected / PASS:**
- Spot Lock status changes to **Inactive** immediately.
- Log shows `DISENGAGING` then `DISENGAGED`.
- Motor returns to manual control.

**FAIL indicators:**
- Spot Lock remains Active after manual button press.

---

### TC-10 — Manual Disengage Button

**Objective:** Confirm the Disengage button safely stops thrust and steering before going inactive.

**Steps:**
1. Push the boat to ~6 m from lock point so thrust is Active.
2. While motor is running, tap **Disengage Spot Lock**.

**Expected / PASS:**
- Log shows `DISENGAGING...`
- Motor ramps down to 0 (`RF_DOWN` commands sent).
- Any active steering is released (`RF_RELEASE` sent).
- Status changes to **Inactive**.
- Log shows `DISENGAGED`.
- All in < 15 seconds.

**FAIL indicators:**
- Motor continues running after status shows Inactive.
- App shows "Disengaging..." indefinitely.

---

### TC-11 — Position Hold Under Sustained Wind/Current

**Objective:** Confirm Spot Lock maintains position over an extended period with environmental load.

> Requires moderate wind (5–15 knots) or noticeable current.

**Steps:**
1. Engage Spot Lock.
2. Note the visual shore reference bearing.
3. Leave Spot Lock running for **5 minutes** without touching the app.
4. At end of 5 minutes, note position relative to shore reference.

**Expected / PASS:**
- Boat never drifts more than **5 m** from shore reference for more than 30 consecutive seconds.
- Motor cycles on and off as expected (not continuously full-throttle).
- App log shows no `WARNING: Drifting away` messages persisting for > 60 seconds.

**FAIL indicators:**
- Boat drifts > 10 m from shore reference and does not return within 2 minutes.
- Continuous full-throttle with no position improvement (check heading calibration, motor power).

---

## Result Summary Sheet

| Test | Conditions | Result | Notes |
|------|-----------|--------|-------|
| TC-01 Engagement | | PASS / FAIL | |
| TC-02 Dead Zone Hold | | PASS / FAIL | |
| TC-03 Drift Correction | | PASS / FAIL | |
| TC-04 Proportional Speed | | PASS / FAIL | |
| TC-05 Heading Correction | | PASS / FAIL | |
| TC-06 Jog Controls | | PASS / FAIL | |
| TC-07 GPS Failure | | PASS / FAIL | |
| TC-08 Disconnect Grace | | PASS / FAIL | |
| TC-09 Manual Override | | PASS / FAIL | |
| TC-10 Manual Disengage | | PASS / FAIL | |
| TC-11 Sustained Hold | | PASS / FAIL | |

---

## Common Failure Causes

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| Motor always pushing wrong direction | Heading offset uncalibrated | Settings → North Calibration |
| Motor never activates | Speed at 0 before engage? Motor not ON? | Verify motor state pre-engage |
| Rapid engage/disengage cycling | GPS jitter larger than dead zone | Increase Dead Zone Radius or Filter Window Size |
| Boat spirals instead of heading to lock | Large accumulated cable rotation | Reduce session time; check Rotation per ms setting |
| Spot Lock disengages mid-session | GPS dropout or poor satellite geometry | Move to open water; check HDOP in GPS Status |
