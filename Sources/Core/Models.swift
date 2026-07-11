import Foundation

// MARK: - Perfil

enum Sexo: String, Codable, CaseIterable, Identifiable {
    case masculino, femenino
    var id: String { rawValue }
    var label: String { self == .masculino ? "Masculino" : "Femenino" }
}

enum Dieta: String, Codable, CaseIterable, Identifiable {
    case omnivoro, vegetariano, vegano

    var id: String { rawValue }

    var label: String {
        switch self {
        case .omnivoro: return "Como de todo"
        case .vegetariano: return "Vegetariano"
        case .vegano: return "Vegano"
        }
    }

    /// Qué tan permisiva es la dieta (más alto = menos restricciones).
    private var rango: Int {
        switch self {
        case .vegano: return 0
        case .vegetariano: return 1
        case .omnivoro: return 2
        }
    }

    /// Un vegano solo come recetas veganas; un vegetariano, veganas y
    /// vegetarianas; un omnívoro, todas.
    func permite(_ r: Recipe) -> Bool { r.dietaMin.rango <= rango }
}

struct UserProfile: Codable {
    var pesoKg: Double
    var alturaCm: Double
    var edad: Int
    var sexo: Sexo
    var dieta: Dieta
    /// Objetivo de proteína en g/kg/día (plant-based endurance: rango alto)
    var proteinaGkg: Double
    /// Multiplicador de actividad diaria fuera del entrenamiento (trabajo de oficina ≈ 1.4)
    var factorActividad: Double

    init(pesoKg: Double, alturaCm: Double, edad: Int, sexo: Sexo,
         dieta: Dieta = .vegano, proteinaGkg: Double, factorActividad: Double) {
        self.pesoKg = pesoKg
        self.alturaCm = alturaCm
        self.edad = edad
        self.sexo = sexo
        self.dieta = dieta
        self.proteinaGkg = proteinaGkg
        self.factorActividad = factorActividad
    }

    // Decodifica perfiles guardados antes de que existiera `dieta` (default vegano).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pesoKg = try c.decode(Double.self, forKey: .pesoKg)
        alturaCm = try c.decode(Double.self, forKey: .alturaCm)
        edad = try c.decode(Int.self, forKey: .edad)
        sexo = try c.decode(Sexo.self, forKey: .sexo)
        dieta = try c.decodeIfPresent(Dieta.self, forKey: .dieta) ?? .vegano
        proteinaGkg = try c.decode(Double.self, forKey: .proteinaGkg)
        factorActividad = try c.decode(Double.self, forKey: .factorActividad)
    }
}

// MARK: - Tipos de día de entrenamiento

enum DayType: String, Codable, CaseIterable, Identifiable {
    case descanso, suave, moderado, largo, carga

    var id: String { rawValue }

    var label: String {
        switch self {
        case .descanso: return "Descanso"
        case .suave:    return "Rodaje suave"
        case .moderado: return "Series / Tempo"
        case .largo:    return "Fondo"
        case .carga:    return "Carga (pre-carrera)"
        }
    }

    /// Carbohidratos objetivo en g/kg de peso corporal (punto medio de los
    /// rangos de los position stands ISSN/ACSM para corredores de fondo).
    var carbsGkg: Double {
        switch self {
        case .descanso: return 4.0
        case .suave:    return 6.0
        case .moderado: return 7.0
        case .largo:    return 9.0
        case .carga:    return 11.0
        }
    }

    var esEntreno: Bool { self != .descanso && self != .carga }
    var esDuro: Bool { self == .largo || self == .carga }

    var icono: String {
        switch self {
        case .descanso: return "moon.zzz"
        case .suave:    return "figure.walk"
        case .moderado: return "stopwatch"
        case .largo:    return "figure.run"
        case .carga:    return "fork.knife"
        }
    }
}

/// Plantilla semanal: índice 0 = lunes … 6 = domingo.
struct TrainingTemplate: Codable {
    var dias: [DayType]

    static let porDefecto = TrainingTemplate(dias: [
        .suave, .moderado, .suave, .moderado, .suave, .descanso, .largo,
    ])

    static let nombresDias = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

    /// 0 = lunes … 6 = domingo para una fecha dada.
    static func indice(para date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = domingo
        return (weekday + 5) % 7
    }

    func tipo(para date: Date) -> DayType {
        let i = Self.indice(para: date)
        return dias.indices.contains(i) ? dias[i] : .descanso
    }
}

// MARK: - Comidas y recetas

enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case preEntreno = "pre"
    case desayuno, almuerzo, snack, cena

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preEntreno: return "Pre-entreno"
        case .desayuno:   return "Desayuno"
        case .almuerzo:   return "Almuerzo"
        case .snack:      return "Snack"
        case .cena:       return "Cena"
        }
    }

    var icono: String {
        switch self {
        case .preEntreno: return "sunrise"
        case .desayuno:   return "cup.and.saucer"
        case .almuerzo:   return "fork.knife"
        case .snack:      return "carrot"
        case .cena:       return "moon.stars"
        }
    }

    static let orden: [MealSlot] = [.preEntreno, .desayuno, .almuerzo, .snack, .cena]
}

struct Recipe: Codable, Identifiable, Hashable {
    let id: String
    let nombre: String
    let momentos: [MealSlot]
    /// Macros por 1 porción
    let kcal: Double
    let carbs: Double
    let prot: Double
    let grasa: Double
    let tiempoMin: Int
    let micros: [String]   // "hierro", "vitC", "omega3", "calcio", "zinc", "proteinaCompleta"
    let ingredientes: [String]
    let preparacion: [String]?
    let nota: String?
    /// Dieta mínima que puede comerla: "vegano" (default), "vegetariano" u "omnivoro".
    let dieta: String?

    var dietaMin: Dieta { Dieta(rawValue: dieta ?? "") ?? .vegano }
}

// MARK: - Objetivos y plan del día

struct DayTargets {
    var dayType: DayType
    var kcal: Double
    var carbs: Double
    var prot: Double
    var grasa: Double
    var trainingKcal: Double
    var carbsGkg: Double
    var horasEntreno: Double
    var aguaLitros: Double
}

struct MealTarget {
    var slot: MealSlot
    var carbs: Double
    var prot: Double
    var grasa: Double
    var kcal: Double { carbs * 4 + prot * 4 + grasa * 9 }
}

struct PlannedMeal: Identifiable {
    var slot: MealSlot
    var recipe: Recipe
    var porciones: Double
    var id: String { slot.rawValue }

    var kcal: Double { recipe.kcal * porciones }
    var carbs: Double { recipe.carbs * porciones }
    var prot: Double { recipe.prot * porciones }
    var grasa: Double { recipe.grasa * porciones }
}

struct ChecklistItem: Identifiable {
    var id: String { nombre }
    var nombre: String
    var cubierto: Bool
    var detalle: String
}

struct DayPlan {
    var fecha: Date
    var targets: DayTargets
    var tipoManana: DayType
    var meals: [PlannedMeal]
    var consejos: [String]
    var checklist: [ChecklistItem]
    var estadoCarrera: EstadoCarrera = .normal
    /// Título del entreno de Garmin de mañana, cuando es el que define el día.
    var tituloManana: String? = nil

    var totalKcal: Double { meals.reduce(0) { $0 + $1.kcal } }
    var totalCarbs: Double { meals.reduce(0) { $0 + $1.carbs } }
    var totalProt: Double { meals.reduce(0) { $0 + $1.prot } }
    var totalGrasa: Double { meals.reduce(0) { $0 + $1.grasa } }
}

// MARK: - Strava

struct StravaCredentials: Codable {
    var clientId: String
    var clientSecret: String
}

struct StravaTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: TimeInterval
    var athleteName: String?
}

struct StravaActivity: Codable, Identifiable {
    let id: Int
    let name: String
    let sportType: String
    let distance: Double        // metros
    let movingTime: Int         // segundos
    let startDateLocal: String  // "2026-07-08T05:12:34Z" (hora local de la actividad)
    let averageHeartrate: Double?
    let workoutType: Int?       // runs: 1 = carrera, 2 = fondo, 3 = series
    var calories: Double?       // solo viene en el detalle

    /// "yyyy-MM-dd" en hora local de la actividad
    var diaLocal: String { String(startDateLocal.prefix(10)) }

    var esRun: Bool { sportType.localizedCaseInsensitiveContains("run") }
    var km: Double { distance / 1000 }

    var duracionTexto: String {
        let h = movingTime / 3600, m = (movingTime % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m) min"
    }
}

// MARK: - Utilidades de fecha

enum Fechas {
    static let claveDia: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func clave(_ date: Date) -> String { claveDia.string(from: date) }

    static let tituloDia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "EEEE d 'de' MMMM"
        return f
    }()
}
