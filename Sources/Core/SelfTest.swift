import Foundation

/// `Recarga --selftest`: valida recetario + motor + planificador sin UI.
func runSelfTest() -> Int32 {
    var fallas: [String] = []
    func check(_ cond: Bool, _ msg: String) { if !cond { fallas.append(msg) } }

    // 1. Recetario
    let recetas: [Recipe]
    do {
        recetas = try RecipeStore.cargar()
    } catch {
        print("SELFTEST FALLÓ: \(error.localizedDescription)")
        return 1
    }
    check(recetas.count >= 45, "recetario muy chico: \(recetas.count)")
    for r in recetas {
        let kcalCalc = r.carbs * 4 + r.prot * 4 + r.grasa * 9
        check(abs(kcalCalc - r.kcal) <= r.kcal * 0.18,
              "\(r.id): macros no cuadran (\(Int(kcalCalc)) vs \(Int(r.kcal)) kcal)")
        check(!r.momentos.isEmpty, "\(r.id): sin momentos")
        check(r.kcal > 0 && r.carbs >= 0 && r.prot >= 0 && r.grasa >= 0, "\(r.id): macros inválidos")
    }
    for slot in MealSlot.orden {
        let n = recetas.filter { $0.momentos.contains(slot) }.count
        check(n >= 5, "pocas recetas para \(slot.label): \(n)")
    }

    // 2. Motor con un perfil de ejemplo
    let perfil = UserProfile(
        pesoKg: 66, alturaCm: 172, edad: 32, sexo: .masculino,
        proteinaGkg: 1.8, factorActividad: 1.4)

    let bmr = NutritionEngine.bmr(perfil)
    check(bmr > 1400 && bmr < 1800, "BMR fuera de rango: \(bmr)")

    let fondo = StravaActivity(
        id: 1, name: "Fondo dominical", sportType: "Run", distance: 28000,
        movingTime: 8400, startDateLocal: "2026-07-05T05:10:00Z",
        averageHeartrate: 152, workoutType: 2, calories: nil)

    let (tipo, esReal) = NutritionEngine.clasificarDia(actividades: [fondo], plantilla: .suave)
    check(tipo == .largo && esReal, "clasificación de fondo falló: \(tipo)")

    let kcalEntreno = NutritionEngine.trainingKcal(actividades: [fondo], pesoKg: perfil.pesoKg)
    check(abs(kcalEntreno - 28 * 66) < 1, "estimación kcal de carrera falló: \(kcalEntreno)")

    let targets = NutritionEngine.dayTargets(profile: perfil, dayType: .largo, trainingKcal: kcalEntreno)
    check(targets.carbs == 9 * 66, "carbos de día largo: \(targets.carbs)")
    check(targets.prot == 1.8 * 66, "proteína: \(targets.prot)")
    check(targets.kcal > 3400 && targets.kcal < 4400, "kcal día fondo fuera de rango: \(targets.kcal)")
    check(targets.grasa >= 0.8 * 66, "grasa por debajo del mínimo: \(targets.grasa)")

    // 3. Reparto por comidas: la cena sube cuando mañana toca fondo
    let mealsNormal = NutritionEngine.mealTargets(day: targets, manana: .suave)
    let mealsPreFondo = NutritionEngine.mealTargets(day: targets, manana: .largo)
    check(mealsNormal.count == 5, "faltan slots en día de entreno: \(mealsNormal.count)")
    let cenaNormal = mealsNormal.first { $0.slot == .cena }!.carbs
    let cenaPreFondo = mealsPreFondo.first { $0.slot == .cena }!.carbs
    check(cenaPreFondo > cenaNormal, "la cena no sube antes de un fondo")

    let descanso = NutritionEngine.dayTargets(profile: perfil, dayType: .descanso, trainingKcal: 0)
    let mealsDescanso = NutritionEngine.mealTargets(day: descanso, manana: .suave)
    check(mealsDescanso.count == 4, "día de descanso no debería tener pre-entreno")
    for m in mealsNormal {
        let suma = mealsNormal.reduce(0.0) { $0 + $1.carbs }
        check(abs(suma - targets.carbs) < 1, "reparto de carbos no suma: \(suma) vs \(targets.carbs)")
        _ = m
    }

    // 4. Planificador: 3 días seguidos sin repetir receta en el mismo slot
    var historia: MealHistory = [:]
    let cal = Calendar.current
    let base = cal.date(from: DateComponents(year: 2026, month: 7, day: 6))!
    var planesPorDia: [[PlannedMeal]] = []
    for dia in 0..<3 {
        let fecha = cal.date(byAdding: .day, value: dia, to: base)!
        let planner = MealPlanner(recetas: recetas, history: historia)
        let plan = planner.plan(fecha: fecha, targets: mealsNormal, fijadas: [:])
        check(plan.count == mealsNormal.count, "día \(dia): faltan comidas (\(plan.count))")
        var delDia: [String: String] = [:]
        for m in plan { delDia[m.slot.rawValue] = m.recipe.id }
        historia[Fechas.clave(fecha)] = delDia
        planesPorDia.append(plan)
    }
    for slot in MealSlot.orden {
        let ids = planesPorDia.compactMap { plan in plan.first { $0.slot == slot }?.recipe.id }
        if ids.count == 3 {
            check(ids[0] != ids[1] && ids[1] != ids[2],
                  "\(slot.label) repite receta en días consecutivos: \(ids)")
        }
    }

    // 5. Cobertura del plan vs objetivos (±20% en carbos y proteína del día)
    let plan = planesPorDia[0]
    let totC = plan.reduce(0.0) { $0 + $1.carbs }
    let totP = plan.reduce(0.0) { $0 + $1.prot }
    check(abs(totC - targets.carbs) / targets.carbs < 0.20,
          "carbos del plan lejos del objetivo: \(Int(totC)) vs \(Int(targets.carbs))")
    check(abs(totP - targets.prot) / targets.prot < 0.25,
          "proteína del plan lejos del objetivo: \(Int(totP)) vs \(Int(targets.prot))")

    // 6. Checklist
    let checklist = NutritionEngine.checklist(meals: plan)
    check(checklist.count == 4, "checklist incompleto")

    // 7. Calendario de carreras
    let maraton = Carrera(id: "m", nombre: "Maratón de Lima", fecha: "2026-10-18", distanciaKm: 42.2)
    let diezK = Carrera(id: "d", nombre: "10K del trabajo", fecha: "2026-08-09", distanciaKm: 10)
    let cs = [maraton, diezK]
    func f(_ s: String) -> Date { Fechas.claveDia.date(from: s)! }
    check(RaceCalendar.estado(para: f("2026-10-18"), carreras: cs) == .diaDeCarrera(maraton),
          "día de carrera no detectado")
    check(RaceCalendar.estado(para: f("2026-10-15"), carreras: cs) == .enCarga(maraton, diasRestantes: 3),
          "la carga de maratón debería empezar 3 días antes")
    check(RaceCalendar.estado(para: f("2026-10-14"), carreras: cs) == .normal,
          "la carga de maratón empezó demasiado pronto")
    check(RaceCalendar.estado(para: f("2026-08-08"), carreras: cs) == .enCarga(diezK, diasRestantes: 1),
          "la carga de 10K debería ser solo la víspera")
    check(RaceCalendar.estado(para: f("2026-08-07"), carreras: cs) == .normal,
          "la carga de 10K empezó demasiado pronto")
    check(!RaceCalendar.consejos(.diaDeCarrera(maraton), pesoKg: 70).isEmpty,
          "sin consejos de día de carrera")
    check(RaceCalendar.consejos(.enCarga(maraton, diasRestantes: 1), pesoKg: 70).count == 2,
          "la víspera debería traer consejo extra de cena")
    if let prox = RaceCalendar.proxima(desde: f("2026-09-01"), carreras: cs) {
        check(prox.carrera.id == "m" && prox.dias == 47,
              "próxima carrera mal calculada: \(prox.carrera.id) a \(prox.dias) días")
    } else {
        fallas.append("proxima() no encontró la carrera futura")
    }

    // Reporte
    print("── Recarga selftest ──")
    print("Recetario: \(recetas.count) recetas ✓")
    print(String(format: "Perfil demo: 66 kg · BMR %.0f kcal", bmr))
    print(String(format: "Día FONDO 28 km → %.0f kcal · C %.0f g (9 g/kg) · P %.0f g · G %.0f g",
                 targets.kcal, targets.carbs, targets.prot, targets.grasa))
    print("\nPlan de ejemplo:")
    for m in plan {
        print(String(format: "  %@ %@ — %@ (×%.2g) · %.0f kcal · C %.0f · P %.0f · G %.0f",
                     "•", m.slot.label, m.recipe.nombre, m.porciones, m.kcal, m.carbs, m.prot, m.grasa))
    }
    print(String(format: "  TOTAL: %.0f kcal · C %.0f · P %.0f", plan.reduce(0) { $0 + $1.kcal }, totC, totP))
    print("Calendario de carreras: carga 3/2/1 días según distancia ✓")

    if fallas.isEmpty {
        print("\nSELFTEST OK ✓")
        return 0
    } else {
        print("\nSELFTEST FALLÓ (\(fallas.count)):")
        fallas.forEach { print("  ✗ \($0)") }
        return 1
    }
}
