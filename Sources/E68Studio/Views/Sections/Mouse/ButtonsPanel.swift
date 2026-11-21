import SwiftUI

// MARK: - Buttons

struct ButtonsPanel: View {
    @ObservedObject private var mouse = MouseStore.shared
    @ObservedObject private var remapper = MouseRemapper.shared
    @ViewState private var recordingButton: MouseButton?

    var body: some View {
        SidePanelScroll {
            PanelTitle(title: "Buttons")

            AccessBanner()

            VStack(spacing: Space.xs) {
                FixedButtonRow(title: "Left click", symbol: "cursorarrow.click", held: remapper.held.contains(0))
                FixedButtonRow(title: "Right click", symbol: "cursorarrow.click.2", held: remapper.held.contains(1))
                ForEach(MouseButton.allCases) { button in
                    ButtonRow(
                        button: button,
                        held: remapper.held.contains(button.rawValue),
                        recordingButton: $recordingButton
                    )
                }
            }

            HStack {
                Spacer()
                Button("Reset Buttons") {
                    mouse.batchUpdate {
                        mouse.bindings = [:]
                        mouse.gestures = [:]
                        mouse.gestureDistance = 50
                    }
                }
                .buttonStyle(.glassCapsule(size: .small))
                .disabled(mouse.bindings.isEmpty && mouse.gestures.isEmpty && mouse.gestureDistance == 50)
            }

            Caption("Saved on this Mac. Active while E68 Studio is running.")
        }
    }
}

/// Shared look for a button row; lights up while the physical button is held.
private struct ButtonRowFrame<Trailing: View>: View {
    let title: String
    let detail: String
    let symbol: String
    let held: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(held ? Color.accentColor : Ink.secondary)
                .frame(width: 30, height: 30)
                .nestedSurface(Circle(), role: held ? .control : .track, hovering: held)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.studioBody.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.studioMeta)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)
            Spacer(minLength: Space.s)
            trailing
        }
        .frame(minHeight: Hit.regular)
        .padding(.horizontal, Space.row)
        .padding(.vertical, 6)
        .glassSelectable(RoundedRectangle(cornerRadius: Corner.control, style: .continuous), selected: held)
        .animation(.snappy(duration: 0.12), value: held)
    }
}

private struct FixedButtonRow: View {
    let title: String
    let symbol: String
    let held: Bool

    var body: some View {
        ButtonRowFrame(title: title, detail: "Fixed", symbol: symbol, held: held) {
            Image(systemName: "lock.fill")
                .font(.studioMeta)
                .foregroundStyle(.tertiary)
                .frame(width: Hit.small, height: Hit.small)
                .help("Left and right click can't be changed")
                .accessibilityLabel("Can't be changed")
        }
    }
}

private struct ButtonRow: View {
    let button: MouseButton
    let held: Bool
    @Binding var recordingButton: MouseButton?
    @ObservedObject private var mouse = MouseStore.shared
    @ViewState private var typing = false
    @ViewState private var text = ""
    @ViewState private var monitor: Any?
    @ViewState private var editingGestures = false

    private var recording: Bool { recordingButton == button }

    private var shortTitle: String {
        switch button {
        case .middle: "Wheel click"
        case .back: "Back button"
        case .forward: "Forward button"
        }
    }

    var body: some View {
        let action = mouse.action(for: button)
        let effective = action == .standard ? button.defaultAction : action
        let detail = recording ? "Press keys… (Esc)"
            : action == .gesture ? "Gestures · " + mouse.gestureMap(for: button).summary
            : effective.title
        ButtonRowFrame(
            title: shortTitle,
            detail: detail,
            symbol: button.symbol,
            held: held || recording
        ) {
            if recording {
                Button("Cancel") {
                    stopRecording()
                }
                .buttonStyle(.glassCapsule(size: .small))
                .fixedSize()
            } else {
                Menu {
                    Button {
                        set(.standard)
                    } label: {
                        if action == .standard { Label("Default (\(button.defaultAction.title))", systemImage: "checkmark") } else { Text("Default (\(button.defaultAction.title))") }
                    }
                    ForEach(MouseAction.groups) { group in
                        Section(group.title) {
                            ForEach(group.actions, id: \.self) { a in
                                Button {
                                    set(a)
                                } label: {
                                    if a == action { Label(a.title, systemImage: "checkmark") } else { Text(a.title) }
                                }
                            }
                        }
                    }
                    Section("Your own") {
                        Button("Gestures…") {
                            set(.gesture)
                            editingGestures = true
                        }
                        Button("Key Combination…") { startRecording() }
                        Button("Type Text…") {
                            if case .typeText(let t) = action { text = t } else { text = "" }
                            typing = true
                        }
                    }
                } label: {
                    Text("Change")
                }
                .menuStyle(.button)
                .buttonStyle(.glassCapsule(size: .small))
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Change \(shortTitle)")
                .popover(isPresented: $editingGestures, arrowEdge: .leading) {
                    GestureEditor(button: button, buttonName: shortTitle.lowercased())
                        .environment(\.insideGlassPanel, true)
                        .studioAppearance()
                }
                .popover(isPresented: $typing, arrowEdge: .leading) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Text to type").font(.studioHeading)
                        TextField("Text to insert", text: $text)
                            .glassField(width: 240)
                            .onSubmit(commitText)
                        HStack {
                            Spacer()
                            Button("Cancel") { typing = false }.buttonStyle(.glassCapsule(size: .small))
                            Button("Save") { commitText() }
                                .buttonStyle(.glassCapsule(.prominent, size: .small))
                                .disabled(text.isEmpty)
                        }
                    }
                    .environment(\.insideGlassPanel, true)
                    .padding(Space.l)
                    .studioAppearance()
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Corner.control, style: .continuous))
        .onTapGesture {
            if action == .gesture { editingGestures = true }
        }
        .onChange(of: recordingButton) { _, active in
            if active != button, monitor != nil { removeMonitor() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            stopRecording()
        }
        .onDisappear(perform: stopRecording)
        .contextMenu {
            if action == .gesture {
                Button("Edit Gestures…") { editingGestures = true }
            }
        }
    }

    private func set(_ action: MouseAction) {
        if action == .standard { mouse.bindings[button] = nil } else { mouse.bindings[button] = action }
    }

    private func commitText() {
        guard !text.isEmpty else { return }
        set(.typeText(text))
        typing = false
    }

    private func startRecording() {
        stopRecording()
        recordingButton = button
        KeyEventTap.isCapturingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Plain Escape cancels; with modifiers it can still be recorded.
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stopRecording()
                return nil
            }
            set(.keystroke(Keystroke.from(event)))
            stopRecording()
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recordingButton == nil || recordingButton == button {
            KeyEventTap.isCapturingShortcut = false
        }
    }

    private func stopRecording() {
        removeMonitor()
        if recordingButton == button {
            recordingButton = nil
            KeyEventTap.isCapturingShortcut = false
        }
    }
}

/// Sets what each direction does while a gesture button is held.
private struct GestureEditor: View {
    let button: MouseButton
    let buttonName: String
    @ObservedObject private var mouse = MouseStore.shared
    @ObservedObject private var remapper = MouseRemapper.shared

    private var map: Binding<GestureMap> {
        Binding(
            get: { mouse.gestureMap(for: button) },
            set: { mouse.gestures[button] = $0 }
        )
    }

    private func lit(_ direction: GestureMap.Direction) -> Bool {
        guard let last = remapper.lastGesture else { return false }
        return last.button == button && last.direction == direction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Gestures · \(buttonName.capitalized)").font(.studioHeading)

            Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
                ForEach(GestureMap.Direction.allCases) { direction in
                    GridRow {
                        Text(direction.arrow)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(lit(direction) ? Color.accentColor : Ink.secondary)
                            .frame(width: 22)
                            .animation(.snappy(duration: 0.15), value: remapper.lastGesture?.serial)
                        Text(direction.title)
                            .font(.studioBody)
                        ActionPicker(selection: Binding(
                            get: { map.wrappedValue[direction] },
                            set: { map.wrappedValue[direction] = $0 }
                        ), includeDefault: nil)
                    }
                }
                Divider().gridCellColumns(3)
                GridRow {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 22)
                    Text("Just press")
                        .font(.studioBody)
                    ActionPicker(selection: map.tap, includeDefault: button.defaultAction)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldHeader(title: "Distance", value: "\(mouse.gestureDistance) px")
                StepSlider(
                    value: Binding(get: { mouse.gestureDistance / 10 }, set: { mouse.gestureDistance = $0 * 10 }),
                    range: 2...15,
                    label: "Gesture distance",
                    accessibilityValueText: "\(mouse.gestureDistance) pixels"
                )
            }

            HStack {
                Button("Reset") { mouse.gestures[button] = nil }
                    .buttonStyle(.glassCapsule(size: .small))
                Spacer()
            }
        }
        .padding(Space.l)
        .frame(width: 320)
    }
}

private struct ActionPicker: View {
    @Binding var selection: MouseAction
    /// When set, offers "Default (…)" stored as `.standard`.
    let includeDefault: MouseAction?

    var body: some View {
        Menu {
            if let def = includeDefault {
                Button {
                    selection = .standard
                } label: {
                    if selection == .standard { Label("Default (\(def.title))", systemImage: "checkmark") } else { Text("Default (\(def.title))") }
                }
            }
            ForEach(GestureMap.choices) { group in
                Section(group.title) {
                    ForEach(group.actions, id: \.self) { a in
                        Button {
                            selection = a
                        } label: {
                            if a == selection { Label(a.title, systemImage: "checkmark") } else { Text(a.title) }
                        }
                    }
                }
            }
        } label: {
            Text(selection == .standard ? "Default (\(includeDefault?.title ?? "—"))" : selection.title)
                .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.glassCapsule(size: .small))
        .menuIndicator(.hidden)
    }
}
