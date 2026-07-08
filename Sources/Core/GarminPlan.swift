import Foundation

/// Entrenamiento PROGRAMADO leído del calendario de Garmin Connect
/// (normalmente empujado por TrainingPeaks al reloj).
struct GarminWorkout: Codable, Equatable {
    let fecha: String        // "yyyy-MM-dd"
    let titulo: String
    let deporte: String      // "running", "strength_training", …
    let duracionSeg: Int?
    let distanciaM: Double?
    let intervalos: Bool

    var esRun: Bool { deporte.localizedCaseInsensitiveContains("run") }
}

enum GarminPlan {

    /// Un workout por fecha; si hay varios, gana el de correr y el más largo.
    static func mapa(de workouts: [GarminWorkout]) -> [String: GarminWorkout] {
        var out: [String: GarminWorkout] = [:]
        for w in workouts {
            guard let actual = out[w.fecha] else {
                out[w.fecha] = w
                continue
            }
            out[w.fecha] = mejor(actual, w)
        }
        return out
    }

    private static func mejor(_ a: GarminWorkout, _ b: GarminWorkout) -> GarminWorkout {
        if a.esRun != b.esRun { return a.esRun ? a : b }
        return (a.duracionSeg ?? 0) >= (b.duracionSeg ?? 0) ? a : b
    }

    /// Tipo de día según el entreno programado. `nil` si no es carrera a pie
    /// (una sesión de fuerza no cambia la periodización de carbohidratos).
    static func tipoDe(_ w: GarminWorkout) -> DayType? {
        guard w.esRun else { return nil }
        let km = (w.distanciaM ?? 0) / 1000
        let min = Double(w.duracionSeg ?? 0) / 60
        if km >= 18 || min >= 95 { return .largo }
        if w.intervalos { return .moderado }
        if (km > 0 && km < 9) || (min > 0 && min < 55) { return .suave }
        if km == 0 && min == 0 { return .suave }
        return .moderado
    }

    /// Gasto estimado del entreno programado (aún no corrido).
    static func kcalEstimada(_ w: GarminWorkout, pesoKg: Double) -> Double? {
        if let d = w.distanciaM, d > 0 { return d / 1000 * pesoKg }
        if let s = w.duracionSeg, s > 0 {
            // ~0.17 kcal/kg/min corriendo a ritmos de rodaje
            return Double(s) / 60 * 0.17 * pesoKg
        }
        return nil
    }
}
