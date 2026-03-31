import AppKit
import SwiftUI

struct AssetCardView: View {
    @EnvironmentObject private var viewModel: ReviewViewModel

    let group: ReviewGroup
    let itemID: String
    let isHighlighted: Bool
    let imageHeight: CGFloat
    let onSelected: () -> Void

    @State private var image: NSImage?

    private var decision: FileDecision {
        viewModel.decision(for: itemID)
    }

    private var decisionBorderColor: Color {
        switch decision {
        case .keep:
            return Color.green.opacity(0.70)
        case .delete:
            return Color.red.opacity(0.72)
        case .sendAndDelete:
            return Color.yellow.opacity(0.78)
        }
    }

    private var decisionBadgeTitle: String {
        switch decision {
        case .keep:
            return "KEEP"
        case .delete:
            return "DELETE"
        case .sendAndDelete:
            return "SEND+DELETE"
        }
    }

    private var decisionBadgeColor: Color {
        switch decision {
        case .keep:
            return Color.green.opacity(0.86)
        case .delete:
            return Color.red.opacity(0.88)
        case .sendAndDelete:
            return Color.yellow.opacity(0.90)
        }
    }

    var body: some View {
        let baseBackground = Color(red: 0.985, green: 0.99, blue: 1.0)
        let cardBackground = isHighlighted ? Color.accentColor.opacity(0.16) : baseBackground

        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.91, green: 0.95, blue: 1.0).opacity(0.5))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    ProgressView()
                }

                HStack {
                    badgeStrip
                    Spacer()
                    decisionBadge
                }
                .padding(8)
            }
            .frame(height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(viewModel.itemFileName(itemID))
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(viewModel.itemDateLabel(itemID))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(viewModel.itemByteSizeLabel(itemID))
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Keep") {
                    viewModel.setDecision(.keep, for: itemID)
                    onSelected()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Button("Delete") {
                    viewModel.setDecision(.delete, for: itemID)
                    onSelected()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Button("Send+Delete") {
                    viewModel.setDecision(.sendAndDelete, for: itemID)
                    onSelected()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Spacer()
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(decisionBorderColor, lineWidth: 2)
        )
        .overlay(alignment: .leading) {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 5)
                    .padding(.vertical, 8)
                    .padding(.leading, 3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(isHighlighted ? 0.9 : 0), lineWidth: isHighlighted ? 1.5 : 0)
                .padding(1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(isHighlighted ? 1 : 0), lineWidth: isHighlighted ? 5 : 0)
        )
        .shadow(color: isHighlighted ? Color.accentColor.opacity(0.4) : .clear, radius: isHighlighted ? 12 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onSelected()
        }
        .onHover { hovering in
            if hovering && viewModel.shouldAcceptHoverHighlight() {
                onSelected()
            }
        }
        .task(id: "\(itemID)-\(Int(imageHeight))") {
            if let quick = await viewModel.thumbnail(for: itemID, maxPixel: max(240, imageHeight * 1.4)) {
                image = quick
            }
            if let highQuality = await viewModel.thumbnail(for: itemID, maxPixel: max(620, imageHeight * 2.0)) {
                image = highQuality
            }
        }
    }

    @ViewBuilder
    private var decisionBadge: some View {
        Text(decisionBadgeTitle)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(decisionBadgeColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var badgeStrip: some View {
        let badges = viewModel.mediaBadges(for: itemID)
        if badges.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.68))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }
}
