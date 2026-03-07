import SwiftUI

struct ContentView: View {
    @EnvironmentObject var scanner: FossilScanner
    @State private var selectedFossil: FossilItem? = nil
    @State private var showingDetail = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            FossilListView(selectedFossil: $selectedFossil)
                .padding(.leading, 8)
                .padding(.top, 4)
                .navigationSplitViewColumnWidth(min: 600, ideal: 700, max: 800)
        } detail: {
            Group {
                if let fossil = selectedFossil {
                    DetailView(fossil: fossil)
                } else {
                    EmptyDetailView()
                }
            }
            .navigationSplitViewColumnWidth(min: 600, ideal: 700, max: 800)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { Task { await scanner.startScan() } }) {
                    Label(scanner.isScanning ? "Scanning..." : "Start Scan", systemImage: "arrow.clockwise")
                }
                HStack(spacing: 6) {
                    Image(systemName: "fossil.shell")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                    Text("MacFossils")
                        .font(.headline)
                }
                .padding(.trailing, 8)
                
                .disabled(scanner.isScanning)
                
                if scanner.isScanning || scanner.isScanningApps {
                    ProgressView(value: scanner.scanProgress)
                        .frame(width: 180)
                        .padding(.trailing, 8)
                }
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                if !scanner.fossils.isEmpty {
                    Text("\(scanner.filteredFossils.count) items · \(ByteCountFormatter.string(fromByteCount: scanner.totalSize, countStyle: .file))")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.horizontal, 10)
                }
            }
        }
        .navigationTitle("")
    }
}

// MARK: - Fossil List View

struct FossilListView: View {
    @EnvironmentObject var scanner: FossilScanner
    @Binding var selectedFossil: FossilItem?
    @State private var sortOrder = SortOrder.riskDescending
    @State private var selectedItems = Set<UUID>()
    @State private var showBulkActions = false
    
    enum SortOrder: String, CaseIterable {
        case riskDescending = "Risk (high → low)"
        case sizeDescending = "Size (large → small)"
        case nameAscending = "Name (A → Z)"
        case lastUsedDescending = "Last used (oldest → newest)"
    }
    
    var sortedFossils: [FossilItem] {
        let fossils = scanner.filteredFossils
        switch sortOrder {
        case .riskDescending:
            return fossils.sorted { a, b in
                let riskOrder: [FossilRisk] = [.review, .caution, .safe]
                let ai = riskOrder.firstIndex(of: a.risk) ?? 0
                let bi = riskOrder.firstIndex(of: b.risk) ?? 0
                return ai < bi
            }
        case .sizeDescending:
            return fossils.sorted { $0.fileSize > $1.fileSize }
        case .nameAscending:
            return fossils.sorted { $0.name < $1.name }
        case .lastUsedDescending:
            return fossils.sorted {
                let dateA = $0.lastOpened ?? $0.lastUsed ?? $0.lastModified ?? Date.distantPast
                let dateB = $1.lastOpened ?? $1.lastUsed ?? $1.lastModified ?? Date.distantPast
                return dateA < dateB
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SearchBar(text: $scanner.searchText)
                
                Spacer()
                
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            HStack(spacing: 8) {
                FilterChip(
                    label: "Orphans only",
                    icon: "questionmark.circle",
                    isActive: $scanner.filterOrphansOnly
                )
                FilterChip(
                    label: "Not used recently",
                    icon: "clock.badge.xmark",
                    isActive: $scanner.filterStaleOnly
                )
                FilterChip(
                    label: "Hide installed apps",
                    icon: "eye.slash",
                    isActive: $scanner.hideInstalledApps
                )
                
                if scanner.filterStaleOnly {
                    HStack(spacing: 4) {
                        Text("from")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper(
                            "\(scanner.staleThresholdDays) days",
                            value: $scanner.staleThresholdDays,
                            in: 30...730,
                            step: 30
                        )
                        .labelsHidden()
                        Text("\(scanner.staleThresholdDays)d")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if !selectedItems.isEmpty {
                    Button("Bulk actions (\(selectedItems.count))") {
                        showBulkActions = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            Divider()
            
            if scanner.hasStartedScan && !scanner.hasScanned {
                ScanningPlaceholder()
            } else if !scanner.hasScanned {
                WelcomeView()
            } else if sortedFossils.isEmpty {
                EmptyResultsView()
            } else {
                List(sortedFossils, selection: $selectedFossil) { fossil in
                    FossilRowView(fossil: fossil)
                        .tag(fossil)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showBulkActions) {
            BulkActionSheet(
                count: selectedItems.count,
                items: scanner.filteredFossils.filter { selectedItems.contains($0.id) },
                onDismiss: { showBulkActions = false }
            )
            .environmentObject(scanner)
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var scanner: FossilScanner
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "fossil.shell")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse)
            
            VStack(spacing: 8) {
                Text("Welcome to MacFossils")
                    .font(.title2.bold())
                
                Text("Scan your Mac for leftovers\nfrom uninstalled apps.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { Task { await scanner.startScan() } }) {
                Label("Start Scan", systemImage: "magnifyingglass")
                    .font(.headline)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
    }
}

// MARK: - Scanning Placeholder

struct ScanningPlaceholder: View {
    @EnvironmentObject var scanner: FossilScanner
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .padding(15)
            Text(scanner.scanStatus)
                .font(.headline)
            Text("Searching for app leftovers... this can take a few minutes...")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Empty Results

struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No leftovers found")
                .font(.headline)
            Text("No results match your filters.")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Empty Detail

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(15)
            Text("Select an item")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click an item on the left\nto see details.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search...", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
        )
        .frame(maxWidth: 240)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let icon: String
    @Binding var isActive: Bool
    
    var body: some View {
        Button(action: { isActive.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isActive ? .white : .primary)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bulk Action Sheet

struct BulkActionSheet: View {
    let count: Int
    let items: [FossilItem]
    let onDismiss: () -> Void
    @EnvironmentObject var scanner: FossilScanner
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Bulk action for \(count) items")
                .font(.title2.bold())
            
            Text("What should happen to the selected items?")
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                Button(role: .destructive) {
                    scanner.moveMultipleToTrash(items)
                    onDismiss()
                } label: {
                    Label("Move all to Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                
                ForEach([FinderTagColor.red, .orange, .yellow, .green, .blue], id: \.self) { color in
                    Button {
                        scanner.applyTagToMultiple(items, tagColor: color)
                        onDismiss()
                    } label: {
                        Circle()
                            .fill(Color(color.nsColor))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Mark with \(color.rawValue)")
                }
                
                Button("Cancel", action: onDismiss)
            }
        }
        .padding(30)
        .frame(minWidth: 400)
    }
}
