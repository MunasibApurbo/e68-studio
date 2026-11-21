import SwiftUI

/// Connection state badge for the keyboard, always visible in the corner of Desk and Studio views.
struct StatusPill: View {
    @EnvironmentObject private var store: KeyboardStore
    /// Name and state only, for narrow windows.
    var compact = false
    /// Without its own glass capsule, for sitting beside the other device inside a shared one.
    var bare = false

    private var statusColor: Color {
        switch store.connection {
        case .ready: return .green
        case .bluetooth: return .blue
        case .loading: return .yellow
        case .failed: return .orange
        case .searching: return .gray
        }
    }

    private var title: String {
        switch store.connection {
        case .ready:
            return store.device?.product ?? "E68"
        case .bluetooth:
            return store.bluetoothDevice?.product ?? "E-68 PRO"
        case .loading:
            return compact ? "Reading…" : "Reading keyboard…"
        case .failed:
            return compact ? "No response" : "Not responding"
        case .searching:
            return "Not connected"
        }
    }

    private var isConnected: Bool {
        switch store.connection {
        case .ready, .bluetooth: return true
        case .loading, .failed, .searching: return false
        }
    }

    private var linkTag: String? {
        guard !compact else { return nil }
        switch store.connection {
        case .ready:
            return DeviceStatusPill.shortLink(store.device?.link ?? "USB")
        case .bluetooth:
            return "BT"
        default:
            return nil
        }
    }

    private var battery: Int? {
        if case .bluetooth = store.connection {
            return store.bluetoothDevice?.batteryLevel
        }
        return nil
    }

    private var fnActive: Bool {
        !compact && store.connection == .ready && store.effectiveLayer != store.activeLayer
    }

    var body: some View {
        DeviceStatusPill(
            symbol: "keyboard",
            statusColor: statusColor,
            title: title,
            isConnected: isConnected,
            linkTag: linkTag,
            battery: battery,
            fnActive: fnActive,
            compact: compact,
            bare: bare
        )
    }
}

/// Connection badge for the mouse studio.
struct MouseStatusPill: View {
    @ObservedObject private var mouse = MouseStore.shared
    var compact = false
    var bare = false

    var body: some View {
        let info = mouse.info
        DeviceStatusPill(
            symbol: "computermouse",
            statusColor: info == nil ? .gray : .green,
            title: info?.product ?? "Not connected",
            isConnected: info != nil,
            linkTag: (!compact && info != nil) ? DeviceStatusPill.shortLink(info!.link) : nil,
            battery: info?.battery,
            fnActive: false,
            compact: compact,
            bare: bare
        )
    }
}

/// Shared status badge for the keyboard and the mouse: a status light, the device's name, then how it
/// is connected and its battery as quiet text. No icons or boxed tags; the light carries the state.
private struct DeviceStatusPill: View {
    let symbol: String
    let statusColor: Color
    let title: String
    let isConnected: Bool
    let linkTag: String?
    let battery: Int?
    let fnActive: Bool
    let compact: Bool
    var bare = false

    var body: some View {
        let content = HStack(spacing: 6) {
            StatusDot(color: statusColor)

            Image(systemName: symbol)
                .font(.studioMeta.weight(.medium))
                .foregroundStyle(isConnected ? Color.primary : Ink.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.studioDetail.weight(isConnected ? .semibold : .medium))
                .foregroundStyle(isConnected ? Color.primary : Ink.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())

            if let linkTag {
                Text(linkTag)
                    .font(.studioMeta.weight(.medium))
                    .foregroundStyle(Ink.secondary)
            }

            if fnActive {
                PillTag(text: "Fn", emphasized: true)
            }

            if let battery {
                Text("\(battery)%")
                    .font(.studioMeta.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(battery <= 20 ? Color.orange : Ink.secondary)
                    .contentTransition(.numericText())
            }
        }
        .animation(Motion.swap, value: title)
        .animation(Motion.swap, value: linkTag)
        .animation(Motion.swap, value: battery)
        .padding(.horizontal, compact ? 10 : 12)
        .frame(height: Hit.bar)
        .accessibilityElement(children: .combine)

        if bare {
            content.contentShape(Rectangle())
        } else {
            content.glassSurface(elevation: .low, scrim: true).fixedSize()
        }
    }

    static func shortLink(_ link: String) -> String {
        let lower = link.lowercased()
        if lower.contains("bluetooth") { return "BT" }
        if lower.contains("2.4") || lower.contains("receiver") || lower.contains("dongle") { return "2.4G" }
        if lower.contains("usb") || lower.contains("cable") { return "USB" }
        return link
    }
}

/// Micro-badge for transport (`USB`, `2.4G`, `BT`) or active layer (`Fn`).
private struct PillTag: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.studioMeta.weight(.medium))
            .foregroundStyle(emphasized ? Color.accentColor : Ink.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(emphasized ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.08))
            )
    }
}

/// Connection-state light shared by both status pills.
struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color.gradient)
            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            .frame(width: 6.5, height: 6.5)
            .shadow(color: color.opacity(0.55), radius: 3)
    }
}
