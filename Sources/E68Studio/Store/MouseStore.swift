import AppKit
import Combine
import IOKit
import IOKit.hid

/// Finds the MCHOSE G7 on any link (USB cable, 2.4 GHz receiver, Bluetooth) and applies per-mouse
/// pointer settings to it. The settings are re-applied whenever the mouse reconnects, because macOS
/// forgets them when the device goes away.
@MainActor
final class MouseStore: ObservableObject {
    static let shared = MouseStore()

    struct Info: Equatable {
        var product: String
        var link: String
        var usbID: String
        var firmware: String
        var serial: String
        var battery: Int?
    }

    struct LinkMeta {
        let product: String
        let firmware: String
        let serial: String
        let btUUID: String
    }

    @Published var info: Info?
    @Published var lastApplyFailed = false

    /// When off, the mouse follows the normal macOS tracking-speed slider.
    @Published var customEnabled: Bool {
        didSet {
            defaults.set(customEnabled, forKey: "mouse.customEnabled")
            if !customEnabled && sniperActive {
                sniperSavedCustomEnabled = nil
                batchUpdate { sniperActive = false }
            } else {
                apply()
            }
        }
    }
    /// Raw 1:1 movement: the pointer travels the same distance however fast the hand moves.
    @Published var accelerationOff: Bool { didSet { defaults.set(accelerationOff, forKey: "mouse.accelerationOff"); apply() } }
    /// 0…1. The macOS acceleration curve, used only while acceleration is on.
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "mouse.speed"); apply() } }

    // MARK: DPI stages

    /// The DPI actually stored in the mouse (set in M HUB). Stages are scaled relative to it.
    @Published var hardwareDPI: Int { didSet { defaults.set(hardwareDPI, forKey: "mouse.hardwareDPI"); apply() } }
    @Published var stages: [DPIStage] {
        didSet {
            guard !isSanitizingStages else { return }
            let activeID = activeStageID(in: oldValue, index: stageIndex)
            sanitizeStages()
            encode(stages, "mouse.stages")
            syncStageIndex(preserving: activeID)
            apply()
        }
    }
    @Published var stageIndex: Int {
        didSet {
            defaults.set(stageIndex, forKey: "mouse.stageIndex")
            if !isSyncingStageIndex { apply() }
        }
    }
    @Published var sniperDPI: Int {
        didSet {
            defaults.set(sniperDPI, forKey: "mouse.sniperDPI")
            if sniperActive { apply() }
        }
    }
    /// True while a button bound to Sniper is held.
    @Published var sniperActive = false { didSet { if sniperActive != oldValue { apply() } } }
    @Published var showStageHUD: Bool { didSet { defaults.set(showStageHUD, forKey: "mouse.showStageHUD") } }

    // MARK: Buttons, scroll, clicks

    @Published var bindings: [MouseButton: MouseAction] {
        didSet {
            encode(bindings, "mouse.bindings")
            if !bindings.values.contains(.sniper) {
                endSniper(announce: false)
            }
        }
    }
    /// Direction actions for buttons bound to `.gesture`.
    @Published var gestures: [MouseButton: GestureMap] { didSet { encode(gestures, "mouse.gestures") } }
    /// Pixels of movement before a gesture fires.
    @Published var gestureDistance: Int { didSet { defaults.set(gestureDistance, forKey: "mouse.gestureDistance") } }
    /// Reverse the wheel without touching the trackpad's natural scrolling.
    @Published var reverseScroll: Bool { didSet { defaults.set(reverseScroll, forKey: "mouse.reverseScroll") } }
    /// Wheel speed in quarter steps: 4 = unchanged, 1 = ¼×, 16 = 4×.
    @Published var scrollQuarterSteps: Int { didSet { defaults.set(scrollQuarterSteps, forKey: "mouse.scrollQuarterSteps") } }
    /// Ignore a press that follows a release of the same button within this many ms (0 = off).
    @Published var debounceMS: Int { didSet { defaults.set(debounceMS, forKey: "mouse.debounceMS") } }

    var scrollMultiplier: Double { Double(scrollQuarterSteps) / 4 }

    var clampedStageIndex: Int {
        let count = stages.filter(\.enabled).count
        guard count > 0 else { return 0 }
        return min(max(stageIndex, 0), count - 1)
    }

    var currentStage: DPIStage? {
        let enabled = stages.filter(\.enabled)
        guard !enabled.isEmpty else { return nil }
        return enabled[min(max(stageIndex, 0), enabled.count - 1)]
    }

    /// The DPI the pointer currently behaves like.
    var effectiveDPI: Int { sniperActive ? sniperDPI : (currentStage?.dpi ?? hardwareDPI) }

    /// Actual DPI applied after clamping the hardware-to-target ratio to 0.05×…8×.
    var appliedDPI: Int {
        Int((Double(max(hardwareDPI, 100)) * multiplier).rounded())
    }

    /// Every link the G7 is on right now (it can be on the cable and a wireless link at once).
    var services: [AnyObject] = []
    var serviceIDs: Set<String> = []
    var orderedServiceIDs: [String] = []
    var initialResolutions: [String: NSNumber] = [:]
    var linkMetaCache: [String: LinkMeta] = [:]
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var wakeTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    var isBatchUpdating = false
    private var isSanitizingStages = false
    private var isSyncingStageIndex = false
    private var sniperSavedCustomEnabled: Bool?
    var bleBatteryReader: BLEBatteryReader?
    var bleBatteryTargetKey: String?
    var bleBatteryLevel: Int?
    var lastHIDBattery: Int?

    private init() {
        customEnabled = defaults.bool(forKey: "mouse.customEnabled")
        accelerationOff = defaults.bool(forKey: "mouse.accelerationOff")
        speed = min(max(defaults.object(forKey: "mouse.speed") as? Double ?? 0.5, 0), 1)
        hardwareDPI = min(max(defaults.object(forKey: "mouse.hardwareDPI") as? Int ?? 1600, 100), 12000)
        let decodedStages = Self.decode([DPIStage].self, "mouse.stages") ?? DPIStage.defaults
        stages = decodedStages.isEmpty ? DPIStage.defaults : decodedStages
        stageIndex = defaults.object(forKey: "mouse.stageIndex") as? Int ?? 2
        sniperDPI = min(max(defaults.object(forKey: "mouse.sniperDPI") as? Int ?? 400, 100), 1600)
        showStageHUD = defaults.object(forKey: "mouse.showStageHUD") as? Bool ?? true
        bindings = Self.decode([MouseButton: MouseAction].self, "mouse.bindings") ?? [:]
        gestures = Self.decode([MouseButton: GestureMap].self, "mouse.gestures") ?? [:]
        gestureDistance = min(max(defaults.object(forKey: "mouse.gestureDistance") as? Int ?? 50, 20), 150)
        reverseScroll = defaults.bool(forKey: "mouse.reverseScroll")
        scrollQuarterSteps = min(max(defaults.object(forKey: "mouse.scrollQuarterSteps") as? Int ?? 4, 1), 16)
        debounceMS = min(max(defaults.integer(forKey: "mouse.debounceMS"), 0), 100)
        sanitizeStages()
        syncStageIndex(preserving: nil)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    func action(for button: MouseButton) -> MouseAction {
        bindings[button] ?? .standard
    }

    func gestureMap(for button: MouseButton) -> GestureMap {
        gestures[button] ?? GestureMap()
    }

    func batchUpdate(_ work: () -> Void) {
        let wasBatch = isBatchUpdating
        isBatchUpdating = true
        work()
        isBatchUpdating = wasBatch
        if !isBatchUpdating { apply() }
    }

    // MARK: Stage control

    func selectStage(_ index: Int, announce: Bool = true) {
        let count = stages.filter(\.enabled).count
        guard count > 0 else { return }
        batchUpdate {
            if !customEnabled { customEnabled = true }
            stageIndex = min(max(index, 0), count - 1)
        }
        if announce { announceStage() }
    }

    func cycleStage() {
        let count = stages.filter(\.enabled).count
        guard count > 0 else { return }
        selectStage((clampedStageIndex + 1) % count)
    }

    func stepStage(_ delta: Int) {
        let count = stages.filter(\.enabled).count
        guard count > 0 else { return }
        selectStage(min(max(clampedStageIndex + delta, 0), count - 1))
    }

    func beginSniper() {
        if sniperSavedCustomEnabled == nil {
            sniperSavedCustomEnabled = customEnabled
        }
        batchUpdate {
            if !customEnabled { customEnabled = true }
            sniperActive = true
        }
        announceStage()
    }

    func endSniper(announce: Bool = true) {
        let restoreOff = (sniperSavedCustomEnabled == false)
        sniperSavedCustomEnabled = nil
        guard sniperActive || restoreOff else { return }
        batchUpdate {
            sniperActive = false
            if restoreOff { customEnabled = false }
        }
        if announce && customEnabled { announceStage() }
    }

    func announceStage() {
        guard showStageHUD else { return }
        let enabled = stages.filter(\.enabled)
        guard sniperActive || !enabled.isEmpty else { return }
        let paletteCount = DPIStage.palette.count
        let rawColorIdx = currentStage?.colorIndex ?? 0
        let safeIdx = ((rawColorIdx % paletteCount) + paletteCount) % paletteCount
        let color = sniperActive ? NSColor.systemGray : DPIStage.palette[safeIdx]
        let label = sniperActive ? "Sniper" : "Stage \(clampedStageIndex + 1) of \(enabled.count)"
        StageHUD.shared.show(dpi: appliedDPI, label: label, color: color)
    }

    func resetStages() {
        batchUpdate {
            stages = DPIStage.defaults
            stageIndex = 2
        }
    }

    private func activeStageID(in stageList: [DPIStage], index: Int) -> UUID? {
        let enabled = stageList.filter(\.enabled)
        guard !enabled.isEmpty else { return nil }
        return enabled[min(max(index, 0), enabled.count - 1)].id
    }

    private func sanitizeStages() {
        isSanitizingStages = true
        defer { isSanitizingStages = false }
        if stages.isEmpty {
            stages = DPIStage.defaults
            return
        }
        let paletteCount = DPIStage.palette.count
        for i in stages.indices {
            let clampedDPI = min(max(stages[i].dpi, 50), 12000)
            if stages[i].dpi != clampedDPI {
                stages[i].dpi = clampedDPI
            }
            let c = stages[i].colorIndex
            let normalizedColor = ((c % paletteCount) + paletteCount) % paletteCount
            if stages[i].colorIndex != normalizedColor {
                stages[i].colorIndex = normalizedColor
            }
        }
        if stages.allSatisfy({ !$0.enabled }) {
            stages[0].enabled = true
        }
    }

    private func syncStageIndex(preserving activeID: UUID?) {
        let enabled = stages.filter(\.enabled)
        guard !enabled.isEmpty else { return }
        let nextIndex: Int
        if let activeID, let kept = enabled.firstIndex(where: { $0.id == activeID }) {
            nextIndex = kept
        } else {
            nextIndex = min(max(stageIndex, 0), enabled.count - 1)
        }
        if stageIndex != nextIndex {
            isSyncingStageIndex = true
            stageIndex = nextIndex
            isSyncingStageIndex = false
        }
    }

    func start() {
        guard timer == nil else { return }
        MouseRemapper.shared.start()
        refresh()
        let t = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.wakeTask?.cancel()
                    self.wakeTask = Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.refresh(applySettings: false)
                        self.apply()
                        self.bleBatteryReader?.refresh()
                        try? await Task.sleep(for: .milliseconds(1500))
                        guard !Task.isCancelled else { return }
                        self.refresh(applySettings: false)
                        self.apply()
                        self.bleBatteryReader?.refresh()
                        try? await Task.sleep(for: .milliseconds(2000))
                        guard !Task.isCancelled else { return }
                        self.refresh(applySettings: false)
                        self.apply()
                    }
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        wakeTask?.cancel()
        wakeTask = nil
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
        stopBLEBatteryReader()
    }

    /// Pointer multiplier relative to the mouse's stored DPI.
    static func multiplier(effectiveDPI: Int, hardwareDPI: Int) -> Double {
        min(max(Double(effectiveDPI) / Double(max(hardwareDPI, 100)), 0.05), 8)
    }

    var multiplier: Double {
        Self.multiplier(effectiveDPI: effectiveDPI, hardwareDPI: hardwareDPI)
    }

    var systemTrackingSpeed: Double {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.mouse.scaling"] as? Double) ?? 0.6875
    }

    var systemLinearScaling: Bool {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.mouse.linear"] as? Bool) ?? false
    }

    func restoreDefaults() {
        // hardwareDPI mirrors the DPI stored on the mouse itself, so it stays unchanged.
        sniperSavedCustomEnabled = nil
        batchUpdate {
            accelerationOff = false
            speed = 0.5
            customEnabled = false
            sniperActive = false
            sniperDPI = 400
            showStageHUD = true
            stages = DPIStage.defaults
            stageIndex = 2
            bindings = [:]
            gestures = [:]
            gestureDistance = 50
            reverseScroll = false
            scrollQuarterSteps = 4
            debounceMS = 0
        }
    }

    // Each setting writes only its own key on change; encode() handles stages & bindings.
}
