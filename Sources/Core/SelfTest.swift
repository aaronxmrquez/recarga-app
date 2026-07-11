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
    check(recetas.count >= 75, "recetario muy chico: \(recetas.count)")

    // Dietas: vegano ⊂ vegetariano ⊂ omnívoro
    let veganas = recetas.filter { Dieta.vegano.permite($0) }
    let vegetarianas = recetas.filter { Dieta.vegetariano.permite($0) }
    let todas = recetas.filter { Dieta.omnivoro.permite($0) }
    check(veganas.allSatisfy { $0.dietaMin == .vegano }, "el filtro vegano dejó pasar recetas no veganas")
    check(recetas.contains { $0.dietaMin == .vegetariano }, "no hay recetas vegetarianas")
    check(recetas.contains { $0.dietaMin == .omnivoro }, "no hay recetas omnívoras")
    check(veganas.count < vegetarianas.count && vegetarianas.count < todas.count,
          "la jerarquía de dietas no filtra: \(veganas.count)/\(vegetarianas.count)/\(todas.count)")
    check(todas.count == recetas.count, "el omnívoro debería ver todo el recetario")
    for r in recetas {
        let kcalCalc = r.carbs * 4 + r.prot * 4 + r.grasa * 9
        check(abs(kcalCalc - r.kcal) <= r.kcal * 0.18,
              "\(r.id): macros no cuadran (\(Int(kcalCalc)) vs \(Int(r.kcal)) kcal)")
        check(!r.momentos.isEmpty, "\(r.id): sin momentos")
        check(r.kcal > 0 && r.carbs >= 0 && r.prot >= 0 && r.grasa >= 0, "\(r.id): macros inválidos")
        check((r.preparacion?.count ?? 0) >= 2, "\(r.id): sin preparación paso a paso")
    }
    for slot in MealSlot.orden {
        let n = veganas.filter { $0.momentos.contains(slot) }.count
        check(n >= 5, "pocas recetas veganas para \(slot.label): \(n)")
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

    let targets = NutritionEngine.dayTargets(
        profile: perfil, dayType: .largo, trainingKcal: kcalEntreno, horasEntreno: 8400.0 / 3600)
    check(targets.carbs == 9 * 66, "carbos de día largo: \(targets.carbs)")
    check(targets.prot == 1.8 * 66, "proteína: \(targets.prot)")
    check(targets.kcal > 3400 && targets.kcal < 4400, "kcal día fondo fuera de rango: \(targets.kcal)")
    check(targets.grasa >= 0.8 * 66, "grasa por debajo del mínimo: \(targets.grasa)")
    check(targets.aguaLitros > 4.4 && targets.aguaLitros < 5.4,
          "agua de día fondo fuera de rango: \(targets.aguaLitros) L")
    let consejosFondo = NutritionEngine.consejos(
        day: targets, manana: .suave, huboActividad: true, pesoKg: 66)
    check(consejosFondo.contains { $0.contains("Hidratación") },
          "falta el consejo de hidratación en día de fondo")

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
    check(abs(descanso.aguaLitros - 2.3) < 0.15,
          "agua de descanso fuera de rango: \(descanso.aguaLitros) L")
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
        let planner = MealPlanner(recetas: veganas, history: historia)
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

    // 6. Checklist según dieta
    let checklist = NutritionEngine.checklist(meals: plan, dieta: .vegano)
    check(checklist.count == 4, "checklist vegano incompleto")
    check(NutritionEngine.checklist(meals: plan, dieta: .omnivoro).count == 3,
          "el omnívoro no debería tener ítem de B12")
    check(NutritionEngine.checklist(meals: plan, dieta: .vegetariano)
            .contains { $0.nombre.hasPrefix("B12") },
          "el vegetariano debería tener aviso de B12")
    // El plan vegano nunca incluye recetas no veganas
    check(plan.allSatisfy { $0.recipe.dietaMin == .vegano },
          "el plan vegano incluyó una receta no vegana")

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

    // 8. Proyección semanal (determinista) + lista de compras
    let semana = WeekPlanner.proyectar(
        desde: f("2026-07-09"), dias: 7, profile: perfil,
        template: .porDefecto, carreras: [], recetas: veganas, historia: [:])
    check(semana.count == 7, "proyección incompleta: \(semana.count) días")
    check(semana.allSatisfy { $0.meals.count >= 4 }, "días proyectados con comidas incompletas")
    let semana2 = WeekPlanner.proyectar(
        desde: f("2026-07-09"), dias: 7, profile: perfil,
        template: .porDefecto, carreras: [], recetas: veganas, historia: [:])
    let ids1 = semana.flatMap { $0.meals.map(\.recipe.id) }
    let ids2 = semana2.flatMap { $0.meals.map(\.recipe.id) }
    check(ids1 == ids2, "la proyección no es determinista")

    let lista = ShoppingList.generar(dias: semana)
    let totalItems = lista.reduce(0) { $0 + $1.items.count }
    check(!lista.isEmpty, "lista de compras vacía")
    check(totalItems >= 15, "lista de compras sospechosamente corta: \(totalItems) ítems")
    check(lista.flatMap(\.items).contains { $0.gramos > 0 },
          "ningún ítem acumuló gramos — el parser de cantidades falló")
    let sinCategoria = lista.first { $0.categoria == "Otros" }?.items.count ?? 0
    check(sinCategoria <= totalItems / 3,
          "demasiados ingredientes sin categoría (\(sinCategoria) de \(totalItems))")

    // Con carrera dentro de la semana: la carga aparece en los días previos
    let semCarrera = WeekPlanner.proyectar(
        desde: f("2026-07-09"), dias: 7, profile: perfil, template: .porDefecto,
        carreras: [Carrera(id: "x", nombre: "Test 42K", fecha: "2026-07-15", distanciaKm: 42.2)],
        recetas: veganas, historia: [:])
    check(semCarrera[3].tipo == .carga && semCarrera[5].tipo == .carga,
          "la proyección no aplica la carga pre-carrera")
    check(semCarrera[6].tipo == .largo, "el día de carrera proyectado no es largo")

    // 9. Plan de Garmin: mapeo de entrenos programados a tipo de día
    let wLargo = GarminWorkout(fecha: "2026-07-10", titulo: "Long Run 26K", deporte: "running",
                               duracionSeg: 7800, distanciaM: 26000, intervalos: false)
    let wSeries = GarminWorkout(fecha: "2026-07-11", titulo: "8x800", deporte: "running",
                                duracionSeg: 3600, distanciaM: 12000, intervalos: true)
    let wSuave = GarminWorkout(fecha: "2026-07-12", titulo: "Easy", deporte: "running",
                               duracionSeg: 2700, distanciaM: 8000, intervalos: false)
    let wFuerza = GarminWorkout(fecha: "2026-07-13", titulo: "Gym", deporte: "strength_training",
                                duracionSeg: 2400, distanciaM: nil, intervalos: false)
    check(GarminPlan.tipoDe(wLargo) == .largo, "workout largo de Garmin mal clasificado")
    check(GarminPlan.tipoDe(wSeries) == .moderado, "workout de series de Garmin mal clasificado")
    check(GarminPlan.tipoDe(wSuave) == .suave, "workout suave de Garmin mal clasificado")
    check(GarminPlan.tipoDe(wFuerza) == nil, "la fuerza no debería cambiar el tipo de día")
    check(abs((GarminPlan.kcalEstimada(wLargo, pesoKg: 66) ?? 0) - 26 * 66) < 1,
          "kcal estimada del workout de Garmin falló")
    let mapa = GarminPlan.mapa(de: [wFuerza, GarminWorkout(
        fecha: "2026-07-13", titulo: "Rodaje", deporte: "running",
        duracionSeg: 3000, distanciaM: 10000, intervalos: false)])
    check(mapa["2026-07-13"]?.esRun == true, "en día doble debería ganar el entreno de correr")

    // La proyección respeta el plan de Garmin sobre la plantilla
    let semGarmin = WeekPlanner.proyectar(
        desde: f("2026-07-09"), dias: 7, profile: perfil, template: .porDefecto,
        carreras: [], recetas: veganas, historia: [:],
        garmin: ["2026-07-10": wLargo])
    check(semGarmin[1].tipo == .largo, "la proyección no usa el entreno programado de Garmin")
    check(semGarmin[1].notaEntreno == "Long Run 26K", "falta el título del entreno de Garmin")
    check(semGarmin[0].tipo == .moderado, "el día sin plan de Garmin debería usar la plantilla")

    // Reporte
    print("── Recarga selftest ──")
    print("Recetario: \(recetas.count) recetas ✓")
    print(String(format: "Perfil demo: 66 kg · BMR %.0f kcal", bmr))
    print(String(format: "Día FONDO 28 km → %.0f kcal · C %.0f g (9 g/kg) · P %.0f g · G %.0f g · Agua %.1f L",
                 targets.kcal, targets.carbs, targets.prot, targets.grasa, targets.aguaLitros))
    print("\nPlan de ejemplo:")
    for m in plan {
        print(String(format: "  %@ %@ — %@ (×%.2g) · %.0f kcal · C %.0f · P %.0f · G %.0f",
                     "•", m.slot.label, m.recipe.nombre, m.porciones, m.kcal, m.carbs, m.prot, m.grasa))
    }
    print(String(format: "  TOTAL: %.0f kcal · C %.0f · P %.0f", plan.reduce(0) { $0 + $1.kcal }, totC, totP))
    print("Calendario de carreras: carga 3/2/1 días según distancia ✓")
    print("Semana proyectada: 7 días · lista de compras: \(totalItems) ítems en \(lista.count) categorías ✓")
    print("\nLista de compras de la semana proyectada:")
    for (cat, items) in lista {
        print("  [\(cat)]")
        for it in items { print("    • \(it.nombre) — \(it.detalle)") }
    }

    if fallas.isEmpty {
        print("\nSELFTEST OK ✓")
        return 0
    } else {
        print("\nSELFTEST FALLÓ (\(fallas.count)):")
        fallas.forEach { print("  ✗ \($0)") }
        return 1
    }
}
