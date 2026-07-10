import Foundation

/// Motor de nutrición determinista. Reglas basadas en los position stands de
/// ISSN/ACSM para deportes de resistencia, ajustadas a dieta vegana
/// (proteína en el rango alto por digestibilidad de fuentes vegetales).
enum NutritionEngine {

    // MARK: Gasto energético

    /// Mifflin-St Jeor
    static func bmr(_ p: UserProfile) -> Double {
        let base = 10 * p.pesoKg + 6.25 * p.alturaCm - 5 * Double(p.edad)
        return base + (p.sexo == .masculino ? 5 : -161)
    }

    /// kcal del entrenamiento: usa las calorías de Strava si están; si no,
    /// estima (correr ≈ 1 kcal × kg × km; otros deportes ≈ 7 kcal/min).
    static func trainingKcal(actividades: [StravaActivity], pesoKg: Double) -> Double {
        actividades.reduce(0) { acc, a in
            if let cal = a.calories, cal > 0 { return acc + cal }
            if a.esRun { return acc + a.km * pesoKg * 1.0 }
            return acc + Double(a.movingTime) / 60.0 * 7.0
        }
    }

    /// Estimación del gasto de una sesión aún no corrida (según plantilla),
    /// con distancias típicas de un maratonista.
    static func kcalEstimada(tipo: DayType, pesoKg: Double) -> Double {
        let km: Double
        switch tipo {
        case .suave: km = 10
        case .moderado: km = 14
        case .largo: km = 30
        default: km = 0
        }
        return km * pesoKg
    }

    /// Duración estimada de la sesión según plantilla (para hidratación).
    static func horasEstimadas(tipo: DayType) -> Double {
        switch tipo {
        case .suave: return 1.0
        case .moderado: return 1.2
        case .largo: return 2.7
        default: return 0
        }
    }

    // MARK: Clasificación del día

    /// Clasifica el día según las actividades reales; si no hay, cae a la
    /// plantilla (y a partir de las 11:00 sin actividad, asume descanso).
    static func clasificarDia(
        actividades: [StravaActivity],
        plantilla: DayType,
        ahora: Date = Date()
    ) -> (tipo: DayType, esReal: Bool) {
        guard !actividades.isEmpty else {
            let hora = Calendar.current.component(.hour, from: ahora)
            if plantilla.esEntreno && hora >= 11 { return (.descanso, false) }
            return (plantilla, false)
        }
        let runs = actividades.filter(\.esRun)
        let dist = runs.reduce(0) { $0 + $1.km }
        let tiempo = actividades.reduce(0) { $0 + $1.movingTime }

        if runs.contains(where: { $0.workoutType == 3 }) { return (.moderado, true) }
        if runs.contains(where: { $0.workoutType == 2 }) || dist >= 18 || tiempo >= 95 * 60 {
            return (.largo, true)
        }
        if dist < 9 && tiempo < 55 * 60 { return (.suave, true) }
        return (.moderado, true)
    }

    // MARK: Objetivos del día

    static func dayTargets(
        profile p: UserProfile, dayType: DayType, trainingKcal: Double, horasEntreno: Double = 0
    ) -> DayTargets {
        let carbs = dayType.carbsGkg * p.pesoKg
        let prot = p.proteinaGkg * p.pesoKg
        var kcal = bmr(p) * p.factorActividad + trainingKcal
        let grasaMin = 0.8 * p.pesoKg
        var grasa = (kcal - (carbs + prot) * 4) / 9
        if grasa < grasaMin {
            grasa = grasaMin
            kcal = (carbs + prot) * 4 + grasa * 9
        }
        // Hidratación: base ~35 ml/kg/día + ~1.1 L por hora de carrera
        // (sudor ~1 L/h repuesto con margen). Redondeado a 0.1 L.
        let agua = ((0.035 * p.pesoKg + 1.1 * horasEntreno) * 10).rounded() / 10
        return DayTargets(
            dayType: dayType, kcal: kcal, carbs: carbs, prot: prot,
            grasa: grasa, trainingKcal: trainingKcal, carbsGkg: dayType.carbsGkg,
            horasEntreno: horasEntreno, aguaLitros: agua
        )
    }

    // MARK: Reparto por comidas

    /// Reparto de macros entre comidas según el tipo de día y lo que toca
    /// mañana. Aaron entrena en ayunas parciales de madrugada (despierta 4am,
    /// corre ~5:00–7:30), así que el desayuno es LA comida de recuperación.
    static func mealTargets(day: DayTargets, manana: DayType) -> [MealTarget] {
        let entrena = day.dayType.esEntreno || day.dayType == .carga
        let mananaDura = manana.esDuro

        // % de los carbohidratos del día por comida: [pre, des, alm, snack, cena]
        let c: [Double]
        let pr: [Double]
        let g: [Double]
        switch (entrena, mananaDura) {
        case (true, false):
            c = [0.10, 0.30, 0.28, 0.10, 0.22]
            pr = [0.04, 0.26, 0.28, 0.14, 0.28]
            g = [0.02, 0.20, 0.36, 0.12, 0.30]
        case (true, true):
            c = [0.10, 0.28, 0.25, 0.07, 0.30]
            pr = [0.04, 0.26, 0.28, 0.14, 0.28]
            g = [0.02, 0.22, 0.36, 0.12, 0.28]
        case (false, false):
            c = [0, 0.30, 0.32, 0.08, 0.30]
            pr = [0, 0.28, 0.30, 0.14, 0.28]
            g = [0, 0.24, 0.36, 0.10, 0.30]
        case (false, true):
            c = [0, 0.24, 0.30, 0.08, 0.38]
            pr = [0, 0.28, 0.30, 0.14, 0.28]
            g = [0, 0.24, 0.36, 0.12, 0.28]
        }

        return MealSlot.orden.enumerated().compactMap { i, slot in
            if slot == .preEntreno && !entrena { return nil }
            return MealTarget(
                slot: slot,
                carbs: day.carbs * c[i],
                prot: day.prot * pr[i],
                grasa: day.grasa * g[i]
            )
        }
    }

    // MARK: Consejos del día

    static func consejos(
        day: DayTargets, manana: DayType, huboActividad: Bool, pesoKg: Double
    ) -> [String] {
        var out: [String] = []
        if day.dayType == .largo && huboActividad {
            let c = Int(1.1 * pesoKg)
            out.append("Ventana de recuperación: desayuna dentro de la primera hora tras llegar — ~\(c) g de carbohidrato + 25–30 g de proteína (el batido o la avena del plan ya lo cubren).")
        }
        if day.dayType == .moderado {
            out.append("Día de intensidad: carbohidrato rápido antes de las series (plátano o dátiles del pre-entreno) — calidad de sesión > entrenar vacío.")
        }
        if manana.esDuro {
            out.append(manana == .carga
                ? "Empieza la carga: sube carbohidratos y baja fibra desde hoy."
                : "Mañana toca fondo: la cena de hoy va cargada de carbohidratos y más ligera en fibra y grasa, para amanecer con el glucógeno lleno.")
        }
        if day.horasEntreno >= 1.3 || day.dayType == .largo {
            let litros = String(format: "%.1f", day.aguaLitros)
            let sodio = day.horasEntreno >= 2
                ? " con sodio (electrolitos o una pizca de sal)"
                : ""
            out.append("Hidratación: ~\(litros) L en el día. Antes de correr ~500 ml; durante, 400–700 ml por hora\(sodio); al terminar repón ~1.5× el peso que perdiste y reparte el resto hasta la noche.")
        }
        if day.dayType == .descanso {
            out.append("Descanso ≠ restricción: la proteína se mantiene (\(String(format: "%.1f", day.prot / pesoKg)) g/kg) para reparar; solo bajan los carbohidratos.")
        }
        return out
    }

    // MARK: Checklist vegano-runner

    static func checklist(meals: [PlannedMeal]) -> [ChecklistItem] {
        let micros = Set(meals.flatMap { $0.recipe.micros })
        let hierroConC = meals.contains { $0.recipe.micros.contains("hierro") && $0.recipe.micros.contains("vitC") }
            || (micros.contains("hierro") && micros.contains("vitC"))
        return [
            ChecklistItem(
                nombre: "Hierro + vitamina C",
                cubierto: hierroConC,
                detalle: hierroConC
                    ? "Cubierto — el limón/tomate ayuda a absorber el hierro de legumbres. Café y té lejos de esas comidas."
                    : "Suma limón, tomate o naranja a la comida con legumbres."
            ),
            ChecklistItem(
                nombre: "Omega-3",
                cubierto: micros.contains("omega3"),
                detalle: micros.contains("omega3")
                    ? "Cubierto con chía, linaza, nueces o sacha inchi."
                    : "Agrega 1 cda de chía/linaza molida o un puñado de sacha inchi."
            ),
            ChecklistItem(
                nombre: "Calcio",
                cubierto: micros.contains("calcio"),
                detalle: micros.contains("calcio")
                    ? "Cubierto (soya fortificada / tofu)."
                    : "Suma leche de soya fortificada o tofu hecho con calcio."
            ),
            ChecklistItem(
                nombre: "B12 (suplemento)",
                cubierto: false,
                detalle: "No sale de la comida: suplemento diario o 2–3×/semana de alta dosis. Tómalo con el desayuno."
            ),
        ]
    }
}
