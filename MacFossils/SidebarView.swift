import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var scanner: FossilScanner
    
    private let iconColumnWidth: CGFloat = 18
    private let valueColumnWidth: CGFloat = 64
    private let minSidebarWidth: CGFloat = 300
    @State private var measuredWidth: CGFloat = 300
    
    private var liveTotalCount: Int {
        scanner.isScanning ? scanner.totalScannedItems : scanner.fossils.count
    }
    
    var body: some View {
        List(selection: $scanner.selectedCategory) {
            Section {
                let totalSize = scanner.fossils.reduce(0) { $0 + $1.fileSize }
                VStack(alignment: .leading, spacing: 8) {
                    SummaryRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        label: "Orphans",
                        value: "\(scanner.orphanCount)",
                        isDimmed: scanner.orphanCount == 0,
                        iconColumnWidth: iconColumnWidth,
                        valueColumnWidth: valueColumnWidth
                    )
                    SummaryRow(
                        icon: "folder.fill",
                        color: .blue,
                        label: "Total",
                        value: "\(liveTotalCount)",
                        isDimmed: liveTotalCount == 0,
                        iconColumnWidth: iconColumnWidth,
                        valueColumnWidth: valueColumnWidth
                    )
                    SummaryRow(
                        icon: "internaldrive.fill",
                        color: .green,
                        label: "Size",
                        value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file),
                        isDimmed: totalSize == 0,
                        iconColumnWidth: iconColumnWidth,
                        valueColumnWidth: valueColumnWidth
                    )
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 8))
            } header: {
                Text("Summary")
            }
            
            Section {
                Label {
                    HStack {
                        Text("All Categories")
                        Spacer()
                        if liveTotalCount > 0 {
                            Text("\(liveTotalCount)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: valueColumnWidth, alignment: .trailing)
                        }
                    }
                } icon: {
                    Image(systemName: "tray.2.fill")
                        .frame(width: iconColumnWidth, alignment: .center)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
                .padding(.trailing, 8)
                .font(.callout)
                .readWidth()
                .listRowBackground(
                    Group {
                        if scanner.selectedCategory == nil {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                        } else {
                            Color.clear
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .onTapGesture {
                    scanner.selectedCategory = nil
                }
                
                ForEach(FossilCategory.allCases) { category in
                    let count = scanner.categoryCounts[category] ?? 0
                    Label {
                        HStack {
                            Text(category.rawValue)
                            Spacer()
                            Text("\(count)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: valueColumnWidth, alignment: .trailing)
                        }
                    } icon: {
                        Image(systemName: category.systemIcon)
                            .foregroundStyle(Color(category.color))
                            .frame(width: iconColumnWidth, alignment: .center)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                    .font(.callout)
                    .opacity(count == 0 ? 0.45 : 1)
                    .readWidth()
                    .listRowBackground(
                        Group {
                            if scanner.selectedCategory == category {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.15))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .onTapGesture {
                        scanner.selectedCategory = category
                    }
                }
            } header: {
                Text("Categories")
            }
            
            Section {
                ForEach([FossilRisk.review, .caution, .safe], id: \.rawValue) { risk in
                    let count = scanner.fossils.filter { $0.risk == risk }.count
                    HStack {
                        Image(systemName: risk.icon)
                            .foregroundStyle(Color(risk.color))
                            .frame(width: iconColumnWidth, alignment: .center)
                        Text(risk.rawValue)
                        Spacer()
                        Text("\(count)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: valueColumnWidth, alignment: .trailing)
                    }
                    .padding(.trailing, 8)
                    .font(.callout)
                    .opacity(count == 0 ? 0.4 : 1)
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 8))
                    .readWidth()
                }
            } header: {
                Text("By Risk")
            }
        }
        .listStyle(.sidebar)
        .onPreferenceChange(SidebarWidthPreferenceKey.self) { value in
            if value > measuredWidth {
                measuredWidth = value
            }
        }
        .frame(minWidth: minSidebarWidth, idealWidth: max(minSidebarWidth, measuredWidth))
    }
}

struct SummaryRow: View {
    let icon: String
    let color: NSColor
    let label: String
    let value: String
    let isDimmed: Bool
    let iconColumnWidth: CGFloat
    let valueColumnWidth: CGFloat
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color(color))
                .frame(width: iconColumnWidth, alignment: .center)
            Text(label)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(width: 110, alignment: .leading)
            Spacer(minLength: 6)
            Text(value)
                .font(.callout.monospacedDigit())
                .frame(width: valueColumnWidth, alignment: .trailing)
        }
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .opacity(isDimmed ? 0.45 : 1)
        .font(.callout)
        .readWidth()
    }
}

private struct SidebarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 240
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ReadWidthModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SidebarWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
    }
}

private extension View {
    func readWidth() -> some View {
        modifier(ReadWidthModifier())
    }
}
