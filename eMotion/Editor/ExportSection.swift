import SwiftUI
import AppKit
import MotionModel
import MotionExport
import Theme

/// The composition's export settings, under its own settings in the
/// inspector. The button asks where to save; so does File > Export (⌘E),
/// with the same settings.
struct ExportSection: View {
    @Bindable var session: ExportSession
    let composition: Composition
    /// Whether anything in the project makes a sound.
    let hasSound: Bool
    @Binding var isOpen: Bool

    private var settings: ExportSettings { session.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Export", isOpen: isOpen) { isOpen.toggle() }
            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    MenuRow(label: "Format", value: settings.format.shortTitle, entries: formatEntries)
                        .help("H.264, HEVC and ProRes 422 have no transparency, so a transparent background "
                              + "exports as its colour. HEVC with alpha, ProRes 4444 and PNG keep it. "
                              + "A PNG is the frame under the playhead, or in Design, the layout as designed.")
                    MenuRow(label: "Size", value: sizeTitle(settings.scale), entries: sizeEntries)
                    if settings.format.hasQuality {
                        MenuRow(label: "Quality", value: settings.quality.title, entries: qualityEntries)
                            .help("Lower quality makes a smaller file. Flat colour and clean edges look the "
                                  + "same at any setting; gradients and blur show the difference first.")
                    }
                    if hasSound && settings.format.isMovie {
                        ToggleRow(label: "Audio", isOn: settings.includesAudio) { session.settings.includesAudio.toggle() }
                            .help("Includes the sound of the project's video and audio layers.")
                    }
                    PanelButton(title: "Export…", icon: .export, disabled: session.isExporting) {
                        session.request(nil)
                    }
                    .help("Choose where to save it. (⌘E)")
                }
                .padding(.horizontal, Theme.panelPad)
                .padding(.bottom, Theme.panelPad)
                .transition(.opacity)
            }
        }
    }

    private func formatEntries() -> [MenuEntry] {
        let groups: [[ExportFormat]] = [[.h264, .hevc], [.hevcAlpha, .proRes422, .proRes4444], [.png]]
        return groups.enumerated().flatMap { index, formats in
            (index > 0 ? [MenuEntry.separator] : []) + formats.map { format in
                MenuEntry.item(format.title, checked: format == settings.format) { session.settings.format = format }
            }
        }
    }

    private func sizeTitle(_ scale: Double) -> String {
        var s = settings
        s.scale = scale
        let (width, height) = s.pixelSize(of: composition)
        return "\(width) × \(height)"
    }

    private func sizeEntries() -> [MenuEntry] {
        ExportSettings.scales.map { scale in
            MenuEntry.item("\(Int(scale * 100))%   \(sizeTitle(scale))", checked: scale == settings.scale) {
                session.settings.scale = scale
            }
        }
    }

    private func qualityEntries() -> [MenuEntry] {
        ExportQuality.allCases.map { quality in
            MenuEntry.item(quality.title, checked: quality == settings.quality) { session.settings.quality = quality }
        }
    }
}

/// A small card over the top of the canvas while an export runs, with its
/// progress and a way to stop it, and for a few seconds after, a way to the
/// file. It floats rather than living in the Export section so it stays in
/// sight whatever is selected.
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
