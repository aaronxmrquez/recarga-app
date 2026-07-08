import SwiftUI

struct TodayView: View {
    @EnvironmentObject var state: AppState
    @Binding var mostrarAjustes: Bool
    @State private var mostrarSemana = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                encabezado

                if let msg = state.errorMsg {
                    banner(msg, icono: "exclamationmark.triangle.fill", color: .red)
                }
                if !state.stravaConectado {
                    banner("Strava no está conectado: el plan usa solo tu plantilla semanal. Conéctalo en Ajustes ⚙︎ para usar tus entrenos reales.",
                           icono: "bolt.horizontal.circle", color: .orange)
                }

                if let plan = state.plan {
                    objetivosView(plan)
                    if !plan.consejos.isEmpty { consejosView(plan) }
                    comidasView(plan)
                    checklistView(plan)
                    piePagina(plan)
                }
            }
            .padding(22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Encabezado

    private var encabezado: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Fechas.tituloDia.string(from: Date()).capitalized)
                    .font(.title.bold())
                if let plan = state.plan {
                    HStack(spacing: 8) {
                        let chip = chipDia(plan)
                        Label(chip.0, systemImage: chip.1)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                        Text(lineaEntreno(plan))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            HStack(spacing: 10) {
                if state.ocupado {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await state.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.ocupado)
                .help("Actualizar desde Strava")

                Button {
                    mostrarSemana = true
                } label: {
                    Image(systemName: "cart")
                }
                .help("Semana y lista de compras")

                Button {
                    mostrarAjustes = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Ajustes")
            }
            .buttonStyle(.bordered)
        }
        .sheet(isPresented: $mostrarSemana) {
            WeekView().environmentObject(state)
        }
    }

    private func chipDia(_ plan: DayPlan) -> (String, String) {
        switch plan.estadoCarrera {
        case .diaDeCarrera(let c):
            return ("Carrera: \(c.nombre)", "flag.checkered")
        case .enCarga(let c, let dias):
            return ("Carga — \(c.nombre) en \(dias) día\(dias == 1 ? "" : "s")", "fork.knife")
        case .normal:
            return (plan.targets.dayType.label, plan.targets.dayType.icono)
        }
    }

    private func lineaEntreno(_ plan: DayPlan) -> String {
        if state.actividadesHoy.isEmpty {
            if plan.targets.dayType == .descanso { return "Sin entreno hoy" }
            if let w = state.garminPlan[Fechas.clave(Date())], GarminPlan.tipoDe(w) != nil {
                return String(format: "Garmin: %@ · ~%@ kcal", w.titulo, Fmt.kcal(plan.targets.trainingKcal))
            }
            return String(format: "según plantilla · ~%@ kcal estimadas", Fmt.kcal(plan.targets.trainingKcal))
        }
        let runs = state.actividadesHoy
        let km = runs.reduce(0.0) { $0 + $1.km }
        let tiempo = runs.map(\.duracionTexto).joined(separator: " + ")
        return String(format: "%.1f km · %@ · %@ kcal (Strava)", km, tiempo, Fmt.kcal(plan.targets.trainingKcal))
    }

    private func banner(_ texto: String, icono: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icono).foregroundStyle(color)
            Text(texto).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
    }

    // MARK: Objetivos

    private func objetivosView(_ plan: DayPlan) -> some View {
        HStack(spacing: 12) {
            tarjeta(valor: Fmt.kcal(plan.targets.kcal), unidad: "kcal", titulo: "Energía", color: .orange)
            tarjeta(valor: Fmt.g(plan.targets.carbs),
                    unidad: String(format: "%.0f g/kg", plan.targets.carbsGkg),
                    titulo: "Carbohidratos", color: .blue)
            tarjeta(valor: Fmt.g(plan.targets.prot), unidad: "reparar", titulo: "Proteína", color: .green)
            tarjeta(valor: Fmt.g(plan.targets.grasa), unidad: "mínimo sano", titulo: "Grasa", color: .purple)
        }
    }

    private func tarjeta(valor: String, unidad: String, titulo: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(titulo).font(.caption).foregroundStyle(.secondary)
            Text(valor).font(.title2.bold().monospacedDigit()).foregroundStyle(color)
            Text(unidad).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
    }

    // MARK: Consejos

    private func consejosView(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(plan.consejos, id: \.self) { c in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(.top, 3)
                    Text(c).font(.callout)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.yellow.opacity(0.07)))
    }

    // MARK: Comidas

    private func comidasView(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comidas de hoy").font(.title3.bold())
            ForEach(plan.meals) { meal in
                comidaCard(meal, dayType: plan.targets.dayType)
            }
        }
    }

    private func hora(_ slot: MealSlot, dayType: DayType) -> String {
        switch slot {
        case .preEntreno: return "≈ 4:15 am"
        case .desayuno: return dayType == .largo ? "al llegar (8:30–9:00)" : "≈ 8:00 am"
        case .almuerzo: return "≈ 1:00 pm"
        case .snack: return "≈ 4:30 pm"
        case .cena: return "≈ 7:30 pm"
        }
    }

    private func comidaCard(_ meal: PlannedMeal, dayType: DayType) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: meal.slot.icono)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.orange.opacity(0.12)))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(meal.slot.label).font(.headline)
                    Text(hora(meal.slot, dayType: dayType))
                        .font(.caption).foregroundStyle(.secondary)
                    if meal.porciones != 1 {
                        Text(Fmt.porciones(meal.porciones))
                            .font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                Text(meal.recipe.nombre).font(.title3)

                Text("\(Fmt.kcal(meal.kcal)) kcal · C \(Fmt.g(meal.carbs)) · P \(Fmt.g(meal.prot)) · G \(Fmt.g(meal.grasa)) · \(meal.recipe.tiempoMin) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text(meal.recipe.ingredientes.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let nota = meal.recipe.nota {
                    Text(nota)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button {
                state.cambiarComida(meal.slot)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Sugerir otra opción")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }

    // MARK: Checklist

    private func checklistView(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Checklist vegano-runner").font(.title3.bold())
            ForEach(plan.checklist) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.nombre.hasPrefix("B12")
                          ? "pills.circle.fill"
                          : (item.cubierto ? "checkmark.circle.fill" : "circle"))
                        .foregroundStyle(item.nombre.hasPrefix("B12")
                                         ? .blue
                                         : (item.cubierto ? .green : .secondary))
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.nombre).font(.callout.weight(.semibold))
                        Text(item.detalle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }

    private func piePagina(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suma del plan: \(Fmt.kcal(plan.totalKcal)) kcal · C \(Fmt.g(plan.totalCarbs)) · P \(Fmt.g(plan.totalProt)) · G \(Fmt.g(plan.totalGrasa))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if plan.tipoManana.esDuro {
                Text("Mañana: \(plan.tipoManana.label) — la cena ya viene ajustada.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let prox = state.proximaCarrera, prox.dias > 0 {
                Text("🏁 \(prox.carrera.nombre) (\(prox.carrera.distanciaTexto)): faltan \(prox.dias) día\(prox.dias == 1 ? "" : "s")\(prox.dias > prox.carrera.diasCarga ? " — la carga se activará sola \(prox.carrera.diasCarga) días antes." : ".")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Orientativo, no es consejo médico. Reglas: ISSN/ACSM para deporte de resistencia.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
    }
}
