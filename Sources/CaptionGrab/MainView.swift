import AppKit
import CaptionGrabCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var model: AppModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            linkEntry
            HStack {
                Spacer()
                Button(action: model.setupChromeExtension) {
                    Label("Set up Chrome extension", systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(.bordered)
            }
            feedback
            transcriptPanel
            historyPanel
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("CaptionGrab").font(.largeTitle.bold())
                Text("Get an English YouTube transcript and save it your way.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var linkEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YouTube link").font(.headline)
            HStack(spacing: 10) {
                TextField("Paste or drag a YouTube link here", text: $model.inputURL)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onSubmit { fetch() }
                    .onDrop(of: [UTType.url.identifier, UTType.plainText.identifier], isTargeted: nil, perform: acceptDrop)
                Button(action: fetch) {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                        Text("Fetching…")
                    } else {
                        Label("Get transcript", systemImage: "text.magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading || model.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Supports video, Shorts, live, and short links.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isSummaryElement)
        } else if let notice = model.noticeMessage {
            Label(notice, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript").font(.headline)
                if let type = model.captionTypeDescription {
                    Text(type)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Button(action: model.copyAll) {
                    Label("Copy all", systemImage: "doc.on.doc")
                }
                .disabled(model.transcript == nil)
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.label) { model.save(format) }
                    }
                } label: {
                    Label("Save as \(model.preferredFormat == .markdown ? "Markdown" : "Word")", systemImage: "square.and.arrow.down")
                }
                .disabled(model.transcript == nil)
            }

            ScrollView {
                if let transcript = model.transcript {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(verbatim: transcript.videoTitle)
                            .font(.title2.bold())
                            .textSelection(.enabled)
                        Text("YouTube Video url: \(transcript.videoURL.absoluteString)")
                            .font(.callout)
                            .textSelection(.enabled)
                        Divider()
                        ForEach(Array(transcript.cues.enumerated()), id: \.offset) { _, cue in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cue.displayTimestamp)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(verbatim: cue.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                } else {
                    ContentUnavailableView(
                        model.isLoading ? "Fetching captions" : "No transcript yet",
                        systemImage: model.isLoading ? "arrow.down.doc" : "captions.bubble",
                        description: Text(model.isLoading ? "CaptionGrab is requesting the title and English captions from YouTube." : "Paste a YouTube link above to get started.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 230)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
        .frame(maxHeight: .infinity)
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent videos").font(.headline)
                Spacer()
                if !model.history.isEmpty {
                    Button("Clear") { model.clearHistory() }
                        .buttonStyle(.link)
                }
            }
            if model.history.isEmpty {
                Text("Your recent list is stored on this Mac only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.history) { item in
                            Button {
                                model.loadRecent(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text(item.lastFetchedAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(width: 190, alignment: .leading)
                                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .help(item.videoURL.absoluteString)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func fetch() {
        inputFocused = false
        Task { await model.fetchTranscript() }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                guard let url = object else { return }
                Task { @MainActor in model.inputURL = url.absoluteString }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                Task { @MainActor in model.inputURL = text }
            }
            return true
        }
        return false
    }
}
