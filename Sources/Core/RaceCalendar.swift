import Foundation

struct Carrera: Codable, Identifiable, Equatable {
    var id: String
    var nombre: String
    /// "yyyy-MM-dd"
    var fecha: String
    var distanciaKm: Double

    var fechaDate: Date? { Fechas.claveDia.date(from: fecha) }

    /// Días de carga de carbohidratos previos, según la distancia.
    var diasCarga: Int {
        if distanciaKm >= 35 { return 3 }   // maratón
        if distanciaKm >= 20 { return 2 }   // media
        return 1                            // 10K o menos
    }

    var distanciaTexto: String {
        distanciaKm == distanciaKm.rounded()
            ? "\(Int(distanciaKm))K"
            : String(format: "%.1fK", distanciaKm)
    }
}

enum EstadoCarrera: Equatable {
    case diaDeCarrera(Carrera)
    case enCarga(Carrera, diasRestantes: Int)
    case normal
}

enum RaceCalendar {

    static func dias(de: Date, a: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents(
            [.day], from: cal.startOfDay(for: de), to: cal.startOfDay(for: a)).day ?? .max
    }

    /// ¿Qué significa esta fecha respecto a las carreras registradas?
    static func estado(para date: Date, carreras: [Carrera]) -> EstadoCarrera {
        let clave = Fechas.clave(date)
        if let c = carreras.first(where: { $0.fecha == clave }) {
            return .diaDeCarrera(c)
        }
        var mejor: (Carrera, Int)?
        for c in carreras {
            guard let f = c.fechaDate else { continue }
            let d = dias(de: date, a: f)
            if d >= 1 && d <= c.diasCarga {
                if mejor == nil || d < mejor!.1 { mejor = (c, d) }
            }
        }
        if let (c, d) = mejor { return .enCarga(c, diasRestantes: d) }
        return .normal
    }

    /// La carrera futura más próxima (incluye hoy) y a cuántos días está.
    static func proxima(desde date: Date, carreras: [Carrera]) -> (carrera: Carrera, dias: Int)? {
        var mejor: (Carrera, Int)?
        for c in carreras {
            guard let f = c.fechaDate else { continue }
            let d = dias(de: date, a: f)
            if d >= 0 && (mejor == nil || d < mejor!.1) { mejor = (c, d) }
        }
        return mejor
    }

    static func consejos(_ estado: EstadoCarrera, pesoKg: Double) -> [String] {
        switch estado {
        case .diaDeCarrera(let c):
            let g = Int(2.5 * pesoKg)
            return ["🏁 Día de carrera — \(c.nombre): desayuno 2.5–3 h antes con 2–3 g/kg de carbohidrato (~\(g) g): pan con mermelada, plátano, avena aguada. Cero fibra, cero grasa, nada que no hayas probado antes de un fondo. Al terminar: recuperación inmediata (carbo + proteína) y a celebrar."]
        case .enCarga(let c, let dias):
            let cuando = dias == 1
                ? "MAÑANA corres \(c.nombre)"
                : "faltan \(dias) días para \(c.nombre)"
            var out = ["Carga de carbohidratos: \(cuando). Hoy ~11 g/kg: arroz, papa, camote, pasta, pan, mazamorra — y menos fibra y grasa, para llegar ligero y con el glucógeno al tope."]
            if dias == 1 {
                out.append("Cena de víspera: temprana, conocida y baja en fibra. Nada nuevo, nada picante, nada experimental.")
            }
            return out
        case .normal:
            return []
        }
    }
}
