import SwiftUI

struct FossilRowView: View {
    @ObservedObject var fossil: FossilItem
    @EnvironmentObject var scanner: FossilScanner
    @State private var isHovering = false
    @State private var showTagPicker = false
    @State private var showTrashConfirm = false
    
    var body: some View {
        HStack(spacing: 10) {
            RiskBadge(risk: fossil.risk)
            
            Image(systemName: fossil.category.systemIcon)
                .foregroundStyle(Color(fossil.category.color))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(fossil.name)
                        .font(.body)
                        .lineLimit(1)
                    
                    if fossil.status == .orphan {
                        Text("ORPHAN")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .cornerRadius(3)
                    } else if let appName = fossil.matchedAppName {
                        Text("→ \(appName)")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .cornerRadius(3)
                    }
                    
                    if case .tagged(let color) = fossil.action {
                        Circle()
                            .fill(Color(color))
                            .frame(width: 10, height: 10)
                    }
                }
                
                HStack(spacing: 8) {
                    if fossil.matchedAppName == "Unknown" {
                        Text("Unknown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let bundleID = fossil.bundleIdentifier {
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Unknown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let days = fossil.daysSinceLastUse {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(days > 365 ? "\(days / 365)y \(days % 365)d ago" : "\(days)d ago")
                            .font(.caption)
                            .foregroundStyle(days > 180 ? .orange : .secondary)
                    }
                }
            }
            
            Spacer()
            
            Text(fossil.formattedSize)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            
            if isHovering || showTrashConfirm {
                HStack(spacing: 4) {
                    Button {
                        scanner.revealInFinder(fossil)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Show in Finder")
                    
                    Button {
                        showTagPicker = true
                    } label: {
                        Image(systemName: "tag.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("Tag with color")
                    .popover(isPresented: $showTagPicker) {
                        TagActionView(fossil: fossil)
                            .environmentObject(scanner)
                    }
                    
                    Button(role: .destructive) {
                        showTrashConfirm = true
                    } label: {
                        Image(systemName: "trash.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Move to Trash")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Risk Badge

struct RiskBadge: View {
    let risk: FossilRisk
    
    var body: some View {
        Image(systemName: risk.icon)
            .foregroundStyle(Color(risk.color))
            .font(.system(size: 12))
            .frame(width: 16)
    }
}
