import SwiftUI
import AppKit

struct CarreraProxima {
    let carrera: Carrera
    let dias: Int
}

@MainActor
final class AppState: ObservableObject {
    @Published var profile: UserProfile?
    @Published var template: TrainingTemplate = .porDefecto
    @Published var carreras: [Carrera] = []
    @Published var proximaCarrera: CarreraProxima?
    @Published var plan: DayPlan?
    @Published var actividadesHoy: [StravaActivity] = []
    @Published var stravaConectado = false
    @Published var atleta: String?
    @Published var ocupado = false
    @Published var conectando = false
    @Published var errorMsg: String?
    @Published var recetasError: String?

    @Published var garminConectado = false
    @Published var conectandoGarmin = false
    @Published var garminEstado: String?
    @Published var garminPlan: [String: GarminWorkout] = [:]
    private var ultimoFetchGarmin: Date?

    let store = Store()
    let strava = StravaClient()
    private(set) var recetas: [Recipe] = []

    /// Recetario filtrado según la dieta del usuario (vegano ⊂ vegetariano ⊂ omnívoro).
    var recetasParaDieta: [Recipe] {
        let d = profile?.dieta ?? .vegano
        return recetas.filter { d.permite($0) }
    }
    private var history: MealHistory = [:]
    private var oauthServer: OAuthCallbackServer?
    private var ultimoRefresh: Date?
    private var timerDia: Timer?

    init() {
        do {
            recetas = try RecipeStore.cargar()
        } catch {
            recetasError = error.localizedDescription
        }
        profile = store.load(UserProfile.self, de: Store.perfil)
        template = store.load(TrainingTemplate.self, de: Store.plantilla) ?? .porDefecto
        carreras = store.load([Carrera].self, de: Store.carreras) ?? []
        history = store.load(MealHistory.self, de: Store.historial) ?? [:]
        strava.creds = store.load(StravaCredentials.self, de: Store.credenciales)
        strava.tokens = store.load(StravaTokens.self, de: Store.tokens)
        strava.alActualizarTokens = { [weak self] t in
            Task { @MainActor in
                self?.store.save(t, en: Store.tokens, privado: true)
            }
        }
        stravaConectado = strava.conectado
        atleta = strava.tokens?.athleteName
        garminConectado = GarminHelper.hayTokens()
        if let cache: [GarminWorkout] = store.load([GarminWorkout].self, de: Store.garminCache) {
            garminPlan = GarminPlan.mapa(de: cache)
        }
        recomputar()
        vigilarCambioDeDia()
    }

    // MARK: Cambio de día

    /// La app puede quedarse abierta días: al pasar la medianoche (o despertar
    /// la Mac en otro día) hay que recalcular, si no se queda el plan de ayer.
    private func vigilarCambioDeDia() {
        timerDia = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.verificarCambioDeDia() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.verificarCambioDeDia() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.verificarCambioDeDia() }
        }
    }

    private func verificarCambioDeDia() {
        guard let plan, !ocupado,
              Fechas.clave(plan.fecha) != Fechas.clave(Date())
        else { return }
        actividadesHoy = []   // las de "hoy" eran de ayer
        Task { await refresh() }
    }

    // MARK: Perfil y plantilla

    func guardarPerfil(_ p: UserProfile) {
        let dietaCambio = profile != nil && profile?.dieta != p.dieta
        profile = p
        store.save(p, en: Store.perfil)
        if dietaCambio {
            // El usuario cambió de dieta: soltar las comidas fijadas de hoy
            // para que el día se regenere completo con el recetario nuevo.
            history[Fechas.clave(Date())] = nil
            store.save(history, en: Store.historial)
        }
        recomputar()
    }

    func guardarPlantilla(_ t: TrainingTemplate) {
        template = t
        store.save(t, en: Store.plantilla)
        recomputar()
    }

    // MARK: Carreras

    func agregarCarrera(nombre: String, fecha: Date, distanciaKm: Double) {
        let c = Carrera(
            id: UUID().uuidString,
            nombre: nombre.trimmingCharacters(in: .whitespacesAndNewlines),
            fecha: Fechas.clave(fecha),
            distanciaKm: distanciaKm)
        carreras.append(c)
        store.save(carreras, en: Store.carreras)
        recomputar()
    }

    func eliminarCarrera(_ c: Carrera) {
        carreras.removeAll { $0.id == c.id }
        store.save(carreras, en: Store.carreras)
        recomputar()
    }

    // MARK: Plan del día

    func recomputar() {
        guard let p = profile, !recetas.isEmpty else {
            plan = nil
            return
        }
        let hoy = Date()
        let manana = Calendar.current.date(byAdding: .day, value: 1, to: hoy) ?? hoy

        let estadoHoy = RaceCalendar.estado(para: hoy, carreras: carreras)
        let estadoManana = RaceCalendar.estado(para: manana, carreras: carreras)
        proximaCarrera = RaceCalendar.proxima(desde: hoy, carreras: carreras)
            .map { CarreraProxima(carrera: $0.carrera, dias: $0.dias) }

        // Prioridad: carrera > entreno programado en Garmin > plantilla.
        let garminHoy = garminPlan[Fechas.clave(hoy)]
        let garminManana = garminPlan[Fechas.clave(manana)]
        let baseHoy = garminHoy.flatMap { GarminPlan.tipoDe($0) } ?? template.tipo(para: hoy)
        let baseManana = garminManana.flatMap { GarminPlan.tipoDe($0) } ?? template.tipo(para: manana)
        let plantillaHoy = RaceCalendar.tipoEfectivo(plantilla: baseHoy, estado: estadoHoy)
        let tipoManana = RaceCalendar.tipoEfectivo(plantilla: baseManana, estado: estadoManana)

        let (clasificado, esReal) = NutritionEngine.clasificarDia(
            actividades: actividadesHoy, plantilla: plantillaHoy)
        var tipo = clasificado
        // Un trote corto de activación no debe romper la carga pre-carrera,
        // y el día de carrera es "largo" aunque la actividad aún no se suba.
        if case .enCarga = estadoHoy { tipo = .carga }
        if case .diaDeCarrera = estadoHoy, actividadesHoy.isEmpty { tipo = .largo }

        let kcalEntreno: Double
        let horasEntreno: Double
        if !actividadesHoy.isEmpty {
            kcalEntreno = NutritionEngine.trainingKcal(actividades: actividadesHoy, pesoKg: p.pesoKg)
            horasEntreno = Double(actividadesHoy.reduce(0) { $0 + $1.movingTime }) / 3600
        } else if case .diaDeCarrera(let c) = estadoHoy {
            kcalEntreno = c.distanciaKm * p.pesoKg
            horasEntreno = c.distanciaKm / 10
        } else if tipo == .descanso || tipo == .carga {
            kcalEntreno = 0
            horasEntreno = 0
        } else if let w = garminHoy, GarminPlan.tipoDe(w) != nil {
            kcalEntreno = GarminPlan.kcalEstimada(w, pesoKg: p.pesoKg)
                ?? NutritionEngine.kcalEstimada(tipo: tipo, pesoKg: p.pesoKg)
            horasEntreno = w.duracionSeg.map { Double($0) / 3600 }
                ?? NutritionEngine.horasEstimadas(tipo: tipo)
        } else {
            kcalEntreno = NutritionEngine.kcalEstimada(tipo: tipo, pesoKg: p.pesoKg)
            horasEntreno = NutritionEngine.horasEstimadas(tipo: tipo)
        }

        let targets = NutritionEngine.dayTargets(
            profile: p, dayType: tipo, trainingKcal: kcalEntreno, horasEntreno: horasEntreno)
        let mealTargets = NutritionEngine.mealTargets(day: targets, manana: tipoManana)

        let claveHoy = Fechas.clave(hoy)
        let planner = MealPlanner(recetas: recetasParaDieta, history: history)
        let meals = planner.plan(fecha: hoy, targets: mealTargets, fijadas: history[claveHoy] ?? [:])

        var deHoy: [String: String] = [:]
        for m in meals { deHoy[m.slot.rawValue] = m.recipe.id }
        history[claveHoy] = deHoy
        store.save(history, en: Store.historial)

        var consejos = RaceCalendar.consejos(estadoHoy, pesoKg: p.pesoKg)
        if actividadesHoy.isEmpty && plantillaHoy.esEntreno && tipo == .descanso {
            let quePlan = garminHoy.flatMap { GarminPlan.tipoDe($0) != nil ? "«\($0.titulo)»" : nil }
                ?? "«\(plantillaHoy.label)»"
            consejos.insert(
                "Hoy tocaba \(quePlan), pero no veo la actividad en Strava y ya pasó la mañana — dejé el día en descanso para no alimentar un entreno que no fue. ¿Sí corriste? Toca ↻ cuando aparezca en Strava y recalculo.",
                at: 0)
        }
        consejos += NutritionEngine.consejos(
            day: targets, manana: tipoManana, huboActividad: esReal, pesoKg: p.pesoKg)
        let tituloManana = garminManana.flatMap { GarminPlan.tipoDe($0) != nil ? $0.titulo : nil }
        plan = DayPlan(
            fecha: hoy, targets: targets, tipoManana: tipoManana, meals: meals,
            consejos: consejos,
            checklist: NutritionEngine.checklist(meals: meals, dieta: p.dieta),
            estadoCarrera: estadoHoy, tituloManana: tituloManana)
    }

    /// Proyecta los próximos días (desde mañana) para la vista de semana y compras.
    func proyectarSemana(dias: Int = 7) -> [DiaProyectado] {
        guard let p = profile, !recetas.isEmpty else { return [] }
        let inicio = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return WeekPlanner.proyectar(
            desde: inicio, dias: dias, profile: p, template: template,
            carreras: carreras, recetas: recetasParaDieta, historia: history, garmin: garminPlan)
    }

    /// Cambia la receta de una comida por otra alternativa.
    func cambiarComida(_ slot: MealSlot) {
        guard let plan else { return }
        let mealTargets = NutritionEngine.mealTargets(day: plan.targets, manana: plan.tipoManana)
        guard let target = mealTargets.first(where: { $0.slot == slot }),
              let actual = plan.meals.first(where: { $0.slot == slot })?.recipe.id
        else { return }
        let otras = Set(plan.meals.filter { $0.slot != slot }.map(\.recipe.id))
        let planner = MealPlanner(recetas: recetasParaDieta, history: history)
        guard let nueva = planner.alternativa(
            fecha: plan.fecha, target: target, actual: actual, otrasDeHoy: otras)
        else { return }
        history[Fechas.clave(plan.fecha)]?[slot.rawValue] = nueva.recipe.id
        store.save(history, en: Store.historial)
        recomputar()
    }

    // MARK: Garmin (entrenos programados)

    func conectarGarmin(email: String, password: String, mfa: String?) async {
        conectandoGarmin = true
        defer { conectandoGarmin = false }
        garminEstado = nil
        do {
            if !GarminHelper.venvListo() {
                garminEstado = "Instalando dependencias (una sola vez, ~30 s)…"
                try await GarminHelper.crearVenv()
            }
            garminEstado = "Conectando con Garmin…"
            let nombre = try await GarminHelper.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                mfa: mfa?.isEmpty == false ? mfa : nil)
            garminConectado = true
            garminEstado = "Conectado\(nombre.map { " como \($0)" } ?? "")"
            await fetchGarmin(forzar: true)
        } catch {
            garminEstado = error.localizedDescription
        }
    }

    func fetchGarmin(forzar: Bool = false) async {
        guard garminConectado else { return }
        if !forzar, let u = ultimoFetchGarmin, Date().timeIntervalSince(u) < 15 * 60 { return }
        do {
            let ws = try await GarminHelper.fetch(dias: 14)
            garminPlan = GarminPlan.mapa(de: ws)
            store.save(ws, en: Store.garminCache)
            ultimoFetchGarmin = Date()
            recomputar()
        } catch {
            garminEstado = error.localizedDescription
        }
    }

    func desconectarGarmin() {
        GarminHelper.desconectar()
        store.delete(Store.garminCache)
        garminConectado = false
        garminPlan = [:]
        garminEstado = nil
        recomputar()
    }

    // MARK: Strava

    func refresh() async {
        await fetchGarmin()
        guard strava.conectado else {
            recomputar()
            return
        }
        ocupado = true
        defer { ocupado = false }
        do {
            let acts = try await strava.actividadesRecientes(dias: 8)
            let hoy = Fechas.clave(Date())
            var deHoy = acts.filter { $0.diaLocal == hoy }
            for i in deHoy.indices.prefix(3) where deHoy[i].calories == nil {
                deHoy[i].calories = try? await strava.caloriasDeActividad(id: deHoy[i].id)
            }
            actividadesHoy = deHoy
            errorMsg = nil
            ultimoRefresh = Date()
            recomputar()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    /// Refresh al volver a la app, como mucho cada 15 minutos.
    func refreshSiToca() async {
        if let u = ultimoRefresh, Date().timeIntervalSince(u) < 15 * 60 { return }
        await refresh()
    }

    func conectarStrava(clientId: String, clientSecret: String) async {
        let creds = StravaCredentials(
            clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines))
        strava.creds = creds
        store.save(creds, en: Store.credenciales, privado: true)

        conectando = true
        defer { conectando = false }
        errorMsg = nil

        let server = OAuthCallbackServer()
        oauthServer?.detener()
        oauthServer = server

        do {
            let code: String = try await withCheckedThrowingContinuation { cont in
                final class Once { var hecho = false }
                let once = Once()
                let resume: (Result<String, Error>) -> Void = { result in
                    guard !once.hecho else { return }
                    once.hecho = true
                    cont.resume(with: result)
                }
                do {
                    try server.iniciar { resume($0) }
                } catch {
                    resume(.failure(error))
                    return
                }
                guard let url = self.strava.authorizeURL() else {
                    resume(.failure(StravaError.sinCredenciales))
                    return
                }
                NSWorkspace.shared.open(url)
                // Timeout de 3 minutos por si nunca vuelve el callback.
                DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
                    resume(.failure(OAuthCallbackServer.CallbackError.sinCodigo))
                }
            }
            server.detener()
            oauthServer = nil
            try await strava.canjearCodigo(code)
            stravaConectado = true
            atleta = strava.tokens?.athleteName
            await refresh()
        } catch {
            server.detener()
            oauthServer = nil
            errorMsg = error.localizedDescription
        }
    }

    func desconectarStrava() {
        store.delete(Store.tokens)
        strava.tokens = nil
        stravaConectado = false
        atleta = nil
        actividadesHoy = []
        recomputar()
    }
}
