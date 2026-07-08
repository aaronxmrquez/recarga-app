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

    let store = Store()
    let strava = StravaClient()
    private(set) var recetas: [Recipe] = []
    private var history: MealHistory = [:]
    private var oauthServer: OAuthCallbackServer?
    private var ultimoRefresh: Date?

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
        recomputar()
    }

    // MARK: Perfil y plantilla

    func guardarPerfil(_ p: UserProfile) {
        profile = p
        store.save(p, en: Store.perfil)
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

    /// Si aún no hay actividad subida (p. ej. son las 4 am), estima el gasto
    /// de la sesión planificada para que los objetivos del día ya la incluyan.
    private func kcalEstimadaPlantilla(_ tipo: DayType, peso: Double) -> Double {
        let km: Double
        switch tipo {
        case .suave: km = 10
        case .moderado: km = 14
        case .largo: km = 30
        default: km = 0
        }
        return km * peso
    }

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

        var plantillaHoy = template.tipo(para: hoy)
        if case .diaDeCarrera = estadoHoy { plantillaHoy = .largo }
        if case .enCarga = estadoHoy { plantillaHoy = .carga }
        var tipoManana = template.tipo(para: manana)
        if case .diaDeCarrera = estadoManana { tipoManana = .largo }
        if case .enCarga = estadoManana { tipoManana = .carga }

        let (clasificado, esReal) = NutritionEngine.clasificarDia(
            actividades: actividadesHoy, plantilla: plantillaHoy)
        var tipo = clasificado
        // Un trote corto de activación no debe romper la carga pre-carrera,
        // y el día de carrera es "largo" aunque la actividad aún no se suba.
        if case .enCarga = estadoHoy { tipo = .carga }
        if case .diaDeCarrera = estadoHoy, actividadesHoy.isEmpty { tipo = .largo }

        let kcalEntreno: Double
        if actividadesHoy.isEmpty {
            if case .diaDeCarrera(let c) = estadoHoy {
                kcalEntreno = c.distanciaKm * p.pesoKg
            } else {
                kcalEntreno = kcalEstimadaPlantilla(tipo, peso: p.pesoKg)
            }
        } else {
            kcalEntreno = NutritionEngine.trainingKcal(actividades: actividadesHoy, pesoKg: p.pesoKg)
        }

        let targets = NutritionEngine.dayTargets(profile: p, dayType: tipo, trainingKcal: kcalEntreno)
        let mealTargets = NutritionEngine.mealTargets(day: targets, manana: tipoManana)

        let claveHoy = Fechas.clave(hoy)
        let planner = MealPlanner(recetas: recetas, history: history)
        let meals = planner.plan(fecha: hoy, targets: mealTargets, fijadas: history[claveHoy] ?? [:])

        var deHoy: [String: String] = [:]
        for m in meals { deHoy[m.slot.rawValue] = m.recipe.id }
        history[claveHoy] = deHoy
        store.save(history, en: Store.historial)

        var consejos = RaceCalendar.consejos(estadoHoy, pesoKg: p.pesoKg)
        consejos += NutritionEngine.consejos(
            day: targets, manana: tipoManana, huboActividad: esReal, pesoKg: p.pesoKg)
        plan = DayPlan(
            fecha: hoy, targets: targets, tipoManana: tipoManana, meals: meals,
            consejos: consejos, checklist: NutritionEngine.checklist(meals: meals),
            estadoCarrera: estadoHoy)
    }

    /// Cambia la receta de una comida por otra alternativa.
    func cambiarComida(_ slot: MealSlot) {
        guard let plan else { return }
        let mealTargets = NutritionEngine.mealTargets(day: plan.targets, manana: plan.tipoManana)
        guard let target = mealTargets.first(where: { $0.slot == slot }),
              let actual = plan.meals.first(where: { $0.slot == slot })?.recipe.id
        else { return }
        let otras = Set(plan.meals.filter { $0.slot != slot }.map(\.recipe.id))
        let planner = MealPlanner(recetas: recetas, history: history)
        guard let nueva = planner.alternativa(
            fecha: plan.fecha, target: target, actual: actual, otrasDeHoy: otras)
        else { return }
        history[Fechas.clave(plan.fecha)]?[slot.rawValue] = nueva.recipe.id
        store.save(history, en: Store.historial)
        recomputar()
    }

    // MARK: Strava

    func refresh() async {
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
