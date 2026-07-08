import Foundation

enum GarminError: Error, LocalizedError {
    case sinScript
    case mfaRequerida(String)
    case helperFallo(String)

    var errorDescription: String? {
        switch self {
        case .sinScript:
            return "No encontré garmin_helper.py (ni en el bundle ni en Support/)."
        case .mfaRequerida(let m):
            return "Garmin pidió un código MFA — ingrésalo en el campo Código MFA y reintenta. (\(m))"
        case .helperFallo(let m):
            return m
        }
    }
}

/// Corre el helper de Python (garminconnect/garth) como proceso hijo.
/// El venv y los tokens viven en ~/Library/Application Support/Recarga/.
enum GarminHelper {

    static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recarga", isDirectory: true)
    }
    static var venvPython: URL { appSupport.appendingPathComponent("garmin-venv/bin/python3") }
    static var tokensDir: URL { appSupport.appendingPathComponent("garmin-tokens", isDirectory: true) }

    static func hayTokens() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: tokensDir.appendingPathComponent("oauth2_token.json").path)
            || fm.fileExists(atPath: tokensDir.appendingPathComponent("oauth1_token.json").path)
    }

    static func venvListo() -> Bool {
        FileManager.default.isExecutableFile(atPath: venvPython.path)
    }

    static func scriptURL() -> URL? {
        if let u = Bundle.main.url(forResource: "garmin_helper", withExtension: "py") {
            return u
        }
        let repo = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Developer/Recarga/Support/garmin_helper.py")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    /// Crea el venv e instala garminconnect (una sola vez, ~30 s).
    static func crearVenv() async throws {
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        _ = try await correr("/usr/bin/python3",
                             ["-m", "venv", appSupport.appendingPathComponent("garmin-venv").path])
        _ = try await correr(venvPython.path,
                             ["-m", "pip", "install", "--quiet", "garminconnect"])
    }

    /// Devuelve el nombre del atleta si Garmin lo entrega.
    static func login(email: String, password: String, mfa: String?) async throws -> String? {
        guard let script = scriptURL() else { throw GarminError.sinScript }
        try? FileManager.default.createDirectory(at: tokensDir, withIntermediateDirectories: true)
        let entrada = "\(email)\n\(password)\n\(mfa ?? "")\n"
        let salida = try await correr(venvPython.path,
                                      [script.path, tokensDir.path, "login"],
                                      stdin: entrada)
        // El helper deja los tokens con la sesión; protegerlos como los de Strava.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: tokensDir.path)
        struct R: Decodable { let ok: Bool?; let nombre: String?; let error: String? }
        guard let data = salida.data(using: .utf8),
              let r = try? JSONDecoder().decode(R.self, from: extraerJSON(salida) ?? data),
              r.ok == true
        else { throw GarminError.helperFallo(salida.isEmpty ? "respuesta vacía del helper" : salida) }
        return r.nombre
    }

    static func fetch(dias: Int = 14) async throws -> [GarminWorkout] {
        guard let script = scriptURL() else { throw GarminError.sinScript }
        let salida = try await correr(venvPython.path,
                                      [script.path, tokensDir.path, "fetch", String(dias)])
        guard let data = extraerJSON(salida) else {
            throw GarminError.helperFallo("respuesta ilegible del helper: \(salida.prefix(200))")
        }
        if let ws = try? JSONDecoder().decode([GarminWorkout].self, from: data) {
            return ws
        }
        struct E: Decodable { let error: String }
        if let e = try? JSONDecoder().decode(E.self, from: data) {
            throw GarminError.helperFallo(e.error)
        }
        throw GarminError.helperFallo("respuesta ilegible del helper: \(salida.prefix(200))")
    }

    static func desconectar() {
        try? FileManager.default.removeItem(at: tokensDir)
    }

    /// La última línea que parece JSON (por si algo imprime warnings antes).
    private static func extraerJSON(_ texto: String) -> Data? {
        for linea in texto.split(separator: "\n").reversed() {
            let l = linea.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("{") || l.hasPrefix("[") { return l.data(using: .utf8) }
        }
        return nil
    }

    private static func correr(_ exe: String, _ args: [String], stdin: String? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["PYTHONWARNINGS"] = "ignore"
                p.environment = env

                let outPipe = Pipe(), errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                let inPipe = Pipe()
                p.standardInput = inPipe

                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: GarminError.helperFallo(
                        "no pude ejecutar \(exe): \(error.localizedDescription)"))
                    return
                }
                if let stdin, let data = stdin.data(using: .utf8) {
                    inPipe.fileHandleForWriting.write(data)
                }
                inPipe.fileHandleForWriting.closeFile()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()

                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""

                if p.terminationStatus == 0 {
                    cont.resume(returning: out)
                } else if p.terminationStatus == 42 {
                    cont.resume(throwing: GarminError.mfaRequerida(
                        String(out.prefix(160))))
                } else {
                    let msg = [out, err].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: GarminError.helperFallo(
                        msg.isEmpty ? "el helper terminó con código \(p.terminationStatus)" : String(msg.prefix(400))))
                }
            }
        }
    }
}
