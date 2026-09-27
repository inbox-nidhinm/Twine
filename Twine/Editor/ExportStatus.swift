import SwiftUI
import AppKit
import MotionModel
import MotionExport
import Theme

/// A small card over the top of the canvas while an export runs, with its
/// progress and a way to stop it, and for a few seconds after, a way to the
/// file. For exports made without the export panel (File > Export Current
/// Frame); the panel shows its own progress, and this stays hidden under it.
struct ExportStatus: View {
    let session: ExportSession

    var body: some View {
        Group {
            if let progress = session.progress {
                HStack(spacing: 8) {
                    ProgressTrack(value: progress)
                    Text("\(Int((progress * 100).rounded(.down)))%")
                        .font(ThemeFont.label)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, alignment: .trailing)
                    IconButton(icon: .close, help: "Cancel the export") { session.cancel() }
                }
                .help("Exporting")
            } else if let url = session.finished {
                HStack(spacing: 8) {
                    IconView(.check, size: 15)
                        .foregroundStyle(Theme.accent)
                    Text(url.lastPathComponent)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .leading)
                    PanelButton(title: "Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        session.dismissFinished()
                    }
                    .fixedSize()
                    IconButton(icon: .close, help: "Dismiss") { session.dismissFinished() }
                }
            }
        }
        // At its natural width, so a short file name makes a short card.
        .fixedSize()
        .padding(.leading, Theme.panelPad)
        .padding(.trailing, Theme.barPad)
        .padding(.vertical, Theme.barPad)
        .floatingPanel()
    }
}

/// A thin bar filled with the accent up to `value`, from 0 to 1.
private struct ProgressTrack: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(Theme.panelRaised)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(Theme.progressBar, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(width: Theme.cardWidth / 2, height: Theme.progressBar)
    }
}

/// A note over the top of the canvas, with a way to dismiss it.
struct NoticeCard: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(4)
                .frame(maxWidth: 420, alignment: .leading)
            IconButton(icon: .close, help: "Dismiss", action: dismiss)
        }
        .fixedSize()
        .padding(.leading, Theme.panelPad)
        .padding(.trailing, Theme.barPad)
        .padding(.vertical, Theme.barPad)
        .floatingPanel()
    }
}
