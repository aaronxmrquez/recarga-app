import Foundation

enum RecipeStoreError: Error, LocalizedError {
    case noEncontrado
    var errorDescription: String? { "No encontré recipes.json (busqué en el bundle y en Resources/)." }
}

enum RecipeStore {

    /// Carga el recetario buscando en: bundle de la app → junto al ejecutable
    /// → Resources/ relativo al directorio actual (para --selftest desde el repo).
    static func cargar() throws -> [Recipe] {
        for url in candidatos() {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let recetas = try JSONDecoder().decode([Recipe].self, from: data)
                return recetas
            }
        }
        throw RecipeStoreError.noEncontrado
    }

    private static func candidatos() -> [URL] {
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: "recipes", withExtension: "json") {
            urls.append(u)
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath().deletingLastPathComponent()
        urls.append(exeDir.appendingPathComponent("../Resources/recipes.json").standardizedFileURL)
        urls.append(exeDir.appendingPathComponent("recipes.json"))
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(cwd.appendingPathComponent("Resources/recipes.json"))
        urls.append(URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Developer/Recarga/Resources/recipes.json"))
        return urls
    }
}
