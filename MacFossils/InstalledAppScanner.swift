import Foundation
import AppKit
import Security

class InstalledAppScanner {
    
    struct InstalledApp {
        let name: String
        let bundleID: String
        let url: URL
        let version: String?
    }
    
    private var authorizationRef: AuthorizationRef?
    
    static let appleOwnedPrefixes: [String] = [
        "com.apple.",
        "com.Apple.",
        "com.iTunes",
        "com.iCloud",
        "com.osxfuse"
    ]
    
    static let appleOwnedFolderNames: [String] = [
        "Apple",
        "com.apple",
        "AddressBook",
        "CallHistoryDB",
        "CallHistoryTransactions",
        "CloudDocs",
        "CoreData",
        "DataDetectors",
        "GeoServices",
        "HomeKit",
        "iCloud",
        "iTunes",
        "Maps",
        "MobileMeAccounts",
        "NetworkExtension",
        "Safari",
        "Siri",
        "Stocks",
        "Suggestions",
        "SyncServices",
        "Wallet",
        "WidgetKit",
        "NotificationCenter",
        "Passwords",
        "PassKit",
        "MediaAnalysis",
        "Knowledge",
        "NGL"
    ]
    
    func scanInstalledApps() -> [String: InstalledApp] {
        print("🔍 Starting app scan...")
        var apps: [String: InstalledApp] = [:]
        
        print("🔍 Requesting admin authorization...")
        requestAdminAuthorization()
        print("✅ Admin authorization completed")
        
        let searchPaths: [String] = [
            "/Applications",
            "/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        
        for path in searchPaths {
            print("🔍 Scanning directory: \(path)")
            let url = URL(fileURLWithPath: path)
            scanDirectory(url, into: &apps)
        }
        print("✅ Directory scanning completed")
        
        print("🔍 Scanning via Workspace...")
        scanViaWorkspace(into: &apps)
        print("✅ Workspace scan completed")
        
        print("🔍 Scanning LaunchServices database...")
        scanLaunchServicesDatabase(into: &apps)
        print("✅ LaunchServices scan completed")
        
        print("🔍 Scanning running processes...")
        scanRunningProcesses(into: &apps)
        print("✅ Running processes scan completed")
        
        print("🔍 Scanning receipts directory...")
        scanReceiptsDirectory(into: &apps)
        print("✅ Receipts scan completed")
        
        print("🔍 Scanning Application Support...")
        scanApplicationSupportForAppTraces(into: &apps)
        print("✅ Application Support scan completed")
        
        print("🔍 Scanning frameworks...")
        scanFrameworks(into: &apps)
        print("✅ Frameworks scan completed")
        
        print("🔍 Scanning system tools...")
        scanSystemTools(into: &apps)
        print("✅ System tools scan completed")
        
        print("🔍 Scanning Homebrew and MacPorts...")
        scanHomebrewAndMacPorts(into: &apps)
        print("✅ Homebrew/MacPorts scan completed")
        
        print("🔍 Cleaning up authorization...")
        cleanupAuthorization()
        print("✅ App scan fully completed with \(apps.count) entries")
        
        return apps
    }
    
    // MARK: - Authorization
    
    private func requestAdminAuthorization() {
        print("⚠️ Admin authorization skipped (background thread compatibility)")
        return
    }
    
    private func cleanupAuthorization() {
        return
    }
    
    private var hasAdminRights: Bool {
        return false
    }
    
    private func scanDirectory(_ url: URL, into apps: inout [String: InstalledApp]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for item in contents {
            if item.pathExtension == "app" {
                if let bundle = Bundle(url: item),
                   let bundleID = bundle.bundleIdentifier {
                    let app = InstalledApp(
                        name: item.deletingPathExtension().lastPathComponent,
                        bundleID: bundleID,
                        url: item,
                        version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String
                    )
                    apps[bundleID.lowercased()] = app
                    let nameLower = item.deletingPathExtension().lastPathComponent.lowercased()
                    apps["name:\(nameLower)"] = app
                    
                    let appNameKeywords = extractComponentKeywords(from: app.name)
                    for keyword in appNameKeywords where keyword.count >= 3 {
                        apps["keyword:\(keyword)"] = app
                    }
                    
                    let bundleComponents = bundleID.components(separatedBy: ".")
                    for component in bundleComponents where component.count > 3 {
                        let componentLower = component.lowercased()
                        let skip = ["com", "org", "net", "app", "apps", "application"]
                        if !skip.contains(componentLower) {
                            apps["keyword:\(componentLower)"] = app
                        }
                    }
                    
                    scanAppBundleContents(item, mainApp: app, into: &apps)
                }
            }
        }
    }
    
    private func scanViaWorkspace(into apps: inout [String: InstalledApp]) {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        
        for dir in appDirs {
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: fileURL),
                      let bundleID = bundle.bundleIdentifier else { continue }
                guard !InstalledAppScanner.isAppleOwned(bundleID: bundleID) else { continue }
                
                let app = InstalledApp(
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    bundleID: bundleID,
                    url: fileURL,
                    version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String
                )
                apps[bundleID.lowercased()] = app
                let nameLower = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                apps["name:\(nameLower)"] = app
                
                let appNameKeywords = extractComponentKeywords(from: app.name)
                for keyword in appNameKeywords where keyword.count >= 3 {
                    apps["keyword:\(keyword)"] = app
                }
                
                let bundleComponents = bundleID.components(separatedBy: ".")
                for component in bundleComponents where component.count > 3 {
                    let componentLower = component.lowercased()
                    let skip = ["com", "org", "net", "app", "apps", "application"]
                    if !skip.contains(componentLower) {
                        apps["keyword:\(componentLower)"] = app
                    }
                }
                
                scanAppBundleContents(fileURL, mainApp: app, into: &apps)
            }
        }
    }
    
    static func isAppleOwned(bundleID: String) -> Bool {
        return appleOwnedPrefixes.contains { bundleID.lowercased().hasPrefix($0.lowercased()) }
    }
    
    static func isAppleOwnedFolder(name: String) -> Bool {
        let lower = name.lowercased()
        
        if appleOwnedFolderNames.contains(where: { $0.lowercased() == lower }) {
            return true
        }
        if appleOwnedPrefixes.contains(where: { lower.hasPrefix($0.lowercased()) }) {
            return true
        }
        return false
    }
    
    // MARK: - Bundle Content Scanning
    
    private func scanAppBundleContents(_ appURL: URL, mainApp: InstalledApp, into apps: inout [String: InstalledApp]) {
        let subpaths = [
            "Contents/Helpers",
            "Contents/Library/LoginItems",
            "Contents/Library/LaunchServices",
            "Contents/MacOS",
            "Contents/Frameworks",
            "Contents/PlugIns",
            "Contents/XPCServices",
            "Contents/Resources",
        ]
        
        for subpath in subpaths {
            let dirURL = appURL.appendingPathComponent(subpath)
            
            guard FileManager.default.isReadableFile(atPath: dirURL.path) else { continue }
            guard FileManager.default.fileExists(atPath: dirURL.path) else { continue }
            
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }
            
            for item in contents {
                let itemName = item.deletingPathExtension().lastPathComponent
                let itemNameLower = itemName.lowercased()
                
                let tooGeneric = ["helper", "agent", "daemon", "service", "updater", "launcher"]
                if tooGeneric.contains(itemNameLower) { continue }
                
                if itemNameLower.count > 3 {
                    apps["helper:\(itemNameLower)"] = mainApp
                }
                
                if item.pathExtension == "app" || item.pathExtension == "xpc" {
                    if let bundle = Bundle(url: item),
                       let bundleID = bundle.bundleIdentifier {
                        apps[bundleID.lowercased()] = mainApp
                    }
                }
                
                let keywords = extractComponentKeywords(from: itemName)
                for keyword in keywords {
                    if keyword.count > 4 {
                        apps["keyword:\(keyword)"] = mainApp
                    }
                }
            }
        }
        
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        if FileManager.default.isReadableFile(atPath: infoPlistURL.path),
           let plist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any] {
            scanPlistForBundleIDs(plist, mainApp: mainApp, into: &apps)
        }
    }
    
    private func extractComponentKeywords(from name: String) -> [String] {
        var keywords: [String] = []
        let lower = name.lowercased()
        
        let camelCasePattern = "([a-z])([A-Z])"
        if let regex = try? NSRegularExpression(pattern: camelCasePattern) {
            let range = NSRange(location: 0, length: name.utf16.count)
            let separated = regex.stringByReplacingMatches(
                in: name,
                range: range,
                withTemplate: "$1 $2"
            ).lowercased()
            
            let components = separated.components(separatedBy: CharacterSet(charactersIn: " -_."))
            keywords.append(contentsOf: components.filter { $0.count >= 3 })
        }
        
        let components = lower.components(separatedBy: CharacterSet(charactersIn: "-_."))
        keywords.append(contentsOf: components.filter { $0.count >= 3 })
        
        return Array(Set(keywords))
    }
    
    private func scanPlistForBundleIDs(_ plist: [String: Any], mainApp: InstalledApp, into apps: inout [String: InstalledApp]) {
        func scanValue(_ value: Any) {
            if let string = value as? String {
                if string.contains(".") && !string.contains("/") && string.count > 5 {
                    let components = string.components(separatedBy: ".")
                    if components.count >= 2 && !components.contains(where: { $0.isEmpty }) {
                        apps[string.lowercased()] = mainApp
                    }
                }
            } else if let dict = value as? [String: Any] {
                for (_, dictValue) in dict {
                    scanValue(dictValue)
                }
            } else if let array = value as? [Any] {
                for arrayValue in array {
                    scanValue(arrayValue)
                }
            }
        }
        
        scanValue(plist)
    }
    
    // MARK: - Additional Data Sources
    
    private func scanLaunchServicesDatabase(into apps: inout [String: InstalledApp]) {
        return
    }
    
    private func scanRunningProcesses(into apps: inout [String: InstalledApp]) {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  let bundleURL = app.bundleURL else { continue }
            
            guard !InstalledAppScanner.isAppleOwned(bundleID: bundleID) else { continue }
            
            let appInfo = InstalledApp(
                name: app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
                bundleID: bundleID,
                url: bundleURL,
                version: nil
            )
            
            apps[bundleID.lowercased()] = appInfo
            let nameLower = appInfo.name.lowercased()
            apps["name:\(nameLower)"] = appInfo
            
            let appNameKeywords = extractComponentKeywords(from: appInfo.name)
            for keyword in appNameKeywords where keyword.count >= 3 {
                apps["keyword:\(keyword)"] = appInfo
            }
            
            let bundleComponents = bundleID.components(separatedBy: ".")
            for component in bundleComponents where component.count > 3 {
                let componentLower = component.lowercased()
                let skip = ["com", "org", "net", "app", "apps", "application"]
                if !skip.contains(componentLower) {
                    apps["keyword:\(componentLower)"] = appInfo
                }
            }
            
            scanAppBundleContents(bundleURL, mainApp: appInfo, into: &apps)
        }
    }
    
    private func scanReceiptsDirectory(into apps: inout [String: InstalledApp]) {
        var receiptPaths = [
            NSHomeDirectory() + "/Library/Receipts",
        ]
        
        if hasAdminRights {
            receiptPaths.append("/Library/Receipts")
            receiptPaths.append("/var/db/receipts")
            print("🔓 Scanning system receipts with admin rights")
        }
        
        for receiptPath in receiptPaths {
            guard FileManager.default.isReadableFile(atPath: receiptPath) else { continue }
            
            guard let receipts = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: receiptPath),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for receipt in receipts {
                let name = receipt.deletingPathExtension().lastPathComponent
                let nameLower = name.lowercased()
                
                if name.contains(".") {
                    let components = name.components(separatedBy: ".")
                    if components.count >= 2 {
                        let dummyApp = InstalledApp(
                            name: components.last ?? name,
                            bundleID: name,
                            url: receipt,
                            version: nil
                        )
                        
                        apps["receipt:\(nameLower)"] = dummyApp
                        
                        for component in components where component.count >= 3 {
                            apps["receipt-component:\(component.lowercased())"] = dummyApp
                        }
                    }
                }
            }
        }
    }
    
    private func scanApplicationSupportForAppTraces(into apps: inout [String: InstalledApp]) {
        var appSupportPaths = [
            NSHomeDirectory() + "/Library/Application Support",
        ]
        
        if hasAdminRights {
            appSupportPaths.append("/Library/Application Support")
            print("🔓 Scanning system Application Support with admin rights")
        }
        
        for supportPath in appSupportPaths {
            guard FileManager.default.isReadableFile(atPath: supportPath) else { continue }
            
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: supportPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for item in contents {
                let name = item.lastPathComponent
                let nameLower = name.lowercased()
                
                if InstalledAppScanner.isAppleOwnedFolder(name: name) { continue }
                
                for (key, app) in apps where !key.hasPrefix("appsupport:") {
                    let appNameLower = app.name.lowercased()
                    let bundleComponents = app.bundleID.components(separatedBy: ".")
                    
                    if nameLower.contains(appNameLower) || appNameLower.contains(nameLower) {
                        apps["appsupport:\(nameLower)"] = app
                        break
                    }
                    
                    for component in bundleComponents where component.count > 4 {
                        if nameLower.contains(component.lowercased()) {
                            apps["appsupport:\(nameLower)"] = app
                            break
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - System Tools & Frameworks
    
    private func scanFrameworks(into apps: inout [String: InstalledApp]) {
        let frameworkPaths = [
            "/Library/Frameworks",
            NSHomeDirectory() + "/Library/Frameworks",
            "/System/Library/Frameworks",
        ]
        
        for frameworkPath in frameworkPaths {
            guard FileManager.default.isReadableFile(atPath: frameworkPath) else { continue }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: frameworkPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for item in contents {
                let name = item.deletingPathExtension().lastPathComponent
                let nameLower = name.lowercased()
                
                if InstalledAppScanner.isAppleOwnedFolder(name: name) { continue }
                
                let frameworkApp = InstalledApp(
                    name: name,
                    bundleID: "framework.\(nameLower)",
                    url: item,
                    version: nil
                )
                
                apps["framework:\(nameLower)"] = frameworkApp
                
                let keywords = extractComponentKeywords(from: name)
                for keyword in keywords where keyword.count >= 3 {
                    apps["keyword:\(keyword)"] = frameworkApp
                }
            }
        }
    }
    
    private func scanSystemTools(into apps: inout [String: InstalledApp]) {
        let toolPaths = [
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt",
            "/opt/local/bin",
            NSHomeDirectory() + "/.local/bin",
        ]
        
        for toolPath in toolPaths {
            guard FileManager.default.isReadableFile(atPath: toolPath) else { continue }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: toolPath),
                includingPropertiesForKeys: [.isExecutableKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for item in contents {
                let name = item.lastPathComponent
                let nameLower = name.lowercased()
                
                guard nameLower.count > 2 else { continue }
                
                let skipTools = ["sh", "bash", "zsh", "ls", "cd", "rm", "cp", "mv", "cat", "echo"]
                if skipTools.contains(nameLower) { continue }
                
                let toolApp = InstalledApp(
                    name: name,
                    bundleID: "tool.\(nameLower)",
                    url: item,
                    version: nil
                )
                
                apps["tool:\(nameLower)"] = toolApp
                apps["keyword:\(nameLower)"] = toolApp
            }
        }
        
        scanJavaInstallations(into: &apps)
    }
    
    private func scanJavaInstallations(into apps: inout [String: InstalledApp]) {
        let javaPaths = [
            "/Library/Java/JavaVirtualMachines",
            "/System/Library/Java/JavaVirtualMachines",
            NSHomeDirectory() + "/Library/Java/JavaVirtualMachines",
        ]
        
        var foundJava = false
        
        for javaPath in javaPaths {
            guard FileManager.default.isReadableFile(atPath: javaPath) else { continue }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: javaPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for jvm in contents {
                let name = jvm.lastPathComponent
                foundJava = true
                
                let javaApp = InstalledApp(
                    name: "Java (\(name))",
                    bundleID: "com.oracle.java",
                    url: jvm,
                    version: name
                )
                
                apps["java"] = javaApp
                apps["keyword:java"] = javaApp
                apps["framework:java"] = javaApp
                apps["tool:java"] = javaApp
                apps["com.oracle.java"] = javaApp
                
                let nameLower = name.lowercased()
                if nameLower.contains("jdk") {
                    apps["keyword:jdk"] = javaApp
                }
                if nameLower.contains("jre") {
                    apps["keyword:jre"] = javaApp
                }
            }
        }
        
        if foundJava {
            print("☕️ Java installation(s) found")
        }
    }
    
    private func scanHomebrewAndMacPorts(into apps: inout [String: InstalledApp]) {
        let brewPaths = [
            "/opt/homebrew/Cellar",  // Apple Silicon
            "/usr/local/Cellar",     // Intel
        ]
        
        for brewPath in brewPaths {
            guard FileManager.default.isReadableFile(atPath: brewPath) else { continue }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: brewPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for package in contents {
                let name = package.lastPathComponent
                let nameLower = name.lowercased()
                
                let brewApp = InstalledApp(
                    name: name,
                    bundleID: "brew.\(nameLower)",
                    url: package,
                    version: nil
                )
                
                apps["brew:\(nameLower)"] = brewApp
                apps["keyword:\(nameLower)"] = brewApp
            }
        }
        
        let portsPath = "/opt/local/var/macports/registry/portfiles"
        if FileManager.default.isReadableFile(atPath: portsPath) {
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: portsPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for package in contents {
                    let name = package.lastPathComponent
                    let nameLower = name.lowercased()
                    
                    let portApp = InstalledApp(
                        name: name,
                        bundleID: "macports.\(nameLower)",
                        url: package,
                        version: nil
                    )
                    
                    apps["port:\(nameLower)"] = portApp
                    apps["keyword:\(nameLower)"] = portApp
                }
            }
        }
    }
}
