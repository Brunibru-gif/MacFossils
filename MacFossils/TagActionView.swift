import SwiftUI

struct TagActionView: View {
    @ObservedObject var fossil: FossilItem
    @EnvironmentObject var scanner: FossilScanner
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Finder Tag")
                .font(.headline)
            
            Text("The tag will be visible in Finder and helps you categorize items without deleting them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                ForEach(FinderTagColor.allCases) { tagColor in
                    Button {
                        scanner.applyTag(fossil, tagColor: tagColor)
                        dismiss()
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color(tagColor.nsColor))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if case .tagged(let color) = fossil.action,
                                       color == tagColor.nsColor {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.caption.bold())
                                    }
                                }
                                .shadow(color: Color(tagColor.nsColor).opacity(0.4), radius: 4, y: 2)
                            
                            Text(tagColor.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel", action: { dismiss() })
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }
}
