import SwiftUI

/// Which desk object the studio close-up is about.
enum StudioDevice: String {
    case keyboard, mouse
}

enum StudioSection: String, CaseIterable, Identifiable {
    case test, keys, light, macros, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .test: return "Test"
        case .keys: return "Keys"
        case .light: return "Light"
        case .macros: return "Macros"
        case .more: return "More"
        }
    }

    var symbol: String {
        switch self {
        case .test: return "hand.tap"
        case .keys: return "keyboard"
        case .light: return "light.max"
        case .macros: return "text.append"
        case .more: return "ellipsis"
        }
    }
}

/// Dock sections of the mouse studio.
enum MouseSection: String, CaseIterable, Identifiable {
    case test, dpi, buttons, scroll, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .test: return "Test"
        case .dpi: return "DPI"
        case .buttons: return "Buttons"
        case .scroll: return "Scroll"
        case .more: return "More"
        }
    }

    var symbol: String {
        switch self {
        case .test: return "hand.tap"
        case .dpi: return "gauge.with.dots.needle.67percent"
        case .buttons: return "computermouse"
        case .scroll: return "arrow.up.and.down"
        case .more: return "ellipsis"
        }
    }
}

@MainActor
final class KeyboardStore: ObservableObject {
    enum Connection: Equatable {
        case searching, loading, ready, bluetooth
        case failed(String)
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    // Navigation: the desk overview, or the studio close-up with one section open
    @Published var inStudio = false {
        didSet {
            if inStudio != oldValue {
                handleViewContextChanged()
            }
        }
    }
    @Published var studioDevice: StudioDevice = .keyboard {
        didSet {
            if studioDevice != oldValue {
                handleViewContextChanged()
            }
        }
    }
    @Published var section: StudioSection = .test {
        didSet {
            if section != oldValue {
                handleViewContextChanged()
            }
        }
    }
    @Published var mouseSection: MouseSection = .dpi

    var inKeyboardStudio: Bool { inStudio && studioDevice == .keyboard }
    var inMouseStudio: Bool { inStudio && studioDevice == .mouse }

    // Device
    @Published var connection: Connection = .searching
    @Published var device: DeviceInfo?
    @Published var bluetoothDevice: BluetoothDeviceInfo?
    @Published var protocolVersion = 0
    @Published var layerCount = 4
    @Published var macroCount = 16
    @Published var macroBufferSize = 512

    // Keymap
    @Published var keymap: [[UInt16]] = FactoryKeymap.layers
    @Published var activeLayer = 0 {
        didSet {
            if activeLayer >= layerCount {
                activeLayer = 0
            }
        }
    }
    @Published var selection: Slot?

    // Macros
    @Published var macros: [[MacroStep]] = Array(repeating: [], count: 16) {
        didSet { cachedMacroImage = nil }
    }
    @Published var storedMacroImage: [UInt8] = Array(repeating: 0, count: 16)
    @Published var macroNames: [String]
    private var cachedMacroImage: [UInt8]?

    // Lighting
    @Published var lighting = LightingState() {
        didSet {
            if lighting.reactiveTypingRipple != oldValue.reactiveTypingRipple {
                defaults.set(lighting.reactiveTypingRipple, forKey: "lighting.reactiveTypingRipple")
            }
        }
    }
    /// Screen Glow: backlight follows the colours on screen.
    @Published var screenSync = false

    // Key test & telemetry
    @Published var pressed: Set<Int> = []
    @Published var flashing: Set<Int> = []
    @Published var tested: Set<Int> = []
    @Published var keyCounts: [Int: Int] = [:]
    @Published var showHeatmap = false
    @Published var currentWPM = 0
    @Published var peakWPM = 0
    @Published var knobCWCount = 0
    @Published var knobCCWCount = 0
    var internalKeyCounts: [Int: Int] = [:]
    var internalCurrentWPM = 0
    var internalPeakWPM = 0
    var telemetryDirty = false
    var telemetrySaveTask: Task<Void, Never>?
    var telemetryPublishTask: Task<Void, Never>?
    var wpmDecayTask: Task<Void, Never>?
    var lastTelemetryPublish: ContinuousClock.Instant?
    var telemetryResignObserver: NSObjectProtocol?
    var keystrokeTimestamps: [ContinuousClock.Instant] = []
    var eventPressed: Set<Int> = []
    var firmwarePressed: [Int: Int] = [:]
    var learnedOSRawBits: Set<Int> = []
    var learnedFnRawBit: Int?
    var lastRawMatrixDown: Set<Int> = []
    var pendingOSKeyDowns: [ContinuousClock.Instant] = []
    var lastOSKeyEventAt: ContinuousClock.Instant?
    var rawMatrixTasks: [Int: Task<Void, Never>] = [:]
    var flashGeneration: [Int: Int] = [:]

    // Feedback
    @Published var toast: Toast?
    @Published var busy: String?

    let hid = HIDTransport()
    let bluetooth = BluetoothMonitor()
    let audioMonitor = AudioMonitor()
    let screenSampler = ScreenColorSampler()
    let keyTap = KeyEventTap()
    var via: VIA { VIA(hid: hid) }
    let defaults = UserDefaults.standard

    var lightingPending = Set<VIA.LightingValue>()
    var lightingNeedsSave = false
    var lightingPump: Task<Void, Never>?
    var lightingWatch: Task<Void, Never>?
    var reactiveHardwareTask: Task<Void, Never>?
    var reactiveHardwareGeneration: UInt64 = 0
    var isPulsingReactiveHardware = false
    var isRestoringLighting = false
    var musicSyncTask: Task<Void, Never>?
    var screenSyncTask: Task<Void, Never>?
    var screenSyncStartGeneration: UInt64 = 0
    var pollTask: Task<Void, Never>?
    private var reloadGeneration: UInt64 = 0
    private var started = false

    init() {
        macroNames = defaults.stringArray(forKey: "macroNames") ?? []
        while macroNames.count < 16 { macroNames.append("") }
        lighting.reactiveTypingRipple = defaults.bool(forKey: "lighting.reactiveTypingRipple")
        loadSavedTelemetry()
        telemetryResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushTelemetryToDefaults()
            }
        }
    }

    var isMainWindowVisible: Bool {
        guard !NSApp.isHidden else { return false }
        return NSApp.windows.contains { window in
            guard window.isVisible,
                  !window.isMiniaturized,
                  window.level == .normal,
                  window.occlusionState.contains(.visible) else { return false }
            let className = NSStringFromClass(type(of: window))
            if className.contains("StatusBar") || className.contains("MenuBarExtra") {
                return false
            }
            return window.canBecomeMain || window.identifier?.rawValue == "e68-main-window"
        }
    }

    func start() {
        guard !started else { return }
        started = true
        ProfileStore.shared.keyboardStore = self
        LiveMirror.shared.store = self
        LiveMirror.shared.start()
        TextExpander.shared.start()
        hid.onConnect = { [weak self] info in
            Task { @MainActor in await self?.connected(info) }
        }
        hid.onDisconnect = { [weak self] in
            Task { @MainActor in self?.disconnected() }
        }
        bluetooth.onConnect = { [weak self] info in
            Task { @MainActor in self?.bluetoothConnected(info) }
        }
        bluetooth.onDisconnect = { [weak self] in
            Task { @MainActor in self?.bluetoothDisconnected() }
        }
        bluetooth.onBatteryUpdate = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.bluetoothDevice?.batteryLevel = level
                BatteryNotifier.shared.check(
                    deviceName: self.bluetoothDevice?.product ?? "E-68 PRO",
                    level: level,
                    isMouse: false
                )
            }
        }
        hid.start()
        bluetooth.start()
        keyTap.shouldPassThroughEscape = { [weak self] in
            guard let self else { return true }
            return self.inStudio && !(self.inKeyboardStudio && self.section == .test)
        }
        keyTap.shouldSwallowNavigationKeys = { [weak self] in
            guard let self else { return false }
            return self.inKeyboardStudio && self.section == .test
        }
        setupScreenSamplerCallbacks()
        keyTap.start { [weak self] code, down in
            Task { @MainActor [weak self] in
                self?.keyEvent(code: code, down: down)
            }
        }
    }

    // MARK: Connection

    private struct Snapshot {
        var protocolVersion: Int
        var layerCount: Int
        var macroCount: Int
        var macroBufferSize: Int
        var keymap: [[UInt16]]
        var macroBuffer: [UInt8]
        var lighting: VIA.RawLighting
    }

    private func connected(_ info: DeviceInfo) async {
        device = info
        connection = .loading
        await reload()
    }

    func reload() async {
        reloadGeneration &+= 1
        let gen = reloadGeneration
        let via = self.via
        do {
            let snap = try await hid.run {
                let layers = max(1, min(try via.layerCount(), FactoryKeymap.layers.count))
                let bufferSize = try via.macroBufferSize()
                return Snapshot(
                    protocolVersion: try via.protocolVersion(),
                    layerCount: layers,
                    macroCount: max(1, min(try via.macroCount(), 16)),
                    macroBufferSize: bufferSize,
                    keymap: try via.readKeymap(layers: layers),
                    macroBuffer: try via.readMacroBuffer(size: bufferSize),
                    lighting: try via.readLighting()
                )
            }
            guard gen == reloadGeneration else { return }
            protocolVersion = snap.protocolVersion
            layerCount = snap.layerCount
            macroCount = snap.macroCount
            macroBufferSize = snap.macroBufferSize
            keymap = snap.keymap
            activeLayer = min(activeLayer, snap.layerCount - 1)
            macros = MacroCodec.split(snap.macroBuffer, count: snap.macroCount)
            storedMacroImage = MacroCodec.image(macros)
            if !lighting.musicSync && !screenSync {
                lighting.apply(snap.lighting)
                lightingNeedsSave = false
            }
            connection = .ready
            if lighting.musicSync {
                audioMonitor.start()
                startHardwareMusicSync()
            }
            if screenSync { startScreenSyncLoop() }
            setKeyTestActive(true)
            setLightingWatch(true)
        } catch {
            guard gen == reloadGeneration else { return }
            connection = .failed(error.localizedDescription)
        }
    }

    private func disconnected() {
        reloadGeneration &+= 1
        device = nil
        connection = bluetoothDevice != nil ? .bluetooth : .searching
        selection = nil
        learnedOSRawBits = []
        learnedFnRawBit = nil
        lastRawMatrixDown = []
        pendingOSKeyDowns = []
        for task in rawMatrixTasks.values { task.cancel() }
        rawMatrixTasks = [:]
        firmwarePressed = [:]
        busy = nil
        lightingPump?.cancel()
        lightingPump = nil
        lightingPending = []
        lightingNeedsSave = false
        reactiveHardwareTask?.cancel()
        reactiveHardwareTask = nil
        reactiveHardwareGeneration &+= 1
        isPulsingReactiveHardware = false
        musicSyncTask?.cancel()
        musicSyncTask = nil
        screenSyncTask?.cancel()
        screenSyncTask = nil
        screenSampler.stop()
        audioMonitor.stop()
        setLightingWatch(false)
        setKeyTestActive(false)
        pressed = []
        flashing = []
        eventPressed = []
        flashGeneration = [:]
    }

    private func bluetoothConnected(_ info: BluetoothDeviceInfo) {
        bluetoothDevice = info
        if device == nil && connection != .loading && connection != .ready {
            connection = .bluetooth
        }
    }

    private func bluetoothDisconnected() {
        bluetoothDevice = nil
        if connection == .bluetooth {
            connection = .searching
            selection = nil
            pressed = []
            flashing = []
            eventPressed = []
            flashGeneration = [:]
        }
    }

    var isReady: Bool { connection == .ready }
    var isBluetooth: Bool { connection == .bluetooth }
    var isConnected: Bool { isReady || isBluetooth }
    var activeProductName: String? { device?.product ?? bluetoothDevice?.product }

    func enterStudio() {
        guard !inKeyboardStudio else { return }
        studioDevice = .keyboard
        inStudio = true
        if isReady {
            if pollTask == nil { setKeyTestActive(true) }
            if lightingWatch == nil { setLightingWatch(true) }
        }
    }

    /// Close-up of the mouse.
    func enterMouseStudio() {
        guard !inMouseStudio else { return }
        studioDevice = .mouse
        inStudio = true
        selection = nil
    }

    func leaveStudio() {
        inStudio = false
        selection = nil
    }

    // MARK: Feedback

    func notify(_ text: String, isError: Bool = false) {
        let t = Toast(text: text, isError: isError)
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(isError ? 6 : 2.5))
            if toast == t { toast = nil }
        }
    }

    // MARK: Keymap

    func code(layer: Int, _ slot: Slot) -> UInt16 {
        guard layer < keymap.count else { return 0 }
        return keymap[layer][slot.index]
    }

    func factoryCode(layer: Int, _ slot: Slot) -> UInt16? {
        guard layer < FactoryKeymap.layers.count else { return nil }
        return FactoryKeymap.layers[layer][slot.index]
    }

    func isModified(layer: Int, _ slot: Slot) -> Bool {
        guard let factory = factoryCode(layer: layer, slot) else { return false }
        return factory != code(layer: layer, slot)
    }

    func modifiedCount(layer: Int) -> Int {
        Layout.all.filter { isModified(layer: layer, $0) }.count
    }

    func legend(layer: Int, _ slot: Slot) -> Legend {
        Keycodes.def(for: code(layer: layer, slot), macroNames: macroNames).legend
    }

    func describe(_ code: UInt16) -> KeyDef {
        Keycodes.def(for: code, macroNames: macroNames)
    }

    /// Writes one key immediately and rolls the UI back if the keyboard does not confirm it.
    func assign(_ code: UInt16, layer: Int, slot: Slot) {
        guard isReady, layer < keymap.count else { return }
        let previous = keymap[layer][slot.index]
        guard previous != code else { return }
        keymap[layer][slot.index] = code
        let via = self.via
        Task {
            do {
                try await hid.run { try via.setKey(layer: layer, index: slot.index, code: code) }
            } catch {
                if keymap[layer][slot.index] == code { keymap[layer][slot.index] = previous }
                notify("Could not change that key. \(error.localizedDescription)", isError: true)
            }
        }
    }

    /// Brings the keyboard's remappable positions in line with `target`, writing only what differs.
    @discardableResult
    func applyKeymap(_ target: [[UInt16]], layers: [Int]? = nil, label: String) async -> Int? {
        guard isReady else { return nil }
        var changes = [(layer: Int, index: Int, code: UInt16)]()
        for layer in layers ?? Array(0..<min(layerCount, target.count)) where layer < target.count && layer < keymap.count {
            for slot in Layout.all where target[layer][slot.index] != keymap[layer][slot.index] {
                changes.append((layer, slot.index, target[layer][slot.index]))
            }
        }
        guard !changes.isEmpty else { return 0 }
        busy = label
        defer { busy = nil }
        let via = self.via
        let layerCount = self.layerCount
        do {
            let fresh = try await hid.run { () -> [[UInt16]] in
                for change in changes {
                    try via.setKey(layer: change.layer, index: change.index, code: change.code)
                }
                return try via.readKeymap(layers: layerCount)
            }
            keymap = fresh
            return changes.count
        } catch {
            notify("Stopped part-way. \(error.localizedDescription)", isError: true)
            if let fresh = try? await hid.run({ try via.readKeymap(layers: layerCount) }) { keymap = fresh }
            return nil
        }
    }

    func restoreFactoryKeymap(layers: [Int]? = nil) async {
        if let n = await applyKeymap(FactoryKeymap.layers, layers: layers, label: "Restoring factory keymap…") {
            notify(n == 0 ? "Already matches the factory keymap." : "Restored \(n) key\(n == 1 ? "" : "s") to factory settings.")
        }
    }

    // MARK: Macros

    var macroCapacity: Int { VIA.usableMacroBytes(bufferSize: macroBufferSize) }
    var macroImage: [UInt8] {
        if let cached = cachedMacroImage { return cached }
        let encoded = MacroCodec.image(macros)
        cachedMacroImage = encoded
        return encoded
    }
    var macroBytesUsed: Int { macroImage.count }
    var macrosDirty: Bool { macroImage != storedMacroImage }
    var macrosFit: Bool { macroBytesUsed <= macroCapacity }

    func setMacroName(_ name: String, slot: Int) {
        guard slot >= 0, slot < macroNames.count else { return }
        macroNames[slot] = name
        defaults.set(macroNames, forKey: "macroNames")
    }

    @discardableResult
    func writeMacros() async -> Bool {
        guard isReady, macrosFit else { return false }
        let image = macroImage
        let size = macroBufferSize
        let via = self.via
        busy = "Writing macros…"
        defer { busy = nil }
        do {
            try await hid.run { try via.writeMacroBuffer(image, bufferSize: size) }
            storedMacroImage = image
            notify("Macros saved to the keyboard.")
            return true
        } catch {
            notify("Macros were not saved. \(error.localizedDescription)", isError: true)
            return false
        }
    }

    func revertMacros() {
        macros = MacroCodec.split(storedMacroImage, count: macroCount)
    }

    func clearMacros() async {
        let previous = macros
        macros = Array(repeating: [], count: macroCount)
        if !(await writeMacros()) {
            macros = previous
        }
    }

    /// Keys on any layer that trigger the given macro slot.
    func keysUsingMacro(_ slot: Int) -> [(layer: Int, slot: Slot)] {
        let code = Keycodes.macroBase + UInt16(slot)
        var hits = [(Int, Slot)]()
        for layer in 0..<min(layerCount, keymap.count) {
            for s in Layout.all where keymap[layer][s.index] == code { hits.append((layer, s)) }
        }
        return hits
    }
}
