import Foundation
import AppKit
import Security

@MainActor
class FossilScanner: ObservableObject {
    
    @Published var fossils: [FossilItem] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var scanStatus: String = "Ready"
    @Published var isScanningApps: Bool = false
    @Published var isScanInProgress: Bool = false
    @Published var hasStartedScan: Bool = false
    @Published var selectedCategory: FossilCategory? = nil
    @Published var searchText: String = ""
    @Published var filterOrphansOnly: Bool = false
    @Published var filterStaleOnly: Bool = false
    @Published var hideInstalledApps: Bool = false
    @Published var staleThresholdDays: Int = 365
    @Published var totalScannedItems: Int = 0
    @Published var hasScanned: Bool = false
    
    private var installedApps: [String: InstalledAppScanner.InstalledApp] = [:]
    private let identifierService = AppIdentifierService()
    private var didPromptAutomationThisLaunch = false
    private var didPromptFullDiskAccessThisLaunch = false
    
    // MARK: - Filtered fossils
    
    var filteredFossils: [FossilItem] {
        var result = fossils
        
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        
        if filterOrphansOnly {
            result = result.filter { $0.status == .orphan }
        }
        
        if hideInstalledApps {
            result = result.filter { $0.status == .orphan }
        }
        
        if filterStaleOnly {
            result = result.filter {
                guard let days = $0.daysSinceLastUse else { return false }
                return days >= staleThresholdDays
            }
        }
        
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                ($0.bundleIdentifier?.lowercased().contains(q) ?? false) ||
                ($0.matchedAppName?.lowercased().contains(q) ?? false)
            }
        }
        
        return result
    }
    
    var categoryCounts: [FossilCategory: Int] {
        var counts: [FossilCategory: Int] = [:]
        for fossil in fossils {
            counts[fossil.category, default: 0] += 1
        }
        return counts
    }
    
    var totalSize: Int64 {
        filteredFossils.reduce(0) { $0 + $1.fileSize }
    }
    
    var orphanCount: Int {
        fossils.filter { $0.status == .orphan }.count
    }
    
    // MARK: - Scan
    
    func startScan() async {
        guard !isScanning else { return }
        triggerFullDiskAccessProbe()
        if !hasFullDiskAccess() {
            requestFullDiskAccessIfNeeded()
            return
        }
        isScanning = true
        isScanInProgress = true
        hasStartedScan = true
        fossils = []
        totalScannedItems = 0
        scanProgress = 0
        hasScanned = false
        
        scanStatus = "Detecting installed apps..."
        isScanningApps = true
        
        let appMap = await Task.detached(priority: .background) {
            InstalledAppScanner().scanInstalledApps()
        }.value
        
        self.installedApps = appMap
        let installedAppsSnapshot = appMap
        isScanningApps = false
        
        print("📊 \(appMap.count) app entries found (incl. helpers, keywords, etc.)")
        
        let uniqueApps = Set(appMap.values.map { $0.name })
        print("🔍 Unique apps: \(uniqueApps.count)")
        print("🔍 Sample apps:")
        for (index, appName) in uniqueApps.prefix(20).enumerated() {
            if let entry = appMap.values.first(where: { $0.name == appName }) {
                print("   \(index + 1). \(appName) (\(entry.bundleID))")
            }
        }
        
        let searchNames = [""]
        for searchName in searchNames {
            let matches = appMap.filter { key, app in
                key.lowercased().contains(searchName) || app.name.lowercased().contains(searchName)
            }
            if matches.isEmpty {
                print("⚠️ '\(searchName)' NOT found in installedApps!")
            } else {
                print("✅ '\(searchName)' found: \(matches.count) entries")
                for (key, app) in matches.prefix(5) {
                    print("   - Key: '\(key)' → App: '\(app.name)' (\(app.bundleID))")
                }
            }
        }
        
        let scanLocations = buildScanLocations()
        let totalLocations = Double(scanLocations.count)
        
        for (index, location) in scanLocations.enumerated() {
            scanStatus = "Scanning: \(location.path.url.lastPathComponent)"
            let baseProgress = Double(index) / totalLocations
            let locationWeight = 1.0 / totalLocations
            scanProgress = baseProgress
            
            let service = self.identifierService
            let baseTotalScanned = totalScannedItems
            let progressHandler: @Sendable (Int, Int) -> Void = { [weak self] processed, total in
                let fraction = total > 0 ? Double(processed) / Double(total) : 0
                let progress = min(1.0, baseProgress + (fraction * locationWeight))
                Task { @MainActor in
                    self?.scanProgress = progress
                    self?.totalScannedItems = baseTotalScanned + processed
                }
            }
            let batchHandler: @Sendable ([FossilItem]) -> Void = { [weak self] batch in
                guard !batch.isEmpty else { return }
                Task { @MainActor in
                    self?.fossils.append(contentsOf: batch)
                }
            }
            
            let staleThreshold = self.staleThresholdDays
            let newFossils = await Task.detached(priority: .utility) {
                await FossilScanner.scanLocation(
                    location, 
                    installedApps: installedAppsSnapshot,
                    identifierService: service,
                    staleThresholdDays: staleThreshold,
                    progressHandler: progressHandler,
                    batchHandler: batchHandler
                )
            }.value
            
            fossils.append(contentsOf: newFossils)
            await Task.yield()
        }
        
        fossils.sort {
            if $0.status == .orphan && $1.status != .orphan { return true }
            if $0.status != .orphan && $1.status == .orphan { return false }
            return $0.fileSize > $1.fileSize
        }
        
        scanProgress = 1.0
        scanStatus = "\(fossils.count) leftovers found"
        isScanning = false
        isScanningApps = false
        isScanInProgress = false
        hasStartedScan = false
        hasScanned = true
    }
    
    func requestAutomationAccessIfNeeded() {
        guard !didPromptAutomationThisLaunch else { return }
        didPromptAutomationThisLaunch = true
        
        let script = """
        tell application "System Events" to get name of first process
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            _ = scriptObject.executeAndReturnError(&error)
            if let error = error,
               let number = error[NSAppleScript.errorNumber] as? Int,
               number == -1743 {
                let alert = NSAlert()
                alert.messageText = "Automation access required"
                alert.informativeText = "MacFossils needs Automation permission to move protected items to Trash. Open System Settings to allow access?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Not Now")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    openAutomationSettings()
                }
            }
        }
    }
    
    func requestFullDiskAccessIfNeeded() {
        guard !didPromptFullDiskAccessThisLaunch else { return }
        didPromptFullDiskAccessThisLaunch = true
        
        guard !hasFullDiskAccess() else { return }
        
        let alert = NSAlert()
        alert.messageText = "Full Disk Access required"
        alert.informativeText = "MacFossils needs Full Disk Access to scan all leftover files. Open System Settings to allow access?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openFullDiskAccessSettings()
        }
    }
    
    private func hasFullDiskAccess() -> Bool {
        let tccPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("com.apple.TCC")
            .appendingPathComponent("TCC.db")
        return FileManager.default.isReadableFile(atPath: tccPath.path)
    }
    
    private func triggerFullDiskAccessProbe() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedDirectories = [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Safari")
        ]
        for directory in protectedDirectories {
            _ = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        }
        let tccDatabase = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("com.apple.TCC")
            .appendingPathComponent("TCC.db")
        if let handle = FileHandle(forReadingAtPath: tccDatabase.path) {
            try? handle.close()
        }
    }
    
    // MARK: - Scan Locations
    
    struct ScanLocation {
        let path: ScanPath
        let category: FossilCategory
        let recursive: Bool
        
        struct ScanPath {
            let url: URL
        }
    }
    
    private func buildScanLocations() -> [ScanLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        
        return [
            ScanLocation(
                path: .init(url: library.appendingPathComponent("Application Support")),
                category: .applicationSupport,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: library.appendingPathComponent("Application Scripts")),
                category: .applicationScripts,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: library.appendingPathComponent("LaunchAgents")),
                category: .launchAgents,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: URL(fileURLWithPath: "/Library/LaunchAgents")),
                category: .launchAgents,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: URL(fileURLWithPath: "/Library/LaunchDaemons")),
                category: .launchDaemons,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: library.appendingPathComponent("Preferences")),
                category: .preferences,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: library.appendingPathComponent("Caches")),
                category: .caches,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: library.appendingPathComponent("Containers")),
                category: .containers,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: library.appendingPathComponent("Saved Application State")),
                category: .savedState,
                recursive: false
            ),
            ScanLocation(
                path: .init(url: library.appendingPathComponent("Logs")),
                category: .logs,
                recursive: false
            ),
        ]
    }
    
    // MARK: - Scan a location
    
    nonisolated private static func scanLocation(
        _ location: ScanLocation,
        installedApps: [String: InstalledAppScanner.InstalledApp],
        identifierService: AppIdentifierService,
        staleThresholdDays: Int,
        progressHandler: @Sendable (Int, Int) -> Void,
        batchHandler: @Sendable ([FossilItem]) -> Void
    ) async -> [FossilItem] {
        var items: [FossilItem] = []
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: location.path.url.path) else { return [] }
        
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: location.path.url,
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .totalFileSizeKey,
                    .contentModificationDateKey,
                    .contentAccessDateKey,
                    .creationDateKey,
                    .isDirectoryKey
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        
        var processedCount = 0
        let totalCount = contents.count
        for itemURL in contents {
            let name = itemURL.lastPathComponent
            
            if InstalledAppScanner.isAppleOwnedFolder(name: name) { continue }
            
            let resourceValues = try? itemURL.resourceValues(forKeys: [
                .totalFileSizeKey, .fileSizeKey,
                .contentModificationDateKey, .contentAccessDateKey, .creationDateKey
            ])
            
            let fileSize = Int64(resourceValues?.totalFileSize ?? resourceValues?.fileSize ?? 0)
            let lastModified = resourceValues?.contentModificationDate
            let lastAccessed = resourceValues?.contentAccessDate
            let creationDate = resourceValues?.creationDate
            
            let lastOpened = getMDLastOpened(url: itemURL)
            
            var (bundleID, matchedApp, status) = await resolveBundleIdentifier(
                itemName: name,
                itemURL: itemURL,
                category: location.category,
                installedApps: installedApps,
                identifierService: identifierService
            )
            
            if status == .orphan {
                let referenceDate = lastOpened ?? lastAccessed ?? lastModified
                if let referenceDate {
                    let daysSince = Calendar.current.dateComponents([.day], from: referenceDate, to: Date()).day ?? 0
                    if daysSince <= staleThresholdDays {
                        status = .stale
                        matchedApp = "Unknown"
                    }
                }
            }
            
            let risk = calculateRisk(
                status: status,
                lastOpened: lastOpened,
                lastModified: lastModified,
                category: location.category,
                staleThresholdDays: staleThresholdDays
            )
            
            let fossil = FossilItem(
                url: itemURL,
                category: location.category,
                status: status,
                bundleIdentifier: bundleID,
                matchedAppName: matchedApp,
                fileSize: fileSize,
                lastModified: lastModified,
                lastOpened: lastOpened,
                lastUsed: lastAccessed,
                creationDate: creationDate,
                risk: risk
            )
            
            items.append(fossil)
            
            processedCount += 1
            if processedCount % 25 == 0 || processedCount == totalCount {
                progressHandler(processedCount, totalCount)
            }
            if items.count >= 50 {
                batchHandler(items)
                items.removeAll(keepingCapacity: true)
            }
            if processedCount % 50 == 0 {
                await Task.yield()
            }
        }
        
        return items
    }
    
    // MARK: - Bundle-ID Resolution
    
    nonisolated private static func resolveBundleIdentifier(
        itemName: String,
        itemURL: URL,
        category: FossilCategory,
        installedApps: [String: InstalledAppScanner.InstalledApp],
        identifierService: AppIdentifierService
    ) async -> (bundleID: String?, matchedApp: String?, status: FossilStatus) {
        let nameLower = itemName.lowercased()
        let nameWithoutExt = itemURL.deletingPathExtension().lastPathComponent.lowercased()
        
        // MARK: - Phase 1
        
        if itemURL.pathExtension == "plist",
           let plist = NSDictionary(contentsOf: itemURL),
           let label = plist["Label"] as? String {
            
            let labelLower = label.lowercased()
            
            if InstalledAppScanner.isAppleOwned(bundleID: label) {
                return (label, nil, .stale)
            }
            
            if let match = installedApps[labelLower] {
                return (match.bundleID, match.name, .stale)
            }
            
            for (_, app) in installedApps {
                if app.bundleID.lowercased() == labelLower {
                    return (app.bundleID, app.name, .stale)
                }
            }
        }
        
        let exactLookups = [
            ("name:\(nameWithoutExt)", true),
            ("helper:\(nameWithoutExt)", true),
            ("receipt:\(nameWithoutExt)", true),
            ("appsupport:\(nameWithoutExt)", true),
            (nameLower, false)
        ]
        
        for (key, requireAppName) in exactLookups {
            if let match = installedApps[key] {
                let appName = requireAppName ? match.name : "Unknown"
                return (match.bundleID, appName, .stale)
            }
        }
        
        for (_, app) in installedApps {
            if app.bundleID.lowercased() == nameLower || 
               app.bundleID.lowercased() == nameWithoutExt {
                return (app.bundleID, app.name, .stale)
            }
        }
        
        // MARK: - Phase 2
        
        let (enhancedAppName, enhancedBundleID, confidence) = await identifierService.identifyApp(
            itemName: itemName,
            bundleIDHint: nil
        )
        
        if let enhancedAppName = enhancedAppName, confidence != .low {
            let emoji = confidence == .high ? "✅" : "⚠️"
            print("\(emoji) Enhanced identification: \(itemName) → \(enhancedAppName) (confidence: \(confidence))")
            
            func isInstalledAppMatch(bundleID: String?, appName: String?) -> Bool {
                if let bundleID = bundleID {
                    let bundleLower = bundleID.lowercased()
                    if installedApps[bundleLower] != nil { return true }
                    for (_, app) in installedApps {
                        if app.bundleID.lowercased() == bundleLower { return true }
                    }
                }
                if let appName = appName {
                    let nameLower = appName.lowercased()
                    if installedApps["name:\(nameLower)"] != nil { return true }
                    for (_, app) in installedApps {
                        if app.name.lowercased() == nameLower { return true }
                    }
                }
                return false
            }
            
            if isInstalledAppMatch(bundleID: enhancedBundleID, appName: enhancedAppName) {
                print("   ✅ App is installed → .stale")
                return (enhancedBundleID, enhancedAppName, .stale)
            } else {
                print("   ⚠️ App is NOT installed → .orphan")
                return (enhancedBundleID, enhancedAppName, .orphan)
            }
        }
        
        // MARK: - Phase 3
        
        var foundMatch: (bundleID: String, appName: String?)? = nil
        var plistLabelLower: String? = nil
        
        func considerMatch(bundleID: String, appName: String?) {
            if foundMatch == nil {
                foundMatch = (bundleID, appName)
            }
        }
        
        func bundleIDMatchesItemName(_ bundleID: String) -> Bool {
            let skip = ["com", "org", "net", "app", "apps", "application"]
            let bundleComponents = bundleID.lowercased()
                .components(separatedBy: ".")
                .filter { $0.count >= 2 && !skip.contains($0) }
            if bundleComponents.isEmpty { return false }
            
            let nameTarget = nameWithoutExt.lowercased()
            for component in bundleComponents {
                if nameTarget.contains(component) { return true }
                if let labelLower = plistLabelLower, labelLower.contains(component) { return true }
            }
            return false
        }
        
        func normalizedToken(_ value: String) -> String {
            let filtered = value.filter { !$0.isNumber }
            return filtered
        }
        
        func hasCommonSubstring(a: String, b: String, minLength: Int) -> Bool {
            guard minLength > 0 else { return true }
            guard a.count >= minLength, b.count >= minLength else { return false }
            let aChars = Array(a)
            let bChars = Array(b)
            if aChars.count <= bChars.count {
                for i in 0...(aChars.count - minLength) {
                    for len in minLength...(aChars.count - i) {
                        let sub = String(aChars[i..<(i + len)])
                        if b.contains(sub) { return true }
                    }
                }
            } else {
                for i in 0...(bChars.count - minLength) {
                    for len in minLength...(bChars.count - i) {
                        let sub = String(bChars[i..<(i + len)])
                        if a.contains(sub) { return true }
                    }
                }
            }
            return false
        }
        
        func levenshteinDistance(_ a: String, _ b: String, maxDistance: Int) -> Int {
            if a == b { return 0 }
            let aChars = Array(a)
            let bChars = Array(b)
            let aCount = aChars.count
            let bCount = bChars.count
            if abs(aCount - bCount) > maxDistance { return maxDistance + 1 }
            
            var prev = Array(0...bCount)
            var current = Array(repeating: 0, count: bCount + 1)
            
            for i in 1...aCount {
                current[0] = i
                var rowMin = current[0]
                for j in 1...bCount {
                    let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                    current[j] = min(
                        prev[j] + 1,
                        current[j - 1] + 1,
                        prev[j - 1] + cost
                    )
                    rowMin = min(rowMin, current[j])
                }
                if rowMin > maxDistance { return maxDistance + 1 }
                prev = current
            }
            
            return prev[bCount]
        }
        
        func isFuzzyMatch(_ a: String, _ b: String, minCommonLength: Int) -> Bool {
            let aNorm = normalizedToken(a)
            let bNorm = normalizedToken(b)
            guard aNorm.count >= minCommonLength, bNorm.count >= minCommonLength else { return false }
            if aNorm.contains(bNorm) || bNorm.contains(aNorm) { return true }
            if hasCommonSubstring(a: aNorm, b: bNorm, minLength: minCommonLength) { return true }
            return levenshteinDistance(aNorm, bNorm, maxDistance: 2) <= 2
        }
        
        func isFuzzyMatchConfirmed(_ a: String, _ b: String) -> Bool {
            let aNorm = normalizedToken(a)
            let bNorm = normalizedToken(b)
            let fuzzy4 = isFuzzyMatch(aNorm, bNorm, minCommonLength: 4)
            guard fuzzy4 else { return false }
            
            if aNorm.contains(bNorm), bNorm.count >= 6 { return true }
            if bNorm.contains(aNorm), aNorm.count >= 6 { return true }
            if hasCommonSubstring(a: aNorm, b: bNorm, minLength: 6) { return true }
            
            return false
        }
        
        let keywords = extractKeywords(from: nameWithoutExt)
        
        for keyword in keywords {
            if let match = installedApps["keyword:\(keyword)"] {
                considerMatch(bundleID: match.bundleID, appName: match.name)
            }
            if let match = installedApps["receipt-component:\(keyword)"] {
                considerMatch(bundleID: match.bundleID, appName: match.name)
            }
            if let match = installedApps["framework:\(keyword)"] {
                considerMatch(bundleID: match.bundleID, appName: match.name)
            }
            if let match = installedApps["tool:\(keyword)"] {
                considerMatch(bundleID: match.bundleID, appName: match.name)
            }
            if let match = installedApps["brew:\(keyword)"] {
                considerMatch(bundleID: match.bundleID, appName: match.name)
            }
        }
        
        let nameComponents = nameWithoutExt.components(separatedBy: CharacterSet(charactersIn: ".-_ "))
            .filter { $0.count > 3 }
        
        for component in nameComponents {
            for (key, app) in installedApps {
                if key.contains(component) {
                    considerMatch(bundleID: app.bundleID, appName: app.name)
                    break
                }
            }
        }
        
        let fileComponents = nameWithoutExt.components(separatedBy: CharacterSet(charactersIn: ".-_ "))
            .filter { $0.count > 2 }
        for (key, app) in installedApps {
            if key.hasPrefix("name:") || key.hasPrefix("helper:") ||
               key.hasPrefix("keyword:") || key.hasPrefix("receipt:") ||
               key.hasPrefix("appsupport:") || key.hasPrefix("receipt-component:") ||
               key.hasPrefix("framework:") || key.hasPrefix("tool:") ||
               key.hasPrefix("brew:") || key.hasPrefix("port:") {
                continue
            }
            
            let bundleComponents = app.bundleID.components(separatedBy: ".")
            let appNameWords = app.name.lowercased().components(separatedBy: CharacterSet(charactersIn: " -_"))
                .filter { $0.count > 3 }
            let allComponents = bundleComponents + appNameWords
            
            for component in allComponents where component.count > 3 {
                let componentLower = component.lowercased()
                let generic = ["app", "application", "desktop", "client", "suite", "studio", "pro", "plus"]
                if generic.contains(componentLower) { continue }
                
                if nameWithoutExt.contains(componentLower) {
                    considerMatch(bundleID: app.bundleID, appName: app.name)
                    break
                }
                
                for fileComponent in fileComponents {
                    if isFuzzyMatchConfirmed(componentLower, fileComponent) {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                        break
                    }
                }
            }
        }
        
        for (key, app) in installedApps {
            guard key.hasPrefix("name:") else { continue }
            
            let appName = String(key.dropFirst(5))
            guard appName.count > 4 else { continue }
            
            let fileWords = nameWithoutExt.components(separatedBy: CharacterSet(charactersIn: ".-_ "))
                .filter { $0.count >= 4 }
            
            let appWords = appName.components(separatedBy: CharacterSet(charactersIn: " -_"))
                .filter { $0.count >= 4 }
            
            guard !fileWords.isEmpty && !appWords.isEmpty else { continue }
            
            for appWord in appWords {
                let appWordLower = appWord.lowercased()
                
                let skipWords = ["application", "software", "desktop", "client", "helper", "launcher", "manager"]
                if skipWords.contains(appWordLower) { continue }
                
                for fileWord in fileWords {
                    if fileWord == appWordLower {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                    }
                    
                    if appWordLower.count >= 5 && fileWord.contains(appWordLower) {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                    }
                    if fileWord.count >= 5 && appWordLower.contains(fileWord) {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                    }
                    
                    if appWordLower.count >= 5 && fileWord.hasPrefix(appWordLower) {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                    }
                    if fileWord.count >= 5 && appWordLower.hasPrefix(fileWord) {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                    }
                }
            }
        }
        
        for (key, app) in installedApps {
            guard key.hasPrefix("name:") else { continue }
            
            let appName = String(key.dropFirst(5))
            guard appName.count > 3 else { continue }
            
            if nameWithoutExt.contains(appName) {
                considerMatch(bundleID: app.bundleID, appName: app.name)
            }
            
            if appName.contains(nameWithoutExt) && nameWithoutExt.count > 5 {
                considerMatch(bundleID: app.bundleID, appName: app.name)
            }
            
            let appNameWords = appName.components(separatedBy: CharacterSet(charactersIn: " -_"))
                .filter { $0.count > 3 }
            
            for word in appNameWords {
                if nameWithoutExt.contains(word) {
                    considerMatch(bundleID: app.bundleID, appName: app.name)
                    break
                }
            }
        }
        
        for (key, app) in installedApps {
            guard key.hasPrefix("name:") else { continue }
            
            let appName = String(key.dropFirst(5))
            let appNameLower = appName.lowercased()
            
            guard appNameLower.count >= 4 else { continue }
            
            let nameWithoutExtNoDigits = normalizedToken(nameWithoutExt)
            let nameLowerNoDigits = normalizedToken(nameLower)
            let appNameLowerNoDigits = normalizedToken(appNameLower)
            
            if nameWithoutExt.contains(appNameLower) {
                considerMatch(bundleID: app.bundleID, appName: app.name)
            }
            
            if nameLower.contains(appNameLower) {
                considerMatch(bundleID: app.bundleID, appName: app.name)
            }
            
            if nameWithoutExtNoDigits.contains(appNameLowerNoDigits) || nameLowerNoDigits.contains(appNameLowerNoDigits) {
                considerMatch(bundleID: app.bundleID, appName: app.name)
            }
            
            if hasCommonSubstring(a: nameWithoutExtNoDigits, b: appNameLowerNoDigits, minLength: 4) {
                considerMatch(bundleID: app.bundleID, appName: app.name)
            }
            
            if nameWithoutExt.count >= 4 && appNameLower.contains(nameWithoutExt) {
                considerMatch(bundleID: app.bundleID, appName: app.name)
            }
            
            let appParts = appNameLower.components(separatedBy: CharacterSet(charactersIn: " -_."))
                .filter { $0.count >= 4 }
            
            let fileParts = nameWithoutExt.components(separatedBy: CharacterSet(charactersIn: ".-_ "))
                .filter { $0.count >= 4 }
            
            let filePartsWithExt = nameLower.components(separatedBy: CharacterSet(charactersIn: ".-_ "))
                .filter { $0.count >= 4 }
            
            let allFileParts = Set(fileParts + filePartsWithExt)
            
            for appPart in appParts {
                if allFileParts.contains(appPart) {
                    considerMatch(bundleID: app.bundleID, appName: app.name)
                }
                
                if nameWithoutExt.contains(appPart) || nameLower.contains(appPart) {
                    considerMatch(bundleID: app.bundleID, appName: app.name)
                }
                
                for filePart in allFileParts {
                    let appPartNoDigits = normalizedToken(appPart)
                    let filePartNoDigits = normalizedToken(filePart)
                    
                    if appPart.contains(filePart) && filePart.count >= 4 {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                    }

                    if filePart.contains(appPart) && appPart.count >= 4 {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                    }

                    if appNameLower.contains(filePart) && filePart.count >= 4 {
                        considerMatch(bundleID: app.bundleID, appName: app.name)
                    }
                    

                    if appPartNoDigits.count >= 4 && filePartNoDigits.count >= 4 {
                        if appPartNoDigits.contains(filePartNoDigits) || filePartNoDigits.contains(appPartNoDigits) {
                            considerMatch(bundleID: app.bundleID, appName: app.name)
                        }
                        
                        if hasCommonSubstring(a: appPartNoDigits, b: filePartNoDigits, minLength: 4) {
                            considerMatch(bundleID: app.bundleID, appName: app.name)
                        }
                        
                        let commonPrefixLength = zip(appPartNoDigits, filePartNoDigits)
                            .prefix { $0 == $1 }
                            .count
                        if commonPrefixLength >= 4 {
                            considerMatch(bundleID: app.bundleID, appName: app.name)
                        }
                    }
                }
            }
        }
        
        for (key, app) in installedApps {
            if key.hasPrefix("name:") || key.hasPrefix("helper:") ||
               key.hasPrefix("keyword:") || key.hasPrefix("receipt:") ||
               key.hasPrefix("appsupport:") || key.hasPrefix("receipt-component:") {
                continue
            }
            
            if nameLower.hasPrefix(key) || key.hasPrefix(nameLower) {
                considerMatch(bundleID: app.bundleID, appName: app.name)
            }
        }
        
        if itemURL.pathExtension == "plist",
           let plist = NSDictionary(contentsOf: itemURL),
           let label = plist["Label"] as? String {
            
            let labelLower = label.lowercased()
            plistLabelLower = labelLower
            
            for (key, app) in installedApps {
                if key.hasPrefix("name:") || key.hasPrefix("helper:") ||
                   key.hasPrefix("keyword:") || key.hasPrefix("receipt:") ||
                   key.hasPrefix("appsupport:") || key.hasPrefix("receipt-component:") ||
                   key.hasPrefix("framework:") || key.hasPrefix("tool:") ||
                   key.hasPrefix("brew:") || key.hasPrefix("port:") {
                    continue
                }
                
                if labelLower.hasPrefix(key) || key.hasPrefix(labelLower) {
                    considerMatch(bundleID: app.bundleID, appName: app.name)
                }
                
                if labelLower.contains(key) || key.contains(labelLower.components(separatedBy: ".").last ?? "") {
                    considerMatch(bundleID: app.bundleID, appName: app.name)
                }
            }
            
            let labelComponents = label.components(separatedBy: ".")
            for component in labelComponents where component.count > 3 {
                let componentLower = component.lowercased()
                
                if let match = installedApps["keyword:\(componentLower)"] {
                    considerMatch(bundleID: match.bundleID, appName: match.name)
                }
            }
        }
        
        if let match = foundMatch {
            func isInstalledAppMatch(bundleID: String?, appName: String?) -> Bool {
                if let bundleID = bundleID {
                    let bundleLower = bundleID.lowercased()
                    if installedApps[bundleLower] != nil { return true }
                    for (_, app) in installedApps {
                        if app.bundleID.lowercased() == bundleLower { return true }
                    }
                }
                if let appName = appName {
                    let nameLower = appName.lowercased()
                    if installedApps["name:\(nameLower)"] != nil { return true }
                    for (_, app) in installedApps {
                        if app.name.lowercased() == nameLower { return true }
                    }
                }
                return false
            }
            
            if isInstalledAppMatch(bundleID: match.bundleID, appName: match.appName) {
                if let appName = match.appName, bundleIDMatchesItemName(match.bundleID) {
                    return (match.bundleID, appName, .stale)
                }
                return (match.bundleID, "Unknown", .stale)
            }
            
            return (match.bundleID, match.appName ?? "Unknown", .orphan)
        }
        
        return (nil, nil, .orphan)
    }
    
    // MARK: - Keyword Extraction
    
    nonisolated private static func extractKeywords(from text: String) -> [String] {
        let textLower = text.lowercased()
        var keywords: [String] = []
        
        let components = textLower.components(separatedBy: CharacterSet(charactersIn: ".-_ "))
        for component in components where component.count > 3 {
            keywords.append(component)
        }
        
        let genericWords = [
            "support", "helper", "agent", "daemon", "service", "plugin", 
            "extension", "plist", "data", "temp", "application", "framework",
            "library", "system", "user", "local", "private", "public"
        ]
        keywords = keywords.filter { !genericWords.contains($0) }
        
        return Array(Set(keywords))
    }
    
    // MARK: - Metadata
    
    nonisolated private static func getMDLastOpened(url: URL) -> Date? {
        let mdItem = MDItemCreate(nil, url.path as CFString)
        guard let item = mdItem else { return nil }
        
        if let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return date
        }
        return nil
    }
    
    // MARK: - Risk Calculation
    
    nonisolated private static func calculateRisk(
        status: FossilStatus,
        lastOpened: Date?,
        lastModified: Date?,
        category: FossilCategory,
        staleThresholdDays: Int
    ) -> FossilRisk {
        
        if status == .orphan { 
            return .review 
        }
        
        if status == .stale { 
            return .safe 
        }
        
        let referenceDate = lastOpened ?? lastModified
        guard let date = referenceDate else { return .caution }
        
        let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        
        if daysSince > staleThresholdDays * 2 { return .review }
        if daysSince > staleThresholdDays { return .caution }
        return .safe
    }
    
    // MARK: - Actions
    
    func moveToTrash(_ fossil: FossilItem) {
        do {
            var resultURL: NSURL? = nil
            try FileManager.default.trashItem(at: fossil.url, resultingItemURL: &resultURL)
            fossil.action = .trashed
            fossils.removeAll { $0.id == fossil.id }
            print("✅ Moved to Trash: \(fossil.name)")
        } catch {
            requestAdminDeletionIfNeeded(fossil: fossil, originalError: error)
        }
    }
    
    private func moveToTrashWithAdmin(_ fossil: FossilItem) -> (success: Bool, error: NSDictionary?) {
        let script = """
        do shell script "mv -f '\\(fossil.url.path.replacingOccurrences(of: "'", with: "'\\\\''"))' ~/.Trash/" with administrator privileges
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            _ = scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                print("❌ AppleScript error: \(error)")
                return (false, error)
            }
            
            if !FileManager.default.fileExists(atPath: fossil.url.path) {
                print("✅ Deleted with admin rights (AppleScript)")
                return (true, nil)
            } else {
                print("⚠️ AppleScript meldet Erfolg, Datei existiert noch")
            }
        }
        
        return (false, error)
    }
    
    private func requestAdminDeletionIfNeeded(fossil: FossilItem, originalError: Error) {
        let alert = NSAlert()
        alert.messageText = "Admin rights required"
        alert.informativeText = "The item '\(fossil.name)' requires administrator privileges to move to Trash. Do you want to continue?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            openAutomationSettings()
            return
        }
        guard response == .alertFirstButtonReturn else { return }
        
        let result = moveToTrashWithAdmin(fossil)
        if result.success {
            fossil.action = .trashed
            fossils.removeAll { $0.id == fossil.id }
            print("✅ Moved to Trash with admin rights: \(fossil.name)")
            return
        }
        
        let details: String
        if let error = result.error,
           let number = error[NSAppleScript.errorNumber] as? Int,
           number == -1743 {
            details = "System Settings > Privacy & Security > Automation: allow MacFossils to control System Events."
        } else {
            details = originalError.localizedDescription
        }
        
        let errorAlert = NSAlert()
        errorAlert.messageText = "Error while deleting"
        errorAlert.informativeText = "System Settings > Privacy & Security > Automation: allow MacFossils to control System Events.\n\nThe file '\(fossil.name)' could not be deleted.\n\nError: \(details)"
        errorAlert.alertStyle = .warning
        errorAlert.addButton(withTitle: "OK")
        errorAlert.addButton(withTitle: "Open Settings")
        
        let errorResponse = errorAlert.runModal()
        if errorResponse == .alertSecondButtonReturn {
            openFullDiskAccessSettings()
        }
    }
    
    private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func applyTag(_ fossil: FossilItem, tagColor: FinderTagColor) {
        do {
            try (fossil.url as NSURL).setResourceValue(
                [tagColor.finderTagName],
                forKey: .tagNamesKey
            )
            fossil.action = .tagged(tagColor.nsColor)
        } catch {
            print("Tagging error: \(error)")
        }
    }
    
    func moveMultipleToTrash(_ items: [FossilItem]) {
        for item in items { moveToTrash(item) }
    }
    
    func applyTagToMultiple(_ items: [FossilItem], tagColor: FinderTagColor) {
        for item in items { applyTag(item, tagColor: tagColor) }
    }
    
    func revealInFinder(_ fossil: FossilItem) {
        NSWorkspace.shared.selectFile(fossil.url.path, inFileViewerRootedAtPath: fossil.url.deletingLastPathComponent().path)
    }
    
    func clearIdentificationCache() async {
        await identifierService.clearAllCache()
    }
}
