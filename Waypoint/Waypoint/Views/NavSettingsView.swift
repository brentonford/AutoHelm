import SwiftUI

struct NavSettingsView: View {
    @ObservedObject private var dataStore = DataStore.shared
    @State private var activeInfo: SettingInfo?

    private var s: Binding<NavSettings> {
        Binding(
            get: { dataStore.navSettings },
            set: { newValue in
                var v = newValue
                v.validate()
                dataStore.updateNavSettings(v)
            }
        )
    }

    var body: some View {
        List {
            arrivalSection
            speedSection
            steeringSection
            cableSection
            gpsSection
            filteringSection
            resetSection
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeInfo) { InfoSheet(info: $0) }
    }

    // MARK: - Arrival

    private var arrivalSection: some View {
        Section {
            DoubleSettingRow(
                info: SettingInfo(
                    title: "Arrival Radius",
                    unit: "m",
                    defaultValue: "5",
                    description: "Distance from the waypoint at which the boat is considered to have arrived. Navigation stops and Spot Lock engages automatically when within this radius.\n\nSet larger than SpotLock's dead zone — stopping a few metres from a GPS waypoint is fine; the Spot Lock then holds the final position. Increase if arrival triggers too far out (weak GPS); decrease if you need to stop closer."
                ),
                value: s.arrivalRadius,
                defaultValue: NavSettings.defaults.arrivalRadius,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("Arrival")
        } footer: {
            Text("The motor ramps down automatically in the final 8 m before arrival.")
        }
    }

    // MARK: - Speed Control

    private var speedSection: some View {
        Section {
            IntSettingRow(
                info: SettingInfo(
                    title: "Minimum Speed",
                    unit: "level",
                    defaultValue: "2",
                    description: "The floor speed level used during the ramp-down zone (final 8 m before arrival). Keep this low so the boat coasts in gently. The cruising speed for the full run is set per-trip in the Navigate sheet.\n\nMust be at least 1."
                ),
                value: s.minSpeed,
                defaultValue: NavSettings.defaults.minSpeed,
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
                defaultValue: NavSettings.defaults.speedChangeDelay,
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
                    defaultValue: "15",
                    description: "The angular dead band within which no steering correction fires during navigation. Wider than Spot Lock's tolerance (10°) because precise heading maintenance is less critical when moving toward a target.\n\nWiden if compass noise causes constant unwanted steering mid-transit."
                ),
                value: s.headingTolerance,
                defaultValue: NavSettings.defaults.headingTolerance,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Correction Interval",
                    unit: "s",
                    defaultValue: "1",
                    description: "Minimum time between heading correction cycles. Increase if corrections are chasing GPS noise or if the motor hasn't responded to the previous command before the next fires."
                ),
                value: s.correctionInterval,
                defaultValue: NavSettings.defaults.correctionInterval,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Small Angle Threshold",
                    unit: "°",
                    defaultValue: "30",
                    description: "Angles below this value receive a short steering pulse. Must be less than Large Angle Threshold."
                ),
                value: s.smallAngleThreshold,
                defaultValue: NavSettings.defaults.smallAngleThreshold,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Large Angle Threshold",
                    unit: "°",
                    defaultValue: "90",
                    description: "Angles above this value receive the longest steering pulse. Must be greater than Small Angle Threshold."
                ),
                value: s.largeAngleThreshold,
                defaultValue: NavSettings.defaults.largeAngleThreshold,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "Small Steering Pulse",
                    unit: "ms",
                    defaultValue: "200",
                    description: "Duration of the steering hold for small angle corrections (below Small Angle Threshold). Must be less than Medium Steering Pulse."
                ),
                value: s.smallSteeringDuration,
                defaultValue: NavSettings.defaults.smallSteeringDuration,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "Medium Steering Pulse",
                    unit: "ms",
                    defaultValue: "600",
                    description: "Duration of the steering hold for medium angle corrections. Must be between Small and Large Steering Pulse values."
                ),
                value: s.mediumSteeringDuration,
                defaultValue: NavSettings.defaults.mediumSteeringDuration,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "Large Steering Pulse",
                    unit: "ms",
                    defaultValue: "1000",
                    description: "Duration of the steering hold for large angle corrections (above Large Angle Threshold). Must be greater than Medium Steering Pulse."
                ),
                value: s.largeSteeringDuration,
                defaultValue: NavSettings.defaults.largeSteeringDuration,
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
                    description: "The cumulative steering rotation that triggers automatic cable untangle. At 720° (2 full rotations), the system steers in the opposite direction until rotation reduces to 360°."
                ),
                value: s.maxRotationBeforeUntangle,
                defaultValue: NavSettings.defaults.maxRotationBeforeUntangle,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Rotation per ms",
                    unit: "°/ms",
                    defaultValue: "0.1",
                    description: "Estimated degrees of motor rotation per millisecond of steering pulse. Used to track cumulative cable rotation for tangle prevention."
                ),
                value: s.rotationPerMs,
                defaultValue: NavSettings.defaults.rotationPerMs,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("Cable Management")
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
                    description: "Minimum number of GPS satellites required for navigation to operate. Navigation cancels automatically if quality drops below this threshold for more failures than GPS Failure Tolerance allows."
                ),
                value: s.minSatellites,
                defaultValue: NavSettings.defaults.minSatellites,
                onInfo: { activeInfo = $0 }
            )

            DoubleSettingRow(
                info: SettingInfo(
                    title: "Maximum HDOP",
                    unit: "",
                    defaultValue: "5",
                    description: "Maximum acceptable Horizontal Dilution of Precision. Values below 2.0 are excellent; 2–5 acceptable; above 5 is poor. Increase if navigation frequently cancels due to GPS quality in your environment."
                ),
                value: s.maxHDOP,
                defaultValue: NavSettings.defaults.maxHDOP,
                onInfo: { activeInfo = $0 }
            )

            IntSettingRow(
                info: SettingInfo(
                    title: "GPS Failure Tolerance",
                    unit: "failures",
                    defaultValue: "5",
                    description: "Number of consecutive GPS quality check failures before navigation automatically cancels. At a 1-second correction interval this is effectively a tolerance period in seconds."
                ),
                value: s.maxConsecutiveGpsFailures,
                defaultValue: NavSettings.defaults.maxConsecutiveGpsFailures,
                onInfo: { activeInfo = $0 }
            )
        } header: {
            Text("GPS Quality")
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
                    description: "Number of GPS position samples averaged together for distance and bearing calculations. More samples smooth out GPS jitter but slow the system's response to real movement."
                ),
                value: s.filterWindowSize,
                defaultValue: NavSettings.defaults.filterWindowSize,
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
                dataStore.updateNavSettings(NavSettings.defaults)
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle")
                    Text("Reset All to Defaults")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(dataStore.navSettings.isAllDefault)
        } footer: {
            Text("Settings take effect the next time navigation is started.")
        }
    }
}

#Preview {
    NavigationStack {
        NavSettingsView()
    }
}
