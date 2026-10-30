import SwiftUI

// Shared components used by SpotLockSettingsView and NavSettingsView.

// MARK: - Setting Info Model

struct SettingInfo: Identifiable {
    let id = UUID()
    let title: String
    let unit: String
    let defaultValue: String
    let description: String
}

// MARK: - Info Sheet

struct InfoSheet: View {
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

struct DoubleSettingRow: View {
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

struct IntSettingRow: View {
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
