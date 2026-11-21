import AppKit
import Carbon.HIToolbox

/// One abbreviation: type `trigger` anywhere and it is replaced with `expansion`.
struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: String
    var expansion: String
    var enabled = true
}

/// System-wide text expansion. Watches typed characters through `GlobalKeyTap`; when the end of
/// what you typed matches a trigger, it deletes the trigger and types the expansion in its place.
///
/// Expansions can contain `{date}`, `{time}`, `{clipboard}` and one `{cursor}`, where the caret
/// is left after typing.
@MainActor
final class TextExpander: ObservableObject {
    static let shared = TextExpander()

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "expander.enabled"); sync() }
    }
    @Published var snippets: [Snippet] {
        didSet { save(); sync() }
    }
    @Published private(set) var expansionCount: Int {
        didSet { defaults.set(expansionCount, forKey: "expander.count") }
    }

    private let defaults = UserDefaults.standard
    private var buffer = ""
    private var expanding = false
    private static let maxBuffer = 64

    static let placeholders: [(token: String, meaning: String)] = [
        ("{date}", "today's date"),
        ("{time}", "the current time"),
        ("{clipboard}", "what you last copied"),
        ("{cursor}", "where the caret ends up"),
    ]

    static let examples: [Snippet] = [
        Snippet(trigger: ";date", expansion: "{date}"),
        Snippet(trigger: ";shrug", expansion: "¯\\_(ツ)_/¯"),
        Snippet(trigger: ";ty", expansion: "Thank you!"),
    ]

    private init() {
        enabled = defaults.object(forKey: "expander.enabled") as? Bool ?? false
        if let data = defaults.data(forKey: "expander.snippets"),
           let saved = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = saved
        } else {
            snippets = Self.examples
        }
        expansionCount = defaults.integer(forKey: "expander.count")
    }

    func start() { sync() }

    func stop() {
        GlobalKeyTap.shared.unsubscribe("expander")
        buffer = ""
    }

    func requestAccess() { MouseRemapper.shared.requestAccess() }

    /// Triggers that are empty, duplicated, or contained in another trigger's ending.
    func problem(with snippet: Snippet) -> String? {
        let t = snippet.trigger
        if t.isEmpty { return "Needs a trigger" }
        if t.count < 2 { return "Use at least 2 characters" }
        if t.contains(where: \.isWhitespace) { return "No spaces in triggers" }
        if snippets.contains(where: { $0.id != snippet.id && $0.enabled && $0.trigger == t }) { return "Trigger used twice" }
        return nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snippets) { defaults.set(data, forKey: "expander.snippets") }
    }

    private func sync() {
        buffer = ""
        if enabled && snippets.contains(where: { $0.enabled && !$0.trigger.isEmpty }) {
            GlobalKeyTap.shared.subscribe("expander") { [weak self] in self?.handle($0) }
        } else {
            GlobalKeyTap.shared.unsubscribe("expander")
        }
    }

    // MARK: Matching

    private static let resetKeys: Set<Int> = [
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
    ]

    private func handle(_ event: GlobalKeyTap.Event) {
        guard !event.isSynthetic, !expanding else { return }
        if IsSecureEventInputEnabled() || (NSApp.isActive && NSApp.keyWindow?.firstResponder is NSText) {
            buffer = ""
            return
        }
        switch event.kind {
        case .click:
            buffer = ""
            return
        case .keyDown:
            break
        default:
            return
        }
        if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) {
            buffer = ""
            return
        }
        let code = Int(event.keyCode)
        if code == kVK_Delete {
            if event.flags.contains(.maskAlternate) || event.flags.contains(.maskCommand) {
                buffer = ""
            } else if !buffer.isEmpty {
                buffer.removeLast()
            }
            return
        }
        if Self.resetKeys.contains(code) {
            buffer = ""
            return
        }
        let typed = event.characters.filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F } }
        guard !typed.isEmpty else { return }
        buffer += typed
        if buffer.count > Self.maxBuffer { buffer.removeFirst(buffer.count - Self.maxBuffer) }

        let match = snippets
            .filter { $0.enabled && $0.trigger.count >= 2 && buffer.hasSuffix($0.trigger) }
            .max { $0.trigger.count < $1.trigger.count }
        if let match {
            buffer = ""
            expand(match)
        }
    }

    // MARK: Typing

    private func expand(_ snippet: Snippet) {
        expanding = true
        let deletes = snippet.trigger.count
        let (text, caretBack) = Self.render(snippet.expansion)
        Task { @MainActor in
            // Let the trigger's last key reach the app before we start deleting it.
            try? await Task.sleep(for: .milliseconds(12))
            for _ in 0..<deletes { ActionPerformer.key(kVK_Delete) }
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                if i > 0 { ActionPerformer.key(kVK_Return, .maskShift) }
                if !line.isEmpty { ActionPerformer.type(line) }
            }
            for _ in 0..<caretBack { ActionPerformer.key(kVK_LeftArrow) }
            try? await Task.sleep(for: .milliseconds(30))
            expansionCount += 1
            expanding = false
        }
    }

    /// Fills in placeholders. Returns the text and how many characters the caret should step back.
    static func render(_ template: String, now: Date = Date()) -> (String, Int) {
        var text = template
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if text.contains("{date}") {
            text = text.replacingOccurrences(of: "{date}", with: now.formatted(date: .abbreviated, time: .omitted))
        }
        if text.contains("{time}") {
            text = text.replacingOccurrences(of: "{time}", with: now.formatted(date: .omitted, time: .shortened))
        }
        let clip = text.contains("{clipboard}")
            ? (NSPasteboard.general.string(forType: .string) ?? "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            : ""
        guard let range = text.range(of: "{cursor}") else {
            return (text.replacingOccurrences(of: "{clipboard}", with: clip), 0)
        }
        let before = String(text[..<range.lowerBound]).replacingOccurrences(of: "{clipboard}", with: clip)
        let after = String(text[range.upperBound...])
            .replacingOccurrences(of: "{cursor}", with: "")
            .replacingOccurrences(of: "{clipboard}", with: clip)
        return (before + after, after.count)
    }
}
