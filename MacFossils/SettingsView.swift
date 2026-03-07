import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var scanner: FossilScanner
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Stale threshold (days)")
                    Spacer()
                    TextField("Days", value: $scanner.staleThresholdDays, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                .help("Files not accessed for this many days are considered stale")
                
                Text("Files that haven't been accessed for \(scanner.staleThresholdDays) days will be marked as stale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Scan Options")
            }
            
            Section {
                Button("Clear Identification Cache") {
                    Task { @MainActor in
                        await scanner.clearIdentificationCache()
                    }
                }
                .help("Clears cached identification results")
                
                Text("The app uses local heuristics and pattern matching to identify apps. Results are cached for 7 days to improve performance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cache")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 320)
    }
}

#Preview {
    SettingsView()
        .environmentObject(FossilScanner())
}
