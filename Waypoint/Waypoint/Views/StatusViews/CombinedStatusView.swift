import SwiftUI
import CoreBluetooth

// MARK: - Combined Status View
struct CombinedStatusView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var isConnectionSectionExpanded = false
    @State private var navigationEnabled = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                ConnectionSection(
                    bluetoothManager: bluetoothManager,
                    isExpanded: $isConnectionSectionExpanded
                )
                
                if bluetoothManager.isConnected {
                    NavigationControlSection(
                        bluetoothManager: bluetoothManager,
                        navigationEnabled: $navigationEnabled
                    )
                    .padding(.horizontal, 12)
                    
                    StatusContentView(
                        bluetoothManager: bluetoothManager,
                        navigationEnabled: navigationEnabled
                    )
                } else {
                    DisconnectedStateView()
                }
            }
            .navigationTitle("Helm Status")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Connection Section
struct ConnectionSection: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            ConnectionHeader(
                bluetoothManager: bluetoothManager,
                isExpanded: $isExpanded
            )
            
            if isExpanded || !bluetoothManager.isConnected {
                ConnectionSectionView(bluetoothManager: bluetoothManager)
                    .padding(.horizontal, 8)
            }
        }
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal, 12)
    }
}

// MARK: - Connection Header
struct ConnectionHeader: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var isExpanded: Bool
    
    var body: some View {
        HStack {
            Text("Connection")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            
            if bluetoothManager.isConnected {
                ConnectedIndicator(bluetoothManager: bluetoothManager)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Connected Indicator
struct ConnectedIndicator: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
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
    }
}

// MARK: - Status Content View
struct StatusContentView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    let navigationEnabled: Bool
    
    var body: some View {
        if let status = bluetoothManager.arduinoStatus {
            ScrollView {
                VStack(spacing: 12) {
                    NavigationStatusCard(status: status)
                    GPSStatusCard(status: status)
                    if navigationEnabled {
                        TargetStatusCard(status: status)
                    }
                }
                .padding(.horizontal, 12)
            }
        } else {
            WaitingForDataView()
        }
    }
}

// MARK: - Waiting for Data View
struct WaitingForDataView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("Waiting for Helm device data...")
                .font(.callout)
                .foregroundColor(.gray)
            Text("Make sure the Helm device is powered on and GPS has a fix")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Disconnected State View
struct DisconnectedStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Helm device not connected")
                .font(.callout)
                .foregroundColor(.red)
            Text("Use the connection controls above to establish connection")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
        
        Spacer()
    }
}