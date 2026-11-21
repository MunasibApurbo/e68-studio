import AppKit
import SwiftUI

/// Per-app automatic profile switcher and manual profile manager inside Keyboard Studio › More.
struct ProfilesView: View {
    @ObservedObject private var profileStore = ProfileStore.shared
    @ObservedObject private var mouse = MouseStore.shared
    @ViewState private var newProfileName = ""
    @MainActor private static var appNameCache: [String: String] = [:]

    private var runningApps: [(name: String, bundleID: String)] {
        var seen = Set<String>()
        var list = [(String, String)]()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier,
                  !seen.contains(id) else { continue }
            seen.insert(id)
            list.append((app.localizedName ?? id, id))
        }
        return list.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    /// "com.apple.Safari" → "Safari", using the installed app's name when it can be found.
    @MainActor
    private static func appName(_ bundleID: String) -> String {
        if let cached = appNameCache[bundleID] { return cached }
        let name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else {
            let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
            name = last.prefix(1).uppercased() + last.dropFirst()
        }
        appNameCache[bundleID] = name
        return name
    }

    var body: some View {
        let currentRunningApps = runningApps
        PanelScroll {
            GroupedSection(title: "Automatic Switching") {
                GroupedRow(label: "Switch profiles by active app") {
                    Toggle("Switch profiles by active app", isOn: $profileStore.autoSwitchEnabled)
                        .labelsHidden()
                        .toggleStyle(AccentSwitchStyle())
                }
            }

            GroupedSection(title: "Saved Profiles") {
                ForEach(profileStore.profiles) { profile in
                    profileRow(profile, runningApps: currentRunningApps)
                }
            }

            GroupedSection(title: "New Profile") {
                GroupedRow(label: "Name") {
                    HStack(spacing: Space.s) {
                        TextField("Profile name", text: $newProfileName)
                            .glassField(width: 180)
                            .onSubmit(createProfile)
                        Button("Save Profile", action: createProfile)
                        .buttonStyle(.glassCapsule(.prominent, size: .small))
                        .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        profileStore.createFromCurrent(name: name)
        newProfileName = ""
    }

    private func profileRow(_ profile: StudioProfile, runningApps: [(name: String, bundleID: String)]) -> some View {
        let isActive = profileStore.activeProfileID == profile.id
        let effectName = profile.lighting.musicSync
            ? "Sound Wave (\(profile.lighting.musicMode.title))"
            : LightingCatalog.name(of: profile.lighting.effect)
        let stageInfo: String = {
            guard let idx = profile.mouseStageIndex else { return "" }
            let enabledSlots = mouse.stages.indices.filter { mouse.stages[$0].enabled }
            guard !enabledSlots.isEmpty else { return "" }
            let slot = enabledSlots[min(max(idx, 0), enabledSlots.count - 1)]
            return " · Stage \(slot + 1)"
        }()
        let appsSubtitle = profile.bundleIdentifiers.isEmpty
            ? "Manual · \(effectName) · \(LayerInfo.title(profile.activeLayer)) layer\(stageInfo)"
            : "\(profile.bundleIdentifiers.map(Self.appName).joined(separator: ", ")) · \(effectName)\(stageInfo)"

        return GroupedRow(label: profile.name, detail: appsSubtitle) {
            HStack(spacing: Space.s) {
                Menu {
                    let unrunningLinked = profile.bundleIdentifiers.filter { id in
                        !runningApps.contains { $0.bundleID.caseInsensitiveCompare(id) == .orderedSame }
                    }.sorted { Self.appName($0).localizedCaseInsensitiveCompare(Self.appName($1)) == .orderedAscending }

                    if !unrunningLinked.isEmpty {
                        Section("Linked Apps (Not Running)") {
                            ForEach(unrunningLinked, id: \.self) { id in
                                Button {
                                    profileStore.toggleAppLink(bundleID: id, for: profile.id)
                                } label: {
                                    Label(Self.appName(id), systemImage: "checkmark.circle.fill")
                                }
                            }
                        }
                    }

                    Section("Link Running Apps") {
                        ForEach(runningApps, id: \.bundleID) { app in
                            let linked = profile.bundleIdentifiers.contains {
                                $0.caseInsensitiveCompare(app.bundleID) == .orderedSame
                            }
                            Button {
                                profileStore.toggleAppLink(bundleID: app.bundleID, for: profile.id)
                            } label: {
                                Label(app.name, systemImage: linked ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                    Divider()
                    Button("Update “\(profile.name)” with Current Settings") {
                        profileStore.captureCurrentState(into: profile.id)
                    }
                    if profileStore.profiles.count > 1 {
                        Button("Delete Profile", role: .destructive) {
                            profileStore.delete(id: profile.id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: Hit.small, height: Hit.small)
                        .chip(Circle(), selected: false)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Link apps, update, or delete this profile")
                .accessibilityLabel("Profile options")

                Button(isActive ? "Active" : "Activate") {
                    profileStore.activate(profile)
                }
                .buttonStyle(.glassCapsule(isActive ? .prominent : .standard, size: .small))
                .frame(minWidth: 84)
                .disabled(isActive)
            }
        }
    }
}
