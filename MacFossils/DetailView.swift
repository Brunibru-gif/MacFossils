import SwiftUI

struct DetailView: View {
    @ObservedObject var fossil: FossilItem
    @EnvironmentObject var scanner: FossilScanner
    @State private var showTagPicker = false
    @State private var showTrashConfirm = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: fossil.category.systemIcon)
                                    .font(.title2)
                                    .foregroundStyle(Color(fossil.category.color))
                                
                                Text(fossil.name)
                                    .font(.title2.bold())
                                    .lineLimit(2)
                            }
                            
                            HStack(spacing: 6) {
                                RiskPill(risk: fossil.risk)
                                
                                if fossil.status == .orphan {
                                    Label("Orphan – no app found", systemImage: "questionmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                
                                if case .tagged(let color) = fossil.action {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color(color)).frame(width: 10, height: 10)
                                        Text("Tagged")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Text(fossil.formattedSize)
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], alignment: .leading, spacing: 12) {
                    
                    MetaCell(
                        icon: "folder.fill",
                        label: "Category",
                        value: fossil.category.rawValue,
                        color: Color(fossil.category.color)
                    )
                    
                    MetaCell(
                        icon: "tag.fill",
                        label: "Bundle ID",
                        value: fossil.bundleIdentifier ?? "Not found",
                        color: fossil.bundleIdentifier != nil ? .blue : .red
                    )
                    
                    if let appName = fossil.matchedAppName {
                        MetaCell(
                            icon: "app.fill",
                            label: "Associated App",
                            value: appName,
                            color: .green
                        )
                    }
                    
                    if let days = fossil.daysSinceLastUse {
                        MetaCell(
                            icon: "clock.fill",
                            label: "Last used",
                            value: fossil.formattedLastOpened,
                            color: days > 180 ? .orange : .secondary
                        )
                    }
                    
                    if let date = fossil.creationDate {
                        MetaCell(
                            icon: "calendar",
                            label: "Created",
                            value: date.formatted(.dateTime.day().month().year()),
                            color: .secondary
                        )
                    }
                    
                    if let date = fossil.lastModified {
                        MetaCell(
                            icon: "pencil.circle.fill",
                            label: "Last modified",
                            value: date.formatted(.dateTime.day().month().year()),
                            color: .secondary
                        )
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("Path", systemImage: "map.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    
                    Text(fossil.url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                }
                
                if let days = fossil.daysSinceLastUse, days > 180 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not used for a long time")
                                .font(.caption.bold())
                            Text("This item hasn't been opened or used for \(days) days.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer(minLength: 16)
                
                VStack(spacing: 10) {
                    Button(action: { scanner.revealInFinder(fossil) }) {
                        Label("Show in Finder", systemImage: "folder.badge.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { showTagPicker = true }) {
                        Label("Tag with color", systemImage: "tag.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $showTagPicker) {
                        TagActionView(fossil: fossil)
                            .environmentObject(scanner)
                    }
                    
                    Button(role: .destructive) {
                        showTrashConfirm = true
                    } label: {
                        Label("Move to Trash", systemImage: "trash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .confirmationDialog(
                        "Move '\(fossil.name)' to Trash?",
                        isPresented: $showTrashConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Move to Trash", role: .destructive) {
                            scanner.moveToTrash(fossil)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The item will be moved to Trash. You can restore it from there.")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(fossil.name)
    }
}

// MARK: - Supporting Views

struct RiskPill: View {
    let risk: FossilRisk
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: risk.icon)
            Text(risk.rawValue)
        }
        .font(.caption.bold())
        .foregroundStyle(Color(risk.color))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(risk.color).opacity(0.12))
        .cornerRadius(6)
    }
}

struct MetaCell: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }
}
