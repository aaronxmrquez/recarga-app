import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                StravaTab()
                    .tabItem { Label("Strava", systemImage: "bolt.horizontal.circle") }
                GarminTab()
                    .tabItem { Label("Garmin", systemImage: "applewatch.radiowaves.left.and.right") }
                PerfilTab()
                    .tabItem { Label("Perfil", systemImage: "person.circle") }
                SemanaTab()
                    .tabItem { Label("Semana", systemImage: "calendar") }
                CarrerasTab()
                    .tabItem { Label("Carreras", systemImage: "flag.checkered") }
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

// MARK: - Garmin

private struct GarminTab: View {
    @EnvironmentObject var state: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var mfa = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.garminConectado {
                Label {
                    Text("Garmin Connect conectado").font(.headline)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text("Recarga lee tus entrenos **programados** (los que TrainingPeaks manda a tu reloj) y los usa en vez de la plantilla: así la cena de hoy ya sabe qué toca mañana de verdad.")
                    .font(.callout).foregroundStyle(.secondary)

                let proximos = state.garminPlan.values
                    .filter { $0.fecha >= Fechas.clave(Date()) }
                    .sorted { $0.fecha < $1.fecha }
                if proximos.isEmpty {
                    Text("No veo entrenos programados en tu calendario de Garmin para los próximos 14 días. Revisa en la app Garmin Connect → Calendario que tus workouts de TrainingPeaks estén llegando.")
                        .font(.callout).foregroundStyle(.orange)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Próximos entrenos leídos (\(proximos.count)):")
                            .font(.callout.weight(.semibold))
                        ForEach(proximos.prefix(5), id: \.fecha) { w in
                            Text("• \(w.fecha) — \(w.titulo)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button("Sincronizar ahora") {
                        Task { await state.fetchGarmin(forzar: true) }
                    }
                    Button("Desconectar", role: .destructive) {
                        state.desconectarGarmin()
                    }
                }
            } else {
                Text("Conectar Garmin Connect").font(.headline)
                Text("Para saber qué te toca **mañana** (y no depender de la plantilla), Recarga lee los entrenos programados de tu calendario de Garmin — los mismos que TrainingPeaks empuja a tu reloj.")
                    .font(.callout).foregroundStyle(.secondary)

                TextField("Email de Garmin", text: $email)
                    .textFieldStyle(.roundedBorder)
                SecureField("Contraseña de Garmin", text: $password)
                    .textFieldStyle(.roundedBorder)
                TextField("Código MFA (solo si tu cuenta lo usa)", text: $mfa)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await state.conectarGarmin(email: email, password: password, mfa: mfa)
                            if state.garminConectado { password = ""; mfa = "" }
                        }
                    } label: {
                        Text(state.conectandoGarmin ? "Conectando…" : "Conectar con Garmin")
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(email.isEmpty || password.isEmpty || state.conectandoGarmin)

                    if state.conectandoGarmin {
                        ProgressView().controlSize(.small)
                    }
                }
                Text("No es la API oficial (Garmin solo la da a empresas): se usa la misma vía que el app móvil, con tu propia cuenta. La contraseña viaja solo a Garmin; aquí quedan únicamente tokens de sesión (~1 año) en tu Mac. Si Garmin cambia algo, se reconecta y listo.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let e = state.garminEstado {
                Text(e).font(.callout)
                    .foregroundStyle(e.hasPrefix("Conectado") ? .green : .orange)
            }
            Spacer()
        }
        .padding(20)
    }
}

// MARK: - Perfil

private struct PerfilTab: View {
    @EnvironmentObject var state: AppState
    @State private var peso = ""
    @State private var altura = ""
    @State private var edad = ""
    @State private var sexo: Sexo = .masculino
    @State private var dieta: Dieta = .vegano
    @State private var proteina = 1.8
    @State private var guardado = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Dieta").frame(width: 110, alignment: .leading)
                Picker("", selection: $dieta) {
                    ForEach(Dieta.allCases) { d in Text(d.label).tag(d) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: dieta) { _, nueva in
                    guard let p = state.profile, p.dieta != nueva else { return }
                    var actualizado = p
                    actualizado.dieta = nueva
                    state.guardarPerfil(actualizado)
                }
            }
            Text("Se aplica al instante: el plan de hoy se regenera con el recetario de la dieta elegida (un vegano ve solo platos veganos; un omnívoro, todo).")
                .font(.caption).foregroundStyle(.secondary)
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
        dieta = p.dieta
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
            pesoKg: p, alturaCm: a, edad: Int(e), sexo: sexo, dieta: dieta,
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

            Text("«Carga» es para los 2–3 días previos a una carrera: carbohidratos al máximo (10–12 g/kg). Si registras tus carreras en la pestaña Carreras, la carga se activa sola — no necesitas tocar la plantilla.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }
}

// MARK: - Carreras

private struct CarrerasTab: View {
    @EnvironmentObject var state: AppState
    @State private var nombre = ""
    @State private var fecha = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var distancia = 42.2

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tus carreras").font(.headline)
            Text("La app activa sola la carga de carbohidratos: 3 días antes en maratón, 2 en media, 1 en 10K o menos. El día de la carrera te da el protocolo de desayuno de competencia y la recuperación.")
                .font(.callout).foregroundStyle(.secondary)

            if state.carreras.isEmpty {
                Text("Sin carreras registradas todavía.")
                    .font(.callout).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(state.carreras.sorted { $0.fecha < $1.fecha }) { c in
                            HStack(spacing: 10) {
                                Image(systemName: "flag.checkered")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.nombre).font(.callout.weight(.semibold))
                                    Text("\(fechaBonita(c)) · \(c.distanciaTexto) · carga \(c.diasCarga) día\(c.diasCarga == 1 ? "" : "s") antes")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    state.eliminarCarrera(c)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Eliminar carrera")
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            Text("Agregar carrera").font(.callout.weight(.semibold))
            TextField("Nombre (ej. Maratón de Lima)", text: $nombre)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 14) {
                DatePicker("Fecha", selection: $fecha, in: Date()..., displayedComponents: .date)
                Picker("Distancia", selection: $distancia) {
                    Text("5K").tag(5.0)
                    Text("10K").tag(10.0)
                    Text("Media (21K)").tag(21.1)
                    Text("30K").tag(30.0)
                    Text("Maratón (42K)").tag(42.2)
                }
                .frame(maxWidth: 190)
            }
            Button("Agregar") {
                state.agregarCarrera(nombre: nombre, fecha: fecha, distanciaKm: distancia)
                nombre = ""
            }
            .buttonStyle(.borderedProminent).tint(.orange)
            .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()
        }
        .padding(20)
    }

    private func fechaBonita(_ c: Carrera) -> String {
        guard let d = c.fechaDate else { return c.fecha }
        return Fechas.tituloDia.string(from: d).capitalized
    }
}
