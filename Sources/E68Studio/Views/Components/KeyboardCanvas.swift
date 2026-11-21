import SwiftUI

extension Color {
    /// A colour that follows the window's light or dark appearance.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                           blue: CGFloat(v & 0xff) / 255, alpha: 1)
        })
    }
}

enum Palette {
    static let plate = Color.adaptive(light: 0xCFD1D6, dark: 0x121315)
    static let legend = Color.adaptive(light: 0x26272B, dark: 0xE8E8EB)
    static let legendDim = Color.adaptive(light: 0x7A7C84, dark: 0x8E9098)
    static let tested = Color.adaptive(light: 0x2E8B57, dark: 0x4CC38A)

    static func capSide(_ tone: Tone) -> Color {
        switch tone {
        case .alpha: return .adaptive(light: 0xD9DADF, dark: 0x2B2D31)
        case .mod: return .adaptive(light: 0xC4C6CD, dark: 0x232528)
        case .accent: return .adaptive(light: 0xB3B6BF, dark: 0x1E2023)
        }
    }

    static func capTop(_ tone: Tone) -> Color {
        switch tone {
        case .alpha: return .adaptive(light: 0xFCFCFD, dark: 0x3D4046)
        case .mod: return .adaptive(light: 0xE9EAEE, dark: 0x32353A)
        case .accent: return .adaptive(light: 0xDADCE2, dark: 0x2B2D32)
        }
    }
}

enum CapState {
    case normal, selected, pressed, tested
}

/// A single keycap: a darker skirt with a lighter top face, like a real cap seen from above.
struct KeyCap: View {
    let legend: Legend
    var tone: Tone = .alpha
    var state: CapState = .normal
    var modified = false
    /// Backlight colour bleeding around the cap, for the lighting preview.
    var glow: Color? = nil
    let unit: CGFloat
    var interactive = true

    @ViewState private var hovering = false

    private var topFill: Color {
        switch state {
        case .pressed: return .accentColor
        case .selected: return Palette.capTop(tone)
        case .tested: return Palette.capTop(tone)
        case .normal: return Palette.capTop(tone)
        }
    }

    private var legendColor: Color {
        state == .pressed ? .white : Palette.legend
    }

    private var mainSize: CGFloat {
        if legend.symbol != nil { return unit * 0.27 }
        switch legend.main.count {
        case 0...1: return unit * (legend.top == nil ? 0.31 : 0.28)
        case 2...3: return unit * 0.23
        case 4...5: return max(9.5, unit * 0.20)
        default: return max(9.0, unit * 0.19)
        }
    }

    var body: some View {
        let r = unit * 0.18
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Palette.capSide(tone))
            if let glow {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(glow.opacity(0.55))
            }
            RoundedRectangle(cornerRadius: r * 0.78, style: .continuous)
                .fill(topFill)
                .overlay {
                    if state == .selected {
                        RoundedRectangle(cornerRadius: r * 0.78, style: .continuous).fill(Color.accentColor.opacity(0.16))
                    } else if state == .tested {
                        RoundedRectangle(cornerRadius: r * 0.78, style: .continuous).fill(Palette.tested.opacity(0.22))
                    } else if hovering && interactive {
                        RoundedRectangle(cornerRadius: r * 0.78, style: .continuous).fill(Color.primary.opacity(0.05))
                    }
                }
                .padding(.horizontal, unit * 0.065)
                .padding(.top, unit * 0.04)
                .padding(.bottom, unit * 0.10)

            VStack(spacing: unit * 0.01) {
                if let top = legend.top {
                    Text(top)
                        .font(.system(size: max(8.5, unit * 0.18), weight: .medium))
                        .foregroundStyle(state == .pressed ? Color.white.opacity(0.85) : Palette.legendDim)
                }
                if let symbol = legend.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: mainSize, weight: .medium))
                        .foregroundStyle(legendColor)
                } else {
                    Text(legend.main == "None" ? "" : legend.main)
                        .font(.system(size: mainSize, weight: .medium))
                        .foregroundStyle(legendColor)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, unit * 0.11)
            .padding(.bottom, unit * 0.06)

            if modified {
                Circle()
                    .fill(Color.orange)
                    .frame(width: unit * 0.1, height: unit * 0.1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, unit * 0.1)
                    .padding(.trailing, unit * 0.14)
            }
        }
        .overlay {
            if state == .selected {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: max(2, unit * 0.045))
            }
        }
        .onHover { hovering = interactive && $0 }
        .contentShape(RoundedRectangle(cornerRadius: r, style: .continuous))
    }
}
