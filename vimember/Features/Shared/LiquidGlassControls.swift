import SwiftUI

struct LiquidGlassCapsuleSurface: View {
    let width: CGFloat
    let height: CGFloat
    let xScale: CGFloat
    var isEnabled = true

    var body: some View {
        let innerStroke = max(0.7, 1.0 * xScale)
        let darkStroke = max(0.4, 0.5 * xScale)

        ZStack {
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.clear)
                    .glassEffect(.regular.interactive(), in: Capsule())

                Capsule()
                    .fill(surfaceOverlay)
                    .blendMode(.plusLighter)

                broadHighlight
            }
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                rimHighlight
            }
            .overlay(alignment: .bottomTrailing) {
                refractiveEdge
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderGradient, lineWidth: innerStroke)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.black.opacity(0.14), lineWidth: darkStroke)
                    .blur(radius: 0.45 * xScale)
            )
            .shadow(color: .white.opacity(0.42), radius: 8 * xScale, x: -2 * xScale, y: -2 * xScale)
            .shadow(color: .black.opacity(0.16), radius: 12 * xScale, y: 4 * xScale)
            .shadow(color: .black.opacity(0.22), radius: 36 * xScale, y: 10 * xScale)
        }
        .frame(width: width, height: height)
        .opacity(isEnabled ? 1 : 0.48)
        .allowsHitTesting(false)
    }

    private var surfaceOverlay: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.025),
                Color.white.opacity(0.010),
                Color.white.opacity(0.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.96),
                Color.white.opacity(0.58),
                Color.white.opacity(0.24)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var broadHighlight: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.70),
                        Color.white.opacity(0.20),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width * 0.42, height: height * 0.32)
            .blur(radius: 3.5 * xScale)
            .offset(x: 4 * xScale, y: 2 * xScale)
            .clipShape(Capsule())
    }

    private var rimHighlight: some View {
        Capsule()
            .fill(Color.white.opacity(0.82))
            .frame(
                width: min(width * 0.34, height * 1.5),
                height: max(2, height * 0.075)
            )
            .blur(radius: 1.6 * xScale)
            .offset(x: 10 * xScale, y: 5 * xScale)
    }

    private var refractiveEdge: some View {
        let edgeSize = height * 0.72
        let lineWidth = max(0.7, 1.1 * xScale)
        let blurRadius = 0.9 * xScale
        let offsetX = -height * 0.16
        let offsetY = -height * 0.10

        return Circle()
            .strokeBorder(Color.cyan.opacity(0.18), lineWidth: lineWidth)
            .frame(width: edgeSize, height: edgeSize)
            .blur(radius: blurRadius)
            .offset(x: offsetX, y: offsetY)
    }
}

struct LiquidGlassRoundedSurface: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let xScale: CGFloat
    var isEnabled = true
    var shadowRadius: CGFloat?
    var shadowYOffset: CGFloat?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let innerStroke = max(0.7, 1.0 * xScale)
        let darkStroke = max(0.4, 0.5 * xScale)

        ZStack {
            ZStack(alignment: .topLeading) {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.interactive(), in: shape)

                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.030),
                                Color.white.opacity(0.012),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.70))
                    .frame(width: width * 0.38, height: min(height * 0.08, 24 * xScale))
                    .blur(radius: 2.0 * xScale)
                    .offset(x: 14 * xScale, y: 10 * xScale)
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color.white.opacity(0.46),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: innerStroke
                )
            )
            .overlay(
                shape.strokeBorder(Color.black.opacity(0.10), lineWidth: darkStroke)
                    .blur(radius: 0.45 * xScale)
            )
            .shadow(color: .white.opacity(0.34), radius: 8 * xScale, x: -2 * xScale, y: -2 * xScale)
            .shadow(color: .black.opacity(0.13), radius: 12 * xScale, y: 4 * xScale)
            .shadow(
                color: .black.opacity(0.18),
                radius: shadowRadius ?? 36 * xScale,
                y: shadowYOffset ?? 10 * xScale
            )
        }
        .frame(width: width, height: height)
        .opacity(isEnabled ? 1 : 0.48)
        .allowsHitTesting(false)
    }
}

struct LiquidGlassIconButton: View {
    let systemName: String
    let size: CGFloat
    let symbolSize: CGFloat
    var symbolWeight: Font.Weight = .semibold
    var foregroundColor: Color = .black
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                GlassEffectContainer(spacing: 0) {
                    LiquidGlassCapsuleSurface(
                        width: size,
                        height: size,
                        xScale: max(size / 44, 0.1),
                        isEnabled: isEnabled
                    )
                }

                Image(systemName: systemName)
                    .font(.system(size: symbolSize, weight: symbolWeight))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foregroundColor)
                    .opacity(isEnabled ? 1 : 0.42)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct LiquidGlassPillButton: View {
    let width: CGFloat
    let height: CGFloat
    var title: String?
    var systemName: String?
    var symbolSize: CGFloat?
    var foregroundColor: Color = .black
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                GlassEffectContainer(spacing: 0) {
                    LiquidGlassCapsuleSurface(
                        width: width,
                        height: height,
                        xScale: max(height / 44, 0.1),
                        isEnabled: isEnabled
                    )
                }

                if let title {
                    Text(title)
                        .font(.system(size: 16 * (height / 40), weight: .medium))
                        .tracking(0.16 * (height / 40))
                        .foregroundStyle(foregroundColor)
                        .opacity(isEnabled ? 1 : 0.42)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: symbolSize ?? max(18, height * 0.40), weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(foregroundColor)
                        .opacity(isEnabled ? 1 : 0.42)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
