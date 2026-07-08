import Foundation

/// Persistencia simple en ~/Library/Application Support/Recarga/ (JSON por archivo).
final class Store {
    let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Recarga", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func url(_ nombre: String) -> URL { dir.appendingPathComponent(nombre) }

    func load<T: Decodable>(_ tipo: T.Type, de nombre: String) -> T? {
        guard let data = try? Data(contentsOf: url(nombre)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// `privado: true` deja el archivo con permisos 0600 (tokens de Strava).
    func save<T: Encodable>(_ valor: T, en nombre: String, privado: Bool = false) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(valor) else { return }
        let destino = url(nombre)
        try? data.write(to: destino, options: .atomic)
        if privado {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: destino.path)
        }
    }

    func delete(_ nombre: String) {
        try? FileManager.default.removeItem(at: url(nombre))
    }

    // Nombres de archivo canónicos
    static let perfil = "profile.json"
    static let plantilla = "template.json"
    static let credenciales = "strava-credentials.json"
    static let tokens = "strava-tokens.json"
    static let historial = "meal-history.json"
}

/// Historial de recetas elegidas por día, para variedad y para fijar los
/// swaps manuales: ["2026-07-08": ["almuerzo": "tacu-tacu", …]]
typealias MealHistory = [String: [String: String]]
