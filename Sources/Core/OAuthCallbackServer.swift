import Foundation
import Network

/// Mini servidor HTTP local que captura el redirect de OAuth de Strava
/// (http://localhost:8723/callback?code=…) y le muestra al navegador una
/// página de "listo, vuelve a la app".
final class OAuthCallbackServer {
    private var listener: NWListener?
    private var conexiones: [NWConnection] = []
    private var completado = false

    enum CallbackError: Error, LocalizedError {
        case puertoOcupado
        case accesoDenegado
        case sinCodigo

        var errorDescription: String? {
            switch self {
            case .puertoOcupado: return "El puerto \(StravaClient.puerto) está ocupado. Cierra la app que lo usa y reintenta."
            case .accesoDenegado: return "Autorización cancelada en Strava."
            case .sinCodigo: return "Strava no devolvió el código de autorización."
            }
        }
    }

    func iniciar(alRecibirCodigo: @escaping (Result<String, Error>) -> Void) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let puerto = NWEndpoint.Port(rawValue: StravaClient.puerto) else {
            throw CallbackError.puertoOcupado
        }
        let l: NWListener
        do {
            l = try NWListener(using: params, on: puerto)
        } catch {
            throw CallbackError.puertoOcupado
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            self.conexiones.append(conn)
            conn.start(queue: .main)
            self.recibir(conn, alRecibirCodigo: alRecibirCodigo)
        }
        l.start(queue: .main)
    }

    private func recibir(_ conn: NWConnection, alRecibirCodigo: @escaping (Result<String, Error>) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let texto = String(data: data, encoding: .utf8) else { return }
            guard let lineaGET = texto.split(separator: "\r\n").first,
                  lineaGET.hasPrefix("GET ") else {
                self.responder(conn, cuerpo: "Recarga", cerrar: true)
                return
            }
            let path = lineaGET.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let comp = URLComponents(string: "http://localhost\(path)")
            let items = comp?.queryItems ?? []
            let code = items.first(where: { $0.name == "code" })?.value
            let error = items.first(where: { $0.name == "error" })?.value

            // El navegador suele pedir también /favicon.ico — ignorarlo.
            guard comp?.path == "/callback" else {
                self.responder(conn, cuerpo: "", cerrar: true)
                return
            }

            let mensaje = code != nil
                ? "<h1>✅ Strava conectado</h1><p>Ya puedes volver a <b>Recarga</b>.</p>"
                : "<h1>Autorización cancelada</h1><p>Vuelve a Recarga e inténtalo de nuevo.</p>"
            self.responder(conn, cuerpo: "<html><meta charset='utf-8'><body style='font-family:-apple-system;text-align:center;padding-top:80px'>\(mensaje)</body></html>", cerrar: true)

            guard !self.completado else { return }
            self.completado = true
            if let code {
                alRecibirCodigo(.success(code))
            } else if error != nil {
                alRecibirCodigo(.failure(CallbackError.accesoDenegado))
            } else {
                alRecibirCodigo(.failure(CallbackError.sinCodigo))
            }
        }
    }

    private func responder(_ conn: NWConnection, cuerpo: String, cerrar: Bool) {
        let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(cuerpo.utf8.count)\r\nConnection: close\r\n\r\n\(cuerpo)"
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in
            if cerrar { conn.cancel() }
        })
    }

    func detener() {
        listener?.cancel()
        listener = nil
        conexiones.forEach { $0.cancel() }
        conexiones.removeAll()
    }
}
