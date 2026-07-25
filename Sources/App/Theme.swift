import SwiftUI

/// Sistema de diseño de Recarga — colores y tipografía tomados 1:1 del
/// archivo de Figma (Diners Design System benchmark). El diseño es "light":
/// se usan colores explícitos para que se vea idéntico en cualquier apariencia.
enum Theme {

    // MARK: Colores (tokens del archivo de Figma)

    static let darkest = Color(hex: 0x0F1217)   // $primary/darkest — texto principal, botón refresh
    static let dark = Color(hex: 0x232830)      // $primary/default — botón oscuro "cómo prepararlo"
    static let darkLight = Color(hex: 0x3A4250) // $primary/light
    static let muted = Color(hex: 0x70829E)     // $primary/lightest — texto secundario, tag HOY
    static let smoke = Color(hex: 0xEFF1F3)     // $neutral/smoke — contenedores, pills, botones claros
    static let paper = Color(hex: 0xFAFAFA)     // $neutral/white — fondo y tarjetas
    static let border = Color(hex: 0xDDDFE0)    // $neutral/grey — bordes
    static let mint = Color(hex: 0x00C8B3)      // Accents/Mint — acento, gráficos, activo

    static let white = Color(hex: 0xFFFFFF)
    static let cardBackground = white
    static let pageBackground = paper

    // MARK: Tipografía

    /// Inter (títulos y texto) — pesos empaquetados: Light, Regular, Bold, Black.
    enum Inter: String {
        case light = "Inter-Light"
        case regular = "Inter-Regular"
        case bold = "Inter-Bold"
        case black = "Inter-Black"
    }

    static func inter(_ w: Inter, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(w.rawValue, size: size, relativeTo: style)
    }

    /// Chivo Mono Light — solo para el logo REC◆RGA.
    static func mono(_ size: CGFloat) -> Font {
        .custom("ChivoMono-Light", size: size, relativeTo: .title)
    }

    // Escala tipográfica usada en la pantalla (tamaños del Figma).
    static let logo = mono(24)
    static let displayLight = inter(.light, 44, relativeTo: .largeTitle)
    static let displayBlack = inter(.black, 44, relativeTo: .largeTitle)
    static let heroBold = inter(.bold, 20, relativeTo: .title3)
    static let heroRegular = inter(.regular, 20, relativeTo: .title3)
    static let sectionLabel = inter(.bold, 11, relativeTo: .caption)   // "DATA DE ENTRENAMIENTO"
    static let cardLabel = inter(.bold, 11, relativeTo: .caption)      // "ENERGÍA"
    static let metricValue = inter(.black, 27, relativeTo: .title)     // "3,465"
    static let metricUnit = inter(.regular, 15, relativeTo: .subheadline)
    static let mealItem = inter(.regular, 28, relativeTo: .title)      // lista de comidas
    static let mealItemActive = inter(.bold, 28, relativeTo: .title)
    static let detailTitle = inter(.bold, 20, relativeTo: .title3)
    static let detailMacros = inter(.regular, 14, relativeTo: .subheadline)
    static let detailBody = inter(.regular, 15, relativeTo: .body)
    static let buttonLabel = inter(.bold, 11, relativeTo: .caption)
    static let footer = inter(.regular, 13, relativeTo: .footnote)

    // Métricas de layout
    static let containerRadius: CGFloat = 24
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 12
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Estilos reutilizables

/// Etiqueta de sección: mayúsculas, tracking, gris oscuro.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.darkest
    var body: some View {
        Text(text.uppercased())
            .font(Theme.sectionLabel)
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// Botón de icono cuadrado redondeado (header).
struct IconSquareButton: View {
    let system: String
    var dark: Bool = false
    var label: String
    var value: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(dark ? Theme.white : Theme.darkest)
                .frame(width: 41, height: 41)
                .background(
                    RoundedRectangle(cornerRadius: 10.5)
                        .fill(dark ? Theme.darkest : Theme.smoke)
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
