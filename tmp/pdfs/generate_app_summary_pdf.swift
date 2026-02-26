import AppKit
import CoreGraphics
import Foundation

struct TextBlock {
    let text: String
    let font: NSFont
    let color: NSColor
    let paragraph: NSParagraphStyle
    let spacingAfter: CGFloat
}

let outputPath: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = scriptDirectory.deletingLastPathComponent().deletingLastPathComponent()
    return repoRoot
        .appendingPathComponent("output")
        .appendingPathComponent("pdf")
        .appendingPathComponent("photo_sort_helper_app_summary.pdf")
        .path
}()

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let pageWidth: CGFloat = 612
let pageHeight: CGFloat = 792
let margin: CGFloat = 42
let contentWidth: CGFloat = pageWidth - (margin * 2)

var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

guard
    let consumer = CGDataConsumer(url: outputURL as CFURL),
    let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
else {
    fputs("Failed to create PDF context\n", stderr)
    exit(1)
}

context.beginPDFPage(nil)
context.setFillColor(NSColor.white.cgColor)
context.fill(mediaBox)

let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let bodyParagraph: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    style.alignment = .left
    return style
}()

let bulletParagraph: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    style.alignment = .left
    style.firstLineHeadIndent = 0
    style.headIndent = 14
    return style
}()

let headerParagraph: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    style.alignment = .left
    return style
}()

func makeBlock(text: String, font: NSFont, color: NSColor = .black, paragraph: NSParagraphStyle, spacingAfter: CGFloat) -> TextBlock {
    TextBlock(text: text, font: font, color: color, paragraph: paragraph, spacingAfter: spacingAfter)
}

func attributedString(for block: TextBlock) -> NSAttributedString {
    NSAttributedString(
        string: block.text,
        attributes: [
            .font: block.font,
            .foregroundColor: block.color,
            .paragraphStyle: block.paragraph
        ]
    )
}

func blockHeight(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
    ceil(
        attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
    )
}

var blocks: [TextBlock] = []
blocks.append(makeBlock(
    text: "Photo Sort Helper - App Summary",
    font: NSFont.boldSystemFont(ofSize: 18),
    paragraph: headerParagraph,
    spacingAfter: 4
))
blocks.append(makeBlock(
    text: "One-page summary generated from repository evidence.",
    font: NSFont.systemFont(ofSize: 10),
    color: NSColor(calibratedWhite: 0.32, alpha: 1.0),
    paragraph: bodyParagraph,
    spacingAfter: 14
))

blocks.append(makeBlock(
    text: "What It Is",
    font: NSFont.boldSystemFont(ofSize: 13),
    paragraph: headerParagraph,
    spacingAfter: 6
))
blocks.append(makeBlock(
    text: "Photo Sort Helper is a macOS SwiftUI app that helps users review bursts and near-duplicate items in Apple Photos. It is safety-first: items default to keep, and the app queues marked items into review albums instead of deleting from the library.",
    font: NSFont.systemFont(ofSize: 10.5),
    paragraph: bodyParagraph,
    spacingAfter: 10
))

blocks.append(makeBlock(
    text: "Who It Is For",
    font: NSFont.boldSystemFont(ofSize: 13),
    paragraph: headerParagraph,
    spacingAfter: 6
))
blocks.append(makeBlock(
    text: "Primary persona: a macOS Apple Photos user who wants faster duplicate/burst triage while keeping final delete decisions manual.",
    font: NSFont.systemFont(ofSize: 10.5),
    paragraph: bodyParagraph,
    spacingAfter: 10
))

blocks.append(makeBlock(
    text: "What It Does",
    font: NSFont.boldSystemFont(ofSize: 13),
    paragraph: headerParagraph,
    spacingAfter: 6
))
let featureBullets = [
    "Requests PhotoKit access and loads album/all-photo scan scopes.",
    "Scans all photos or a selected album with optional date range and asset cap.",
    "Builds time-near clusters, then forms similarity groups using Vision feature-print distance and burst IDs.",
    "Optionally includes videos; videos are reviewable but excluded from auto-pick quality scoring.",
    "Suggests best shots and singleton low-quality discards using face/framing/sharpness/lighting/color signals, with lightweight learning from reviewed groups.",
    "Provides per-group keep/discard controls, keyboard navigation, image/video preview, and estimated reclaim size.",
    "Queues selected items into \"Files to Edit\" or \"Files to Manually Delete\" albums for manual follow-up in Photos."
]
for bullet in featureBullets {
    blocks.append(makeBlock(
        text: "- \(bullet)",
        font: NSFont.systemFont(ofSize: 10),
        paragraph: bulletParagraph,
        spacingAfter: 3
    ))
}
blocks.append(makeBlock(
    text: "",
    font: NSFont.systemFont(ofSize: 10),
    paragraph: bodyParagraph,
    spacingAfter: 4
))

blocks.append(makeBlock(
    text: "How It Works (Architecture)",
    font: NSFont.boldSystemFont(ofSize: 13),
    paragraph: headerParagraph,
    spacingAfter: 6
))
let architectureBullets = [
    "UI: PhotoSortHelperApp + RootView render controls/review panes and bind to a shared ReviewViewModel.",
    "Orchestration: ReviewViewModel manages scan settings, progress, grouping state, keep/discard selections, keyboard navigation, and session persistence.",
    "Data/IO: PhotoLibraryService wraps PhotoKit operations (authorization, album and asset fetch, thumbnails, AVAsset loading, and album mutations).",
    "Analysis: SimilarityScanner pulls assets from PhotoLibraryService, clusters by timestamp, computes Vision feature prints for images, builds similarity components, and returns review groups plus auto-pick suggestions.",
    "Data flow: User starts scan -> ReviewViewModel creates ScanSettings -> SimilarityScanner returns groups/scores -> UI captures review decisions -> explicit queue actions add assets to Photos albums."
]
for bullet in architectureBullets {
    blocks.append(makeBlock(
        text: "- \(bullet)",
        font: NSFont.systemFont(ofSize: 10),
        paragraph: bulletParagraph,
        spacingAfter: 3
    ))
}
blocks.append(makeBlock(
    text: "",
    font: NSFont.systemFont(ofSize: 10),
    paragraph: bodyParagraph,
    spacingAfter: 4
))

blocks.append(makeBlock(
    text: "How To Run (Minimal)",
    font: NSFont.boldSystemFont(ofSize: 13),
    paragraph: headerParagraph,
    spacingAfter: 6
))
let runBullets = [
    "Install Xcode and select it as the active developer directory (README includes the exact xcode-select command).",
    "Open Package.swift in Xcode from the repository root.",
    "Run the PhotoSortHelper scheme, then allow Photos access when prompted by macOS.",
    "Choose source/settings and click \"Scan for Similar Photos\" to begin review."
]
for bullet in runBullets {
    blocks.append(makeBlock(
        text: "- \(bullet)",
        font: NSFont.systemFont(ofSize: 10),
        paragraph: bulletParagraph,
        spacingAfter: 3
    ))
}

var y = pageHeight - margin
let availableBottom = margin
var overflowDetected = false

for block in blocks {
    let attributed = attributedString(for: block)
    let height = max(0, blockHeight(attributed, width: contentWidth))

    if !block.text.isEmpty {
        let nextY = y - height
        if nextY < availableBottom {
            overflowDetected = true
            break
        }

        let rect = CGRect(x: margin, y: nextY, width: contentWidth, height: height)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        y = nextY
    }

    y -= block.spacingAfter
}

NSGraphicsContext.restoreGraphicsState()
context.endPDFPage()
context.closePDF()

if overflowDetected {
    fputs("Content overflowed one page; reduce text before delivery.\n", stderr)
    exit(2)
}

print("Wrote \(outputPath)")
