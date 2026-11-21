import SwiftUI

/// Text Snippets: type a short trigger anywhere on the Mac and it becomes the full text.
struct SnippetsView: View {
    @ObservedObject private var expander = TextExpander.shared
    @ObservedObject private var remapper = MouseRemapper.shared

    var body: some View {
        PanelScroll(maxWidth: 720) {
            GroupedSection(title: "Text Snippets") {
                GroupedRow(label: "Expand snippets as you type", detail: "Type a trigger like ;date in any app and it’s replaced with the text.") {
                    Toggle("Expand snippets as you type", isOn: $expander.enabled)
                        .labelsHidden()
                        .toggleStyle(AccentSwitchStyle())
                }
            }

            if !remapper.trusted {
                HStack(spacing: Space.m) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.orange)
                    Text("Snippets need Accessibility access.")
                        .font(.studioDetail)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Allow…") { expander.requestAccess() }
                        .buttonStyle(.glassCapsule(.prominent, size: .small))
                }
                .insetCard()
            }

            VStack(spacing: Space.xs) {
                if expander.snippets.isEmpty {
                    EmptyStateView(
                        symbol: "text.badge.plus",
                        title: "No snippets"
                    )
                    .insetCard()
                } else {
                    HStack(spacing: Space.s) {
                        Text("Trigger").frame(width: 130, alignment: .leading)
                        Text("Expands to")
                        Spacer()
                    }
                    .font(.studioMeta.weight(.medium))
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 12)

                    ForEach($expander.snippets) { $snippet in
                        SnippetRow(snippet: $snippet, problem: expander.problem(with: snippet)) {
                            expander.snippets.removeAll { $0.id == snippet.id }
                        }
                    }
                }

                HStack {
                    Button {
                        expander.snippets.append(Snippet(trigger: ";", expansion: ""))
                    } label: {
                        Label("Add Snippet", systemImage: "plus")
                    }
                    .buttonStyle(.glassCapsule(size: .small))
                    Spacer()
                    if expander.expansionCount > 0 {
                        Text("Expanded \(expander.expansionCount) time\(expander.expansionCount == 1 ? "" : "s")")
                            .font(.studioMeta.monospacedDigit())
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .padding(.top, Space.xs)
            }
            .opacity(expander.enabled ? 1 : 0.55)

            VStack(alignment: .leading, spacing: Space.s) {
                FieldHeader(title: "Placeholders")
                ForEach(TextExpander.placeholders, id: \.token) { item in
                    HStack(spacing: Space.s) {
                        Text(item.token)
                            .font(.system(.callout, design: .monospaced))
                            .frame(width: 110, alignment: .leading)
                        Text(item.meaning)
                            .font(.studioMeta)
                            .foregroundStyle(Ink.secondary)
                    }
                }
            }
            .insetCard()
        }
    }
}

private struct SnippetRow: View {
    @Binding var snippet: Snippet
    let problem: String?
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 3) {
                TextField(";trigger", text: $snippet.trigger)
                    .font(.system(.body, design: .monospaced))
                    .glassField(width: 130)
                if let problem {
                    Text(problem)
                        .font(.studioMeta)
                        .foregroundStyle(.orange)
                        .frame(width: 130, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField("Text to type", text: $snippet.expansion, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.studioBody)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: Hit.small)
                .glassSurface(RoundedRectangle(cornerRadius: Hit.small / 2, style: .continuous), interactive: true)
            Toggle("Use this snippet", isOn: $snippet.enabled)
                .labelsHidden()
                .toggleStyle(AccentSwitchStyle())
                .help(snippet.enabled ? "Turn off this snippet" : "Turn on this snippet")
            IconButton(symbol: "trash", label: "Delete Snippet", action: onDelete)
        }
    }
}
