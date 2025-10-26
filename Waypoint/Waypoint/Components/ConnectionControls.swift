import SwiftUI
import CoreBluetooth

// MARK: - Connection Section View
struct ConnectionSectionView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 12) {
            if bluetoothManager.isConnected {
                ConnectedDeviceView(bluetoothManager: bluetoothManager)
            } else {
                DisconnectedDeviceView(bluetoothManager: bluetoothManager)
            }
        }
    }
}

// MARK: - Connected Device View
struct ConnectedDeviceView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 8) {
            ConnectionStatusRow(bluetoothManager: bluetoothManager)
            DisconnectButton(bluetoothManager: bluetoothManager)
        }
    }
}

// MARK: - Disconnected Device View
struct DisconnectedDeviceView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 12) {
            if !bluetoothManager.discoveredDevices.isEmpty {
                DeviceListView(bluetoothManager: bluetoothManager)
            } else {
                ScanningIndicatorView()
            }
        }
    }
}

// MARK: - Connection Status Row
struct ConnectionStatusRow: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Connected")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("(\(bluetoothManager.signalStrength) dBm)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
    }
}

// MARK: - Disconnect Button
struct DisconnectButton: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        Button(action: {
            bluetoothManager.disconnect()
        }) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                Text("Disconnect")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(6)
        }
    }
}

// MARK: - Device List View
struct DeviceListView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Available Devices")
                .font(.caption)
                .foregroundColor(.gray)
            
            ForEach(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                DeviceRow(device: device, bluetoothManager: bluetoothManager)
            }
        }
    }
}

// MARK: - Device Row
struct DeviceRow: View {
    let device: CBPeripheral
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        Button(action: {
            bluetoothManager.connect(to: device)
        }) {
            HStack {
                Image(systemName: "sensor")
                    .foregroundColor(.blue)
                Text(device.name ?? "Unknown Device")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(6)
        }
    }
}

// MARK: - Scanning Indicator View
struct ScanningIndicatorView: View {
    var body: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(0.8)
            Text("Scanning for devices...")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Navigation Control Section
struct NavigationControlSection: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var navigationEnabled: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Navigation Control")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Toggle("", isOn: $navigationEnabled)
                    .onChange(of: navigationEnabled) { oldValue, newValue in
                        bluetoothManager.setNavigationEnabled(newValue)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            NavigationStatusIndicator(enabled: navigationEnabled)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Navigation Status Indicator
struct NavigationStatusIndicator: View {
    let enabled: Bool
    
    var body: some View {
        HStack {
            Image(systemName: enabled ? "location.fill" : "location.slash")
                .foregroundColor(enabled ? .green : .red)
            Text(enabled ? "Navigation Active" : "Navigation Disabled")
                .font(.caption)
                .foregroundColor(enabled ? .green : .red)
            Spacer()
        }
    }
}