import Foundation

/// Generador pseudoaleatorio determinista (mismo día → mismo plan).
private struct LCG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
    mutating func unit() -> Double { Double(next() % 10_000) / 10_000 }
}

/// Elige recetas del recetario para cubrir los objetivos de cada comida.
/// Determinista por fecha, con memoria de los últimos días para variar.
final class MealPlanner {
    let recetas: [Recipe]
    var history: MealHistory
    let dieta: Dieta

    init(recetas: [Recipe], history: MealHistory, dieta: Dieta = .vegano) {
        self.recetas = recetas
        self.history = history
        self.dieta = dieta
    }

    // MARK: Plan del día

    /// `fijadas`: recetas ya elegidas hoy (swaps del usuario) que se respetan.
    /// `preferir`: recetas recién desbloqueadas (cambio de dieta) con bono de
    /// estreno, para que el cambio se note el mismo día.
    func plan(
        fecha: Date, targets: [MealTarget], fijadas: [String: String],
        preferir: Set<String> = []
    ) -> [PlannedMeal] {
        var rng = LCG(state: semilla(fecha))
        let antiguedad = recienteAntiguedad(fecha: fecha)
        var usadasHoy = Set<String>()
        var tieneOmega3 = false
        var out: [PlannedMeal] = []

        for target in targets {
            let fijada = fijadas[target.slot.rawValue].flatMap { id in recetas.first { $0.id == id } }
            let meal: PlannedMeal?
            if let r = fijada, r.momentos.contains(target.slot) {
                meal = PlannedMeal(slot: target.slot, recipe: r, porciones: mejorPorcion(r, target).porcion)
            } else {
                meal = elegir(
                    target: target, excluir: [], usadasHoy: usadasHoy,
                    antiguedad: antiguedad, tieneOmega3: tieneOmega3,
                    preferir: preferir, rng: &rng)
            }
            if let m = meal {
                usadasHoy.insert(m.recipe.id)
                if m.recipe.micros.contains("omega3") { tieneOmega3 = true }
                out.append(m)
            }
        }
        return out
    }

    /// Alternativa para un slot (botón "cambiar"): excluye la receta actual.
    func alternativa(
        fecha: Date, target: MealTarget, actual: String, otrasDeHoy: Set<String>
    ) -> PlannedMeal? {
        var rng = LCG(state: semilla(fecha) ^ UInt64(abs(actual.hashValue)))
        return elegir(
            target: target, excluir: [actual], usadasHoy: otrasDeHoy,
            antiguedad: recienteAntiguedad(fecha: fecha), tieneOmega3: true,
            preferir: [], rng: &rng)
    }

    // MARK: Selección

    private func elegir(
        target: MealTarget, excluir: [String], usadasHoy: Set<String>,
        antiguedad: [String: Int], tieneOmega3: Bool,
        preferir: Set<String>, rng: inout LCG
    ) -> PlannedMeal? {
        let candidatas = recetas.filter {
            $0.momentos.contains(target.slot) && !excluir.contains($0.id)
        }
        guard !candidatas.isEmpty else { return nil }

        var mejor: (recipe: Recipe, porcion: Double, score: Double)?
        for r in candidatas {
            let (porcion, err) = mejorPorcion(r, target)
            var score = err
            if usadasHoy.contains(r.id) { score += 1.5 }
            switch antiguedad[r.id] {
            case 1: score += 0.9   // ayer
            case 2: score += 0.55
            case 3: score += 0.35
            case 4: score += 0.2
            case 5: score += 0.1
            default: break
            }
            if target.slot == .almuerzo && r.micros.contains("hierro") { score -= 0.12 }
            if !tieneOmega3 && r.micros.contains("omega3") { score -= 0.15 }
            if preferir.contains(r.id) { score -= 0.35 }   // estreno por cambio de dieta

            // Afinidad: quien eligió "como de todo" espera ver su proteína
            // (carne, pescado, huevo) protagonista, no solo platos veganos.
            switch dieta {
            case .omnivoro:
                if r.dietaMin == .omnivoro { score -= 0.30 }
                else if r.dietaMin == .vegetariano { score -= 0.15 }
                else if r.proteinaVaria(para: .omnivoro) { score -= 0.25 }
            case .vegetariano:
                if r.dietaMin == .vegetariano { score -= 0.15 }
                else if r.proteinaVaria(para: .vegetariano) { score -= 0.10 }
            case .vegano:
                break
            }
            score += rng.unit() * 0.05
            if mejor == nil || score < mejor!.score {
                mejor = (r, porcion, score)
            }
        }
        guard let m = mejor else { return nil }
        return PlannedMeal(slot: target.slot, recipe: m.recipe, porciones: m.porcion)
    }

    /// Escala la porción (0.5×–3.0×) para acercarse al objetivo del slot,
    /// priorizando carbohidratos, luego proteína.
    private func mejorPorcion(_ r: Recipe, _ t: MealTarget) -> (porcion: Double, error: Double) {
        var mejor: (Double, Double) = (1.0, .greatestFiniteMagnitude)
        var p = 0.5
        while p <= 3.01 {
            let err = 1.0 * abs(r.carbs * p - t.carbs) / max(t.carbs, 25)
                + 0.7 * abs(r.prot * p - t.prot) / max(t.prot, 15)
                + 0.35 * abs(r.grasa * p - t.grasa) / max(t.grasa, 12)
            if err < mejor.1 { mejor = (p, err) }
            p += 0.25
        }
        return mejor
    }

    // MARK: Historial

    private func semilla(_ fecha: Date) -> UInt64 {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: fecha)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return UInt64(y * 10_000 + m * 100 + d)
    }

    /// recipeId → hace cuántos días se usó (1–5), mirando el historial.
    private func recienteAntiguedad(fecha: Date) -> [String: Int] {
        var out: [String: Int] = [:]
        for atras in 1...5 {
            guard let d = Calendar.current.date(byAdding: .day, value: -atras, to: fecha) else { continue }
            let clave = Fechas.clave(d)
            for (_, id) in history[clave] ?? [:] {
                if out[id] == nil { out[id] = atras }
            }
        }
        return out
    }
}
