import SwiftUI

@main
struct MacFossilsApp: App {
    @StateObject private var scanner = FossilScanner()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanner)
                .frame(minWidth: 1500, minHeight: 700)
                .onAppear {
                    scanner.requestAutomationAccessIfNeeded()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Start Scan") {
                    Task { await scanner.startScan() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(scanner)
        }
    }
}
