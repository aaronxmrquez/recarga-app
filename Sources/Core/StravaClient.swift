import Foundation

enum StravaError: Error, LocalizedError {
    case sinCredenciales
    case sinTokens
    case http(Int, String)
    case respuestaInvalida

    var errorDescription: String? {
        switch self {
        case .sinCredenciales: return "Faltan el Client ID y el Client Secret de Strava (Ajustes)."
        case .sinTokens: return "Cuenta de Strava no conectada todavía."
        case .http(let code, let cuerpo):
            return "Strava respondió \(code): \(cuerpo.prefix(160))"
        case .respuestaInvalida: return "Respuesta inesperada de Strava."
        }
    }
}

/// Cliente mínimo de la API v3 de Strava (OAuth code flow + actividades).
final class StravaClient {
    static let puerto: UInt16 = 8723
    static var redirectURI: String { "http://localhost:\(puerto)/callback" }

    var creds: StravaCredentials?
    var tokens: StravaTokens?
    /// Se llama cada vez que los tokens cambian (para persistirlos).
    var alActualizarTokens: ((StravaTokens) -> Void)?

    var conectado: Bool { creds != nil && tokens != nil }

    // MARK: OAuth

    func authorizeURL() -> URL? {
        guard let creds else { return nil }
        var comp = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        comp.queryItems = [
            .init(name: "client_id", value: creds.clientId),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: "read,activity:read_all,profile:read_all"),
        ]
        return comp.url
    }

    func canjearCodigo(_ code: String) async throws {
        let t = try await pedirToken([
            "grant_type": "authorization_code",
            "code": code,
        ])
        tokens = t
        alActualizarTokens?(t)
    }

    private func refrescarSiHaceFalta() async throws {
        guard let t = tokens else { throw StravaError.sinTokens }
        if t.expiresAt - 300 > Date().timeIntervalSince1970 { return }
        let nuevo = try await pedirToken([
            "grant_type": "refresh_token",
            "refresh_token": t.refreshToken,
        ])
        tokens = nuevo
        alActualizarTokens?(nuevo)
    }

    private struct TokenResponse: Decodable {
        struct Athlete: Decodable {
            let firstname: String?
            let lastname: String?
        }
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval
        let athlete: Athlete?
    }

    private func pedirToken(_ extra: [String: String]) async throws -> StravaTokens {
        guard let creds else { throw StravaError.sinCredenciales }
        var params = extra
        params["client_id"] = creds.clientId
        params["client_secret"] = creds.clientSecret

        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw StravaError.respuestaInvalida }
        guard http.statusCode == 200 else {
            throw StravaError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let r = try dec.decode(TokenResponse.self, from: data)
        let nombre = [r.athlete?.firstname, r.athlete?.lastname]
            .compactMap { $0 }.joined(separator: " ")
        return StravaTokens(
            accessToken: r.accessToken,
            refreshToken: r.refreshToken,
            expiresAt: r.expiresAt,
            athleteName: nombre.isEmpty ? tokens?.athleteName : nombre
        )
    }

    // MARK: API

    private func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        try await refrescarSiHaceFalta()
        guard let t = tokens else { throw StravaError.sinTokens }
        var comp = URLComponents(string: "https://www.strava.com/api/v3" + path)!
        if !query.isEmpty {
            comp.queryItems = query.map { .init(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comp.url!)
        req.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw StravaError.respuestaInvalida }
        guard http.statusCode == 200 else {
            throw StravaError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func actividadesRecientes(dias: Int = 8) async throws -> [StravaActivity] {
        let despues = Int(Date().addingTimeInterval(-Double(dias) * 86400).timeIntervalSince1970)
        let data = try await get("/athlete/activities", query: [
            "after": String(despues),
            "per_page": "100",
        ])
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode([StravaActivity].self, from: data)
    }

    /// Las calorías solo vienen en el detalle de la actividad.
    func caloriasDeActividad(id: Int) async throws -> Double? {
        struct Detalle: Decodable { let calories: Double? }
        let data = try await get("/activities/\(id)")
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(Detalle.self, from: data).calories
    }
}
