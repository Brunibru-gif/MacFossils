import Foundation
import AppKit

// MARK: - Enums

enum FossilCategory: String, CaseIterable, Identifiable {
    case applicationSupport = "Application Support"
    case applicationScripts = "Application Scripts"
    case launchAgents = "LaunchAgents"
    case launchDaemons = "LaunchDaemons"
    case preferences = "Preferences"
    case caches = "Caches"
    case containers = "Containers"
    case savedState = "Saved Application State"
    case logs = "Logs"
    case cronJobs = "Cron Jobs"
    case other = "Other"
    
    var id: String { rawValue }
    
    var systemIcon: String {
        switch self {
        case .applicationSupport: return "folder.fill"
        case .applicationScripts: return "scroll.fill"
        case .launchAgents: return "bolt.fill"
        case .launchDaemons: return "gearshape.2.fill"
        case .preferences: return "slider.horizontal.3"
        case .caches: return "internaldrive.fill"
        case .containers: return "shippingbox.fill"
        case .savedState: return "clock.arrow.circlepath"
        case .logs: return "doc.text.fill"
        case .cronJobs: return "calendar.badge.clock"
        case .other: return "questionmark.folder.fill"
        }
    }
    
    var color: NSColor {
        switch self {
        case .applicationSupport: return .systemBlue
        case .applicationScripts: return .systemPurple
        case .launchAgents: return .systemOrange
        case .launchDaemons: return .systemRed
        case .preferences: return .systemTeal
        case .caches: return .systemGreen
        case .containers: return .systemIndigo
        case .savedState: return .systemBrown
        case .logs: return .systemGray
        case .cronJobs: return .systemYellow
        case .other: return .secondaryLabelColor
        }
    }
}

enum FossilStatus {
    case orphan
    case stale
    case unknown
}

enum FossilAction {
    case none
    case tagged(NSColor)
    case trashed
}

enum FossilRisk: String {
    case safe = "Safe"
    case caution = "Caution"
    case review = "Review"
    
    var color: NSColor {
        switch self {
        case .safe: return .systemGreen
        case .caution: return .systemOrange
        case .review: return .systemRed
        }
    }
    
    var icon: String {
        switch self {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .review: return "xmark.circle.fill"
        }
    }
}

// MARK: - FossilItem

class FossilItem: ObservableObject, Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let category: FossilCategory
    var status: FossilStatus
    var bundleIdentifier: String?
    var matchedAppName: String?
    let fileSize: Int64
    let lastModified: Date?
    let lastOpened: Date?
    let lastUsed: Date?
    let creationDate: Date?
    let risk: FossilRisk
    
    @Published var action: FossilAction = .none
    @Published var isSelected: Bool = false
    
    // MARK: - Hashable Conformance
    
    static func == (lhs: FossilItem, rhs: FossilItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var name: String { url.lastPathComponent }
    
    var daysSinceLastUse: Int? {
        guard let date = lastOpened ?? lastModified else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var formattedLastOpened: String {
        guard let date = lastOpened else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var isOrphan: Bool { status == .orphan }
    
    init(url: URL,
         category: FossilCategory,
         status: FossilStatus,
         bundleIdentifier: String? = nil,
         matchedAppName: String? = nil,
         fileSize: Int64 = 0,
         lastModified: Date? = nil,
         lastOpened: Date? = nil,
         lastUsed: Date? = nil,
         creationDate: Date? = nil,
         risk: FossilRisk = .caution) {
        self.url = url
        self.category = category
        self.status = status
        self.bundleIdentifier = bundleIdentifier
        self.matchedAppName = matchedAppName
        self.fileSize = fileSize
        self.lastModified = lastModified
        self.lastOpened = lastOpened
        self.lastUsed = lastUsed
        self.creationDate = creationDate
        self.risk = risk
    }
}

// MARK: - Finder Tag Colors

enum FinderTagColor: String, CaseIterable, Identifiable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case gray = "Gray"
    
    var id: String { rawValue }
    
    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }
    
    var finderTagName: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .gray: return "Gray"
        }
    }
}
