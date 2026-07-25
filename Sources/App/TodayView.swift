import SwiftUI

struct TodayView: View {
    @EnvironmentObject var state: AppState
    @Binding var mostrarAjustes: Bool
    @State private var mostrarSemana = false
    @State private var pagina: String? = "hoy"

    private var dietaUsuario: Dieta { state.profile?.dieta ?? .vegano }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 20)

            if let plan = state.plan {
                pager(plan)
            } else {
                Spacer()
            }

            footer
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
        }
        .background(Theme.pageBackground)
        .sheet(isPresented: $mostrarSemana) {
            WeekView().environmentObject(state)
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            LogoRecarga()
            HStack {
                IconSquareButton(system: "arrow.clockwise", dark: true,
                                 label: "Recalcular el plan de hoy",
                                 value: state.ocupado ? "Actualizando" : "") {
                    Task { await state.refresh() }
                }
                .overlay(alignment: .center) {
                    if state.ocupado {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    IconSquareButton(system: "cart", label: "Ver la semana y la lista de compras") { mostrarSemana = true }
                    IconSquareButton(system: "gearshape", label: "Ajustes") { mostrarAjustes = true }
                }
            }
        }
    }

    // MARK: Paginación (Hoy ↔ Checklist)

    private func pager(_ plan: DayPlan) -> some View {
        // Cada página mide AL MENOS el alto del viewport (llena la pantalla y
        // deja la 2ª bajo el pliegue), pero puede crecer y hacer scroll si el
        // contenido no cabe — así nada se recorta ni queda inalcanzable.
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        paginaHoy(plan)
                            .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                            .id("hoy")
                        paginaChecklist(plan)
                            .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                            .id("checklist")
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $pagina)
                .scrollIndicators(.hidden)
                .overlay(alignment: .trailing) {
                    dots(proxy).padding(.trailing, 10)
                }
            }
        }
    }

    private func dots(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 14) {
            dot("hoy", proxy)
            dot("checklist", proxy)
        }
    }

    private func dot(_ id: String, _ proxy: ScrollViewProxy) -> some View {
        Button {
            // Un solo mecanismo, todo dentro de la misma transacción animada.
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(id, anchor: .top)
                pagina = id
            }
        } label: {
            Circle()
                .fill(pagina == id ? Theme.darkest : Theme.border)
                .frame(width: 8, height: 8)
                .padding(6)               // área de click más amplia
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(id == "hoy" ? "Ir a Hoy" : "Ir al Checklist")
        .accessibilityLabel(id == "hoy" ? "Ir a Hoy" : "Ir al Checklist")
    }

    // MARK: Página 1 — Hoy

    private func paginaHoy(_ plan: DayPlan) -> some View {
        VStack(spacing: 18) {
            if let msg = state.errorMsg { avisoCompacto(msg, color: .red) }
            if !state.stravaConectado && !state.garminConectado {
                avisoCompacto("Conecta Strava o Garmin en Ajustes para usar tus entrenos reales.", color: Theme.muted)
            }

            tituloBloque(plan)
            RecomendacionesBar(plan: plan, pesoKg: state.profile?.pesoKg ?? 70)
            TrainingDataGrid(plan: plan)
            MealSection(plan: plan, dieta: dietaUsuario) { slot in
                state.cambiarComida(slot)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
    }

    private func tituloBloque(_ plan: DayPlan) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("HOY")
                    .font(Theme.inter(.bold, 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.smoke))
                tituloFecha(plan.fecha)
            }
            VStack(spacing: 4) {
                Text(entrenoTitulo(plan))
                    .font(Theme.heroBold)
                    .foregroundStyle(Theme.darkest)
                Text(entrenoLinea(plan))
                    .font(Theme.heroRegular)
                    .foregroundStyle(Theme.muted)
            }
            .multilineTextAlignment(.center)
        }
    }

    private func tituloFecha(_ fecha: Date) -> some View {
        let wd = Self.diaSemana.string(from: fecha).capitalized
        let resto = "\(Self.diaNum.string(from: fecha)) de \(Self.diaMes.string(from: fecha).capitalized)"
        return (
            Text(wd + " ").font(Theme.displayLight)
            + Text(resto).font(Theme.displayBlack).underline()
        )
        .foregroundStyle(Theme.darkest)
    }

    // MARK: Página 2 — Checklist

    private func paginaChecklist(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: dietaUsuario == .vegano ? "Checklist vegano runner" : "Checklist runner")
                Text("Lo que un runner \(dietaUsuario == .vegano ? "vegano " : "")necesita cubrir hoy")
                    .font(Theme.inter(.black, 30, relativeTo: .title))
                    .foregroundStyle(Theme.darkest)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(plan.checklist) { item in
                    checklistCard(item)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }

    private func checklistCard(_ item: ChecklistItem) -> some View {
        let esB12 = item.nombre.hasPrefix("B12")
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: esB12 ? "pills.fill" : (item.cubierto ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: 22))
                .foregroundStyle(esB12 ? Theme.muted : (item.cubierto ? Theme.mint : Theme.border))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.nombre)
                    .font(Theme.inter(.bold, 16, relativeTo: .headline))
                    .foregroundStyle(Theme.darkest)
                Text(item.detalle)
                    .font(Theme.inter(.regular, 14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.smoke))
    }

    // MARK: Footer

    private var footer: some View {
        (
            Text("Recarga es una app orientativa, no es consejo médico. ")
                .font(Theme.footer)
            + Text("Reglas: ISSN/ACSM para deportes de resistencia")
                .font(Theme.inter(.regular, 13).italic())
        )
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func avisoCompacto(_ texto: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 13))
            Text(texto).font(Theme.inter(.regular, 13))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    // MARK: Textos del entreno

    private func entrenoTitulo(_ plan: DayPlan) -> String {
        switch plan.estadoCarrera {
        case .diaDeCarrera(let c): return "Carrera: \(c.nombre)"
        case .enCarga(let c, let d): return "Carga — \(c.nombre) en \(d) día\(d == 1 ? "" : "s")"
        case .normal: return plan.targets.dayType.label
        }
    }

    private func entrenoLinea(_ plan: DayPlan) -> String {
        let runs = state.actividadesHoy.filter(\.esRun)
        if runs.isEmpty {
            if plan.targets.dayType == .descanso { return "Sin entreno hoy" }
            if plan.targets.dayType == .carga { return "Carga de carbohidratos · sin entreno fuerte" }
            // Actividad de hoy que no es carrera a pie (fuerza, bici, natación).
            if let otra = state.actividadesHoy.first {
                return String(format: "%@ / %@ / ~%@ kcal (STRAVA)",
                              otra.name, otra.duracionTexto, Fmt.kcal(plan.targets.trainingKcal))
            }
            if let w = state.garminPlan[Fechas.clave(Date())], GarminPlan.tipoDe(w) != nil {
                return String(format: "%@ / ~%@ kcal (GARMIN)", w.titulo, Fmt.kcal(plan.targets.trainingKcal))
            }
            return String(format: "según plantilla / ~%@ kcal", Fmt.kcal(plan.targets.trainingKcal))
        }
        let km = runs.reduce(0.0) { $0 + $1.km }
        let tiempo = runs.map(\.duracionTexto).joined(separator: " + ")
        return String(format: "%.1f km / %@ / %@ kcal (STRAVA)", km, tiempo, Fmt.kcal(plan.targets.trainingKcal))
    }

    // Formateadores de fecha para el título grande.
    static let diaSemana: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_PE"); f.dateFormat = "EEEE"; return f
    }()
    static let diaNum: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_PE"); f.dateFormat = "d"; return f
    }()
    static let diaMes: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_PE"); f.dateFormat = "MMMM"; return f
    }()
}

// MARK: - Logo REC◆RGA

struct LogoRecarga: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("REC").font(Theme.logo).foregroundStyle(Theme.darkest)
            Sparkle().fill(Theme.darkest)
                .frame(width: 15, height: 22)
                .padding(.horizontal, 1)
            Text("RGA").font(Theme.logo).foregroundStyle(Theme.darkest)
        }
    }
}

/// Rombo de 4 puntas (sparkle) del logo — lados cóncavos hacia el centro.
struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let top = CGPoint(x: c.x, y: r.minY)
        let right = CGPoint(x: r.maxX, y: c.y)
        let bottom = CGPoint(x: c.x, y: r.maxY)
        let left = CGPoint(x: r.minX, y: c.y)
        // Controles hacia el centro (concavidad ~60%).
        let k: CGFloat = 0.62
        let cTop = CGPoint(x: c.x, y: r.minY + (c.y - r.minY) * k)
        let cRight = CGPoint(x: r.maxX - (r.maxX - c.x) * k, y: c.y)
        let cBottom = CGPoint(x: c.x, y: r.maxY - (r.maxY - c.y) * k)
        let cLeft = CGPoint(x: r.minX + (c.x - r.minX) * k, y: c.y)
        var p = Path()
        p.move(to: top)
        p.addQuadCurve(to: right, control: CGPoint(x: cRight.x, y: cTop.y))
        p.addQuadCurve(to: bottom, control: CGPoint(x: cRight.x, y: cBottom.y))
        p.addQuadCurve(to: left, control: CGPoint(x: cLeft.x, y: cBottom.y))
        p.addQuadCurve(to: top, control: CGPoint(x: cLeft.x, y: cTop.y))
        p.closeSubpath()
        return p
    }
}

// MARK: - Recomendaciones (recuperación + hidratación)

struct RecomendacionesBar: View {
    let plan: DayPlan
    let pesoKg: Double

    var body: some View {
        let r = NutritionEngine.recomendaciones(day: plan.targets, pesoKg: pesoKg)
        return HStack(spacing: 12) {
            tarjeta(
                icono: "bolt.heart.fill",
                label: "Ventana de recuperación",
                valor: r.hayEntreno ? "\(r.recuperacionCarbs) g C + \(r.recuperacionProt) g P" : "Proteína repartida",
                detalle: r.recuperacionDetalle)
            tarjeta(
                icono: "drop.fill",
                label: "Hidratación",
                valor: String(format: "%.1f L", r.hidratacionLitros),
                detalle: r.hidratacionDetalle)
        }
    }

    private func tarjeta(icono: String, label: String, valor: String, detalle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icono)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.mint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.mint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(Theme.cardLabel).tracking(1.1)
                    .foregroundStyle(Theme.muted)
                Text(valor)
                    .font(Theme.inter(.bold, 16, relativeTo: .headline))
                    .foregroundStyle(Theme.darkest)
                Text(detalle)
                    .font(Theme.inter(.regular, 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.smoke))
    }
}
