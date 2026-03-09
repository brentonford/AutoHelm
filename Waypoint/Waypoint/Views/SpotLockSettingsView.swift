import SwiftUI

// MARK: - Setting Info Model

struct SettingInfo: Identifiable {
    let id = UUID()
    let title: String
    let unit: String
    let defaultValue: String
    let description: String
}

// MARK: - Info Sheet

private struct InfoSheet: View {
    let info: SettingInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(info.title)
                            .font(.title2.bold())
                        if !info.unit.isEmpty {
                            Text("(\(info.unit))")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "dial.low")
                            .foregroundColor(.blue)
                        Text("Default: \(info.defaultValue)\(info.unit.isEmpty ? "" : " \(info.unit)")")
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                    }
                    .padding(10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    Text(info.description)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Double Setting Row

private struct DoubleSettingRow: View {
    let info: SettingInfo
    @Binding var value: Double
    let defaultValue: Double
    let onInfo: (SettingInfo) -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    private var isDefault: Bool { abs(value - defaultValue) < 0.0001 }

    var body: some View {
        HStack(spacing: 10) {
            Button { onInfo(info) } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Text(info.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            TextField("", text: $editText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onTapGesture { isFocused = true }

            Text(info.unit)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(minWidth: 28, alignment: .leading)

            Button { value = defaultValue } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .opacity(isDefault ? 0 : 1)
            .frame(width: 22)
        }
        .onAppear { editText = format(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused { editText = format(newValue) }
        }
    }

    private func commit() {
        let cleaned = editText.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(cleaned), parsed.isFinite {
            value = parsed
        }
        editText = format(value)
    }

    private func format(_ v: Double) -> String { String(format: "%g", v) }
}

// MARK: - Int Setting Row

private struct IntSettingRow: View {
    let info: SettingInfo
    @Binding var value: Int
    let defaultValue: Int
    let onInfo: (SettingInfo) -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    private var isDefault: Bool { value == defaultValue }

    var body: some View {
        HStack(spacing: 10) {
            Button { onInfo(info) } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Text(info.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            TextField("", text: $editText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onTapGesture { isFocused = true }

            Text(info.unit)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(minWidth: 28, alignment: .leading)

            Button { value = defaultValue } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .opacity(isDefault ? 0 : 1)
            .frame(width: 22)
        }
        .onAppear { editText = String(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused { editText = String(newValue) }
        }
    }

    private func commit() {
        if let parsed = Int(editText.trimmingCharacters(in: .whitespaces)), parsed > 0 {
            value = parsed
        }
        editText = String(value)
    }
}

// MARK: - Main View

struct SpotLockSettingsView: View {
    @ObservedObject private var dataStore = DataStore.shared
    @State private var activeInfo: SettingInfo?

    /// A binding that validates and persists on every write.
    private var s: Binding<SpotLockSettings> {
        Binding(
            get: { dataStore.spotLockSettings },
            set: { newValue in
                var v = newValue
                v.validate()
                dataStore.updateSpotLockSettings(v)
            }
        )
    }

    var body: some View {
        List {
            positionSection
            speedSection
            steeringSection
            cableSection
            gpsSection
            connectivitySection
            filteringSection
            resetSection
        }
        .navigationTitle("Spot Lock")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeInfo) { InfoSheet(info: $0) }
    }

    // MARK: - Position Control

    private var positionSection: some View {
        Section {
            DoubleSettingRow(
                info: SettingInfo(
                    title: "Dead Zone Radius",
                    unit: "m",
                    defaultValue: "2",
                    description: "The radius around the lock point where thrust stops. When the boat is within this circle the motor is stopped.\n\nIncrease if the boat overshoots and oscillates back and forth through the lock point. Decrease if it drifts too far before stopping.\n\nMust be at least 0.5 m less than Activation Threshold."
                ),
                value: s.deadZoneRadius,
                defaultValue: SpotLockSettings.defaults.deadZoneRadius,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Activation Threshold",
                    unit: "m",
                    defaultValue: "4",
                    description: "The distance from the lock point at which thrust re-activates after stopping. The gap between this and Dead Zone Radius is the hysteresis band — it prevents the motor from cycling on and off constantly.\n\nMust be at least 0.5 m greater than Dead Zone Radius."
                ),
                value: s.activationThreshold,
                defaultValue: SpotLockSettings.defaults.activationThreshold,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Jog Distance",
                    unit: "m",
                    defaultValue: "1.5",
                    description: "How far the lock point moves per jog button hold tick. Smaller values give finer control in tight marina berths. Larger values allow faster repositioning on open water."
                ),
                value: s.jogDistance,
                defaultValue: SpotLockSettings.defaults.jogDistance,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("Position Control")
        }
    }

    // MARK: - Speed Control

    private var speedSection: some View {
        Section {
            IntSettingRow(
                info: SettingInfo(
                    title: "Minimum Speed",
                    unit: "level",
                    defaultValue: "3",
                    description: "The floor speed level when thrust is active. Set this to the lowest level that actually moves your boat against normal conditions. Too low and the motor won't overcome drag or current; too high causes overshoot when close to the lock point.\n\nMust be at least 1 less than Maximum Speed."
                ),
                value: s.minSpeed,
                defaultValue: SpotLockSettings.defaults.minSpeed,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "Maximum Speed",
                    unit: "level",
                    defaultValue: "10",
                    description: "The ceiling speed level Spot Lock will use. Reduce in calm conditions to save battery and prevent overshoot. Use the full range in strong current or wind.\n\nMust be at least 1 greater than Minimum Speed."
                ),
                value: s.maxSpeed,
                defaultValue: SpotLockSettings.defaults.maxSpeed,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Proportional Gain",
                    unit: "×",
                    defaultValue: "1",
                    description: "Controls how aggressively motor speed increases with distance beyond the dead zone. At 1.0, each extra metre of drift adds one speed level above the minimum. Increase for faster response in current or wind; decrease for calmer conditions where gentler corrections prevent overshoot."
                ),
                value: s.proportionalGain,
                defaultValue: SpotLockSettings.defaults.proportionalGain,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Speed Step Delay",
                    unit: "s",
                    defaultValue: "2",
                    description: "The pause between each motor speed level step during ramp-up or ramp-down. Increase if your motor controller fails to register rapid step commands. Decrease for faster speed changes on responsive motors."
                ),
                value: s.speedChangeDelay,
                defaultValue: SpotLockSettings.defaults.speedChangeDelay,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("Speed Control")
        }
    }

    // MARK: - Steering

    private var steeringSection: some View {
        Section {
            DoubleSettingRow(
                info: SettingInfo(
                    title: "Heading Tolerance",
                    unit: "°",
                    defaultValue: "10",
                    description: "The angular dead band within which no steering correction fires. Wider tolerance means less steering activity and less cable wear, but the boat wanders further off bearing before correcting. Narrower gives tighter alignment at the cost of more corrections.\n\nWiden this value if compass noise causes constant unwanted steering."
                ),
                value: s.headingTolerance,
                defaultValue: SpotLockSettings.defaults.headingTolerance,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Correction Interval",
                    unit: "s",
                    defaultValue: "1",
                    description: "Minimum time between correction cycles. Increase if corrections are chasing GPS noise or if the motor hasn't had time to respond to the previous command before the next fires. Decrease for faster response on accurate GPS in calm conditions."
                ),
                value: s.correctionInterval,
                defaultValue: SpotLockSettings.defaults.correctionInterval,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Small Angle Threshold",
                    unit: "°",
                    defaultValue: "30",
                    description: "Angles below this value receive a short steering pulse. Angles between this and Large Angle Threshold receive a medium pulse. Adjust based on how sharply your motor turns at your chosen speed levels.\n\nMust be less than Large Angle Threshold."
                ),
                value: s.smallAngleThreshold,
                defaultValue: SpotLockSettings.defaults.smallAngleThreshold,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Large Angle Threshold",
                    unit: "°",
                    defaultValue: "90",
                    description: "Angles above this value receive the longest steering pulse. Angles between Small Angle Threshold and this value receive a medium pulse.\n\nMust be greater than Small Angle Threshold."
                ),
                value: s.largeAngleThreshold,
                defaultValue: SpotLockSettings.defaults.largeAngleThreshold,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "Small Steering Pulse",
                    unit: "ms",
                    defaultValue: "200",
                    description: "Duration of the steering hold for small angle corrections (below Small Angle Threshold). This is the most critical tuning value — set it to the minimum duration that produces a noticeable turn without overshooting a small correction on your specific motor.\n\nMust be less than Medium Steering Pulse."
                ),
                value: s.smallSteeringDuration,
                defaultValue: SpotLockSettings.defaults.smallSteeringDuration,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "Medium Steering Pulse",
                    unit: "ms",
                    defaultValue: "600",
                    description: "Duration of the steering hold for medium angle corrections (between Small and Large Angle Threshold).\n\nMust be between Small and Large Steering Pulse values."
                ),
                value: s.mediumSteeringDuration,
                defaultValue: SpotLockSettings.defaults.mediumSteeringDuration,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "Large Steering Pulse",
                    unit: "ms",
                    defaultValue: "1000",
                    description: "Duration of the steering hold for large angle corrections (above Large Angle Threshold). For very large heading errors the boat may not fully correct in one pulse — subsequent correction cycles will continue adjusting.\n\nMust be greater than Medium Steering Pulse."
                ),
                value: s.largeSteeringDuration,
                defaultValue: SpotLockSettings.defaults.largeSteeringDuration,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("Steering")
        }
    }

    // MARK: - Cable Management

    private var cableSection: some View {
        Section {
            DoubleSettingRow(
                info: SettingInfo(
                    title: "Max Rotation",
                    unit: "°",
                    defaultValue: "720",
                    description: "The cumulative steering rotation that triggers automatic cable untangle. At 720° (2 full rotations), the system forces steering in the opposite direction until rotation reduces back to 360°. Lower this for shorter or stiffer cables that tangle more easily."
                ),
                value: s.maxRotationBeforeUntangle,
                defaultValue: SpotLockSettings.defaults.maxRotationBeforeUntangle,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Rotation per ms",
                    unit: "°/ms",
                    defaultValue: "0.1",
                    description: "Estimated degrees of motor rotation per millisecond of steering pulse. Used to track cumulative cable rotation for tangle prevention.\n\nIncrease if the system does not trigger untangle cycles often enough; decrease if it triggers them too frequently. Varies by motor model, prop load, and speed level."
                ),
                value: s.rotationPerMs,
                defaultValue: SpotLockSettings.defaults.rotationPerMs,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("Cable Management")
        } footer: {
            Text("The system auto-unwinds when cumulative rotation exceeds Max Rotation, steering opposite until back to 360°.")
        }
    }

    // MARK: - GPS Quality

    private var gpsSection: some View {
        Section {
            IntSettingRow(
                info: SettingInfo(
                    title: "Minimum Satellites",
                    unit: "sats",
                    defaultValue: "4",
                    description: "Minimum number of GPS satellites required for Spot Lock to operate or continue operating. Lower values allow operation with weaker signal but reduce position accuracy. Increase to 6 or more for tighter position holding when GPS geometry is good."
                ),
                value: s.minSatellites,
                defaultValue: SpotLockSettings.defaults.minSatellites,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Maximum HDOP",
                    unit: "",
                    defaultValue: "5",
                    description: "Maximum acceptable Horizontal Dilution of Precision. Lower values require better GPS geometry before Spot Lock will operate. Values below 2.0 are excellent; 2–5 is acceptable; above 5 is poor.\n\nIncrease if Spot Lock frequently disengages due to GPS quality in your environment."
                ),
                value: s.maxHDOP,
                defaultValue: SpotLockSettings.defaults.maxHDOP,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "GPS Failure Tolerance",
                    unit: "failures",
                    defaultValue: "5",
                    description: "Number of consecutive GPS quality check failures before Spot Lock automatically disengages. At a 1-second correction interval this is effectively a tolerance period in seconds.\n\nIncrease in environments with intermittent satellite view (trees, bridges, docks). Decrease for safety-critical use."
                ),
                value: s.maxConsecutiveGpsFailures,
                defaultValue: SpotLockSettings.defaults.maxConsecutiveGpsFailures,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("GPS Quality")
        }
    }

    // MARK: - Connectivity

    private var connectivitySection: some View {
        Section {
            DoubleSettingRow(
                info: SettingInfo(
                    title: "Disconnect Grace Period",
                    unit: "s",
                    defaultValue: "5",
                    description: "How long Spot Lock continues operating after BLE connection to the Helm is lost. This allows brief dropouts in RF-noisy environments (near other vessels, docks, marinas) without disengaging. The motor continues running autonomously during this period.\n\nBalance convenience against safety for your situation."
                ),
                value: s.disconnectGracePeriodSeconds,
                defaultValue: SpotLockSettings.defaults.disconnectGracePeriodSeconds,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("Connectivity")
        }
    }

    // MARK: - Position Filtering

    private var filteringSection: some View {
        Section {
            IntSettingRow(
                info: SettingInfo(
                    title: "Filter Window Size",
                    unit: "samples",
                    defaultValue: "5",
                    description: "Number of GPS position samples averaged together for distance and bearing calculations. More samples smooth out GPS jitter but slow the system's response to real drift. Fewer samples are more reactive but may trigger corrections that chase noise.\n\nIncrease near structures that cause GPS multipath interference."
                ),
                value: s.filterWindowSize,
                defaultValue: SpotLockSettings.defaults.filterWindowSize,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("Position Filtering")
        }
    }

    // MARK: - Reset All

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                dataStore.updateSpotLockSettings(SpotLockSettings.defaults)
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle")
                    Text("Reset All to Defaults")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(dataStore.spotLockSettings.isAllDefault)
        } footer: {
            Text("Settings take effect the next time Spot Lock is engaged.")
        }
    }
}

#Preview {
    NavigationStack {
        SpotLockSettingsView()
    }
}
