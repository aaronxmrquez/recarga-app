import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                StravaTab()
                    .tabItem { Label("Strava", systemImage: "bolt.horizontal.circle") }
                PerfilTab()
                    .tabItem { Label("Perfil", systemImage: "person.circle") }
                SemanaTab()
                    .tabItem { Label("Semana", systemImage: "calendar") }
            }
            .padding(.top, 8)

            HStack {
                Spacer()
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 620)
    }
}

// MARK: - Strava

private struct StravaTab: View {
    @EnvironmentObject var state: AppState
    @State private var clientId = ""
    @State private var clientSecret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.stravaConectado {
                Label {
                    Text("Conectado\(state.atleta.map { " como \($0)" } ?? "")")
                        .font(.headline)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text("El plan del día se recalcula con tus actividades reales al abrir la app o con el botón ↻.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Desconectar cuenta", role: .destructive) {
                    state.desconectarStrava()
                }
            } else {
                Text("Conectar Strava").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Entra a **strava.com/settings/api** y crea tu app (una sola vez).")
                    Text("2. En *Authorization Callback Domain* escribe: **localhost**")
                    Text("3. Copia aquí el *Client ID* y el *Client Secret*:")
                }
                .font(.callout)

                TextField("Client ID", text: $clientId)
                    .textFieldStyle(.roundedBorder)
                TextField("Client Secret", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await state.conectarStrava(
                                clientId: clientId, clientSecret: clientSecret)
                        }
                    } label: {
                        Text(state.conectando ? "Esperando a Strava…" : "Conectar con Strava")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(clientId.isEmpty || clientSecret.isEmpty || state.conectando)

                    if state.conectando {
                        ProgressView().controlSize(.small)
                    }
                }
                Text("Se abrirá tu navegador para autorizar. Los tokens se guardan solo en tu Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let e = state.errorMsg {
                Text(e).font(.callout).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(20)
        .onAppear {
            if let c = state.strava.creds {
                clientId = c.clientId
                clientSecret = c.clientSecret
            }
        }
    }
}

// MARK: - Perfil

private struct PerfilTab: View {
    @EnvironmentObject var state: AppState
    @State private var peso = ""
    @State private var altura = ""
    @State private var edad = ""
    @State private var sexo: Sexo = .masculino
    @State private var proteina = 1.8
    @State private var guardado = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            campo("Peso (kg)", $peso)
            campo("Altura (cm)", $altura)
            campo("Edad", $edad)
            HStack {
                Text("Sexo").frame(width: 110, alignment: .leading)
                Picker("", selection: $sexo) {
                    ForEach(Sexo.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            HStack {
                Text("Proteína").frame(width: 110, alignment: .leading)
                Slider(value: $proteina, in: 1.6...2.2, step: 0.1)
                Text(String(format: "%.1f g/kg", proteina))
                    .monospacedDigit().frame(width: 70, alignment: .trailing)
            }
            Text("Actualiza el peso cada 1–2 semanas: todos los objetivos son por kg.")
                .font(.caption).foregroundStyle(.secondary)

            if let error { Text(error).font(.callout).foregroundStyle(.red) }

            HStack {
                Button("Guardar cambios") { guardar() }
                    .buttonStyle(.borderedProminent).tint(.orange)
                if guardado {
                    Label("Guardado", systemImage: "checkmark")
                        .font(.callout).foregroundStyle(.green)
                }
            }
            Spacer()
        }
        .padding(20)
        .onAppear { cargar() }
    }

    private func campo(_ titulo: String, _ b: Binding<String>) -> some View {
        HStack {
            Text(titulo).frame(width: 110, alignment: .leading)
            TextField("", text: b).textFieldStyle(.roundedBorder)
        }
    }

    private func cargar() {
        guard let p = state.profile else { return }
        peso = String(format: "%.1f", p.pesoKg)
        altura = String(format: "%.0f", p.alturaCm)
        edad = "\(p.edad)"
        sexo = p.sexo
        proteina = p.proteinaGkg
    }

    private func num(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func guardar() {
        guard let p = num(peso), p > 30, p < 200,
              let a = num(altura), a > 120, a < 230,
              let e = num(edad), e > 12, e < 100
        else {
            error = "Revisa los datos."
            return
        }
        error = nil
        state.guardarPerfil(UserProfile(
            pesoKg: p, alturaCm: a, edad: Int(e), sexo: sexo,
            proteinaGkg: (proteina * 10).rounded() / 10,
            factorActividad: state.profile?.factorActividad ?? 1.4))
        guardado = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { guardado = false }
    }
}

// MARK: - Plantilla semanal

private struct SemanaTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tu semana típica de entrenamiento")
                .font(.headline)
            Text("Strava dice lo que ya corriste; esto dice lo que viene — así la cena de hoy se adelanta al fondo de mañana. Ajústala cuando cambie tu bloque.")
                .font(.callout).foregroundStyle(.secondary)

            ForEach(0..<7, id: \.self) { i in
                HStack {
                    Text(TrainingTemplate.nombresDias[i])
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { state.template.dias[i] },
                        set: { nuevo in
                            var t = state.template
                            t.dias[i] = nuevo
                            state.guardarPlantilla(t)
                        }
                    )) {
                        ForEach(DayType.allCases) { d in
                            Label(d.label, systemImage: d.icono).tag(d)
                        }
                    }
                    .labelsHidden()
                }
            }

            Text("«Carga» es para los 2–3 días previos a un maratón: carbohidratos al máximo (10–12 g/kg) sin entrenamiento fuerte.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }
}
