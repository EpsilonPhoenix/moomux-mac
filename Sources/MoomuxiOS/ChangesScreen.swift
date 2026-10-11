import DiffKit
import MoomuxKit
import SwiftUI

/// A session's changes against its merge base — what Review shows in tmux,
/// drawn natively. The phone gets this and the Mac does not: on a desk the
/// tmux window and the GUI diff tool (⌘D) are better than any viewer here,
/// while on a 6-inch screen a pager at 50 columns is the worse half.
///
/// Flat, not a tree, for MergeRight's reason: indentation costs width the
/// names want.
struct ChangesScreen: View {
    let app: AppState
    let sessionID: Session.ID

    var body: some View {
        content
            .navigationTitle(app.session(id: sessionID)?.name ?? "Changes")
            .navigationBarTitleDisplayMode(.inline)
            .task { await app.loadDiff(sessionID) }
            .refreshable { await app.loadDiff(sessionID) }
    }

    @ViewBuilder
    private var content: some View {
        switch app.diffs[sessionID] {
        case .none:
            ProgressView().controlSize(.small)
        case .some(.none):
            ContentUnavailableView("Not a git repository", systemImage: "folder.badge.questionmark")
        // Not when truncated: a first file over the cap alone sends no patch.
        case let .some(.some(diff)) where diff.files.isEmpty && !diff.truncated:
            ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                   description: Text("Nothing differs from the base branch."))
        case let .some(.some(diff)):
            List {
                Section {
                    let viewed = app.viewed(sessionID, in: diff.files)
                    ForEach(diff.files) { file in
                        let seen = viewed.wrappedValue.contains(file.id)
                        NavigationLink(value: Route.fileDiff(sessionID, file.path)) { row(file, viewed: seen) }
                            .swipeActions(edge: .leading) {
                                Button(seen ? "Unviewed" : "Viewed",
                                       systemImage: seen ? "eye.slash" : "checkmark") {
                                    if seen { viewed.wrappedValue.remove(file.id) }
                                    else { viewed.wrappedValue.insert(file.id) }
                                }
                                .tint(.accentColor)
                            }
                    }
                } header: {
                    // "HEAD" is the core saying no base branch shares history
                    // with this one — "vs HEAD" would read as a real comparison.
                    let against = diff.base == "HEAD" || diff.base.isEmpty
                        ? "Uncommitted changes only" : "Against \(diff.base)"
                    let seen = app.viewed(sessionID, in: diff.files).wrappedValue.count
                    Text(seen == 0 ? against : "\(against) · \(seen) of \(diff.files.count) viewed")
                } footer: {
                    if diff.truncated {
                        Text(diff.files.isEmpty
                             ? "Too large to send — the first file alone is over the limit."
                             : "Too large to send whole — the files after these were left out.")
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func row(_ file: FileChange, viewed: Bool) -> some View {
        let name = (file.path as NSString).lastPathComponent
        let dir = (file.path as NSString).deletingLastPathComponent
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if viewed {
                        Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Viewed")
                    }
                    Text(name).font(.body.monospaced()).lineLimit(1)
                        .foregroundStyle(viewed ? .secondary : .primary)
                }
                if let old = file.previousPath {
                    // A plain `mv` is +0 −0 — without this the row says nothing happened.
                    Text("renamed from \(old)").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                } else if !dir.isEmpty {
                    // Truncated from the head: the end of a path is the part
                    // that tells two files apart.
                    Text(dir).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            Spacer()
            if file.isBinary {
                Text("binary").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("+\(file.additions)").foregroundStyle(DiffTheme.added)
                Text("−\(file.deletions)").foregroundStyle(DiffTheme.removed)
            }
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .combine)
    }
}

/// One file. Looked up by path in its own `body`, like every other route here,
/// so a refresh on the list underneath redraws this too. The route's path is only
/// the seed: the stepper swaps the file in place rather than pushing another screen.
struct FileDiffScreen: View {
    let app: AppState
    let sessionID: Session.ID
    @State private var selection: FileChange.ID?
    /// Pressed on the last file: leaves the Changes list behind as well.
    let finished: () -> Void

    /// A re-indent is noise on a phone more often than on a desk: every
    /// whitespace-only line costs a full row of a narrow screen.
    @AppStorage("hidesWhitespaceChanges") private var hidesWhitespace = false

    // Find, across the whole change. The query outlives a file swap — that is
    // what lets stepping past the last match carry on into the next file.
    @State private var query = ""
    @State private var searching = false
    @State private var matches: [DiffFind.Match] = []
    @State private var current = 0
    /// "12 of 40" across files; nil while counting.
    @State private var counts: (before: Int, total: Int)?
    /// Stepped backwards into this file: start at its last match.
    @State private var startAtEnd = false
    @State private var target: PatchScrollTarget?

    init(app: AppState, sessionID: Session.ID, path: String, finished: @escaping () -> Void) {
        self.app = app
        self.sessionID = sessionID
        self.finished = finished
        _selection = State(initialValue: path)
    }

    var body: some View {
        let path = selection ?? ""
        Group {
            if app.diffs[sessionID] == nil {
                // Pushed without the list having loaded — a deep link. Measured:
                // without this it read as "No longer changed" for a file that was.
                ProgressView().controlSize(.small)
                    .task { await app.loadDiff(sessionID) }
            } else if let diff = app.diffs[sessionID] ?? nil,
                      let file = diff.files.first(where: { $0.id == path }) {
                PatchView(file: file, hidesWhitespaceChanges: hidesWhitespace)
                    .patchFind(query, current: matches.indices.contains(current) ? matches[current] : nil)
                    .patchScrollTarget(target)
                    .overlay(alignment: .bottomLeading) {
                        // "Next" marks this file viewed and goes to the next
                        // one that is not — the list shows the same marks.
                        PatchFileStepper(files: diff.files, selection: $selection,
                                         viewed: app.viewed(sessionID, in: diff.files))
                            .padding(12)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !query.isEmpty { findBar(files: diff.files, path: path).padding(12) }
                    }
                    .onPatchFilesEnd(perform: finished)
                    .task(id: FindKey(path: path, patch: file.patch?.hashValue ?? 0,
                                      query: query, hidesWhitespace: hidesWhitespace)) {
                        await find(in: file, files: diff.files)
                    }
            } else {
                // The file went away on a refresh: committed and merged, or reverted.
                ContentUnavailableView("No longer changed", systemImage: "checkmark.circle")
            }
        }
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $searching, prompt: "Find in changes")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { searching = true } label: {
                        Label("Find", systemImage: "magnifyingglass")
                    }
                    Toggle(isOn: $hidesWhitespace) {
                        Label("Hide Whitespace Changes", systemImage: "text.alignleft")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
    }

    private struct FindKey: Hashable {
        let path: String
        let patch: Int
        let query: String
        let hidesWhitespace: Bool
    }

    /// Re-run on every keystroke, file swap, refresh and whitespace toggle;
    /// `.task(id:)` cancels the one it replaces, which is the debounce.
    private func find(in file: FileChange, files: [FileChange]) async {
        let query = query, hides = hidesWhitespace
        guard !query.isEmpty else {
            (matches, current, counts, target) = ([], 0, nil, nil)
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        // Parsing a large patch is not main-actor work.
        let found = await Task.detached {
            DiffFind.matches(in: file, query: query, hidesWhitespaceChanges: hides)
        }.value
        guard !Task.isCancelled else { return }
        matches = found
        current = startAtEnd ? max(found.count - 1, 0) : 0
        startAtEnd = false
        target = found.indices.contains(current) ? PatchScrollTarget(lineID: found[current].lineID) : nil
        counts = nil
        counts = await DiffFind.totals(in: files, query: query, current: file.path, localCount: found.count)
    }

    /// Past either end of this file's matches, on to the nearest file that has
    /// some, wrapping; with no other file to go to, round this one.
    private func step(_ delta: Int, files: [FileChange], path: String) {
        let next = current + delta
        if matches.indices.contains(next) {
            current = next
            target = PatchScrollTarget(lineID: matches[next].lineID)
        } else if let file = DiffFind.nextFile(in: files, from: path, delta: delta, query: query) {
            startAtEnd = delta < 0
            selection = file.id
        } else if !matches.isEmpty {
            current = delta > 0 ? 0 : matches.count - 1
            target = PatchScrollTarget(lineID: matches[current].lineID)
        }
    }

    private func findBar(files: [FileChange], path: String) -> some View {
        let label: String = switch counts {
        case .none: "…"
        case let .some(c) where c.total == 0: "No matches"
        // The other files' counts are raw patch text, so a file with matches
        // only in hidden whitespace can push this past the total; clamp it.
        case let .some(c): "\(min(c.before + current + 1, c.total)) of \(c.total)"
        }
        return HStack(spacing: 14) {
            Text(label).font(.caption.monospacedDigit())
            Group {
                Button { step(-1, files: files, path: path) } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Previous Match")
                Button { step(1, files: files, path: path) } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Next Match")
            }
            .disabled(counts.map { $0.total == 0 } ?? true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
    }
}

private extension AppState {
    /// A session's viewed files as the ids DiffKit's stepper takes, read and
    /// written against the patches on screen now.
    func viewed(_ id: Session.ID, in files: [FileChange]) -> Binding<Set<FileChange.ID>> {
        Binding(get: { self.viewedFiles[id, default: ViewedFiles()].ids(in: files) },
                set: { self.viewedFiles[id, default: ViewedFiles()].set($0, in: files) })
    }
}
