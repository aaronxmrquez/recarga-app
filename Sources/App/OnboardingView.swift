import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var state: AppState

    @State private var peso = ""
    @State private var altura = ""
    @State private var edad = ""
    @State private var sexo: Sexo = .masculino
    @State private var proteina = 1.8
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Recarga").font(.largeTitle.bold())
                Text("Qué comer según tu entrenamiento — vegano y peruano")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                campo("Peso (kg)", texto: $peso, placeholder: "66")
                campo("Altura (cm)", texto: $altura, placeholder: "172")
                campo("Edad", texto: $edad, placeholder: "32")

                HStack {
                    Text("Sexo").frame(width: 110, alignment: .leading)
                    Picker("", selection: $sexo) {
                        ForEach(Sexo.allCases) { s in Text(s.label).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack {
                    Text("Proteína").frame(width: 110, alignment: .leading)
                    Slider(value: $proteina, in: 1.6...2.2, step: 0.1)
                    Text(String(format: "%.1f g/kg", proteina))
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
                Text("Para veganos de fondo se recomienda el rango alto (1.8–2.0).")
                    .font(.caption).foregroundStyle(.secondary)

                Label("Asumo que entrenas de madrugada (~5:00–7:30 am): el plan incluye pre-entreno al despertar y el desayuno como comida de recuperación.",
                      systemImage: "sunrise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 420)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            Button {
                guardar()
            } label: {
                Text("Empezar").font(.headline).frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)

            Text("Después conecta Strava desde el engranaje ⚙︎ para que el plan use tus entrenos reales.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func campo(_ titulo: String, texto: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(titulo).frame(width: 110, alignment: .leading)
            TextField(placeholder, text: texto)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func num(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func guardar() {
        guard let p = num(peso), p > 30, p < 200,
              let a = num(altura), a > 120, a < 230,
              let e = num(edad), e > 12, e < 100
        else {
            error = "Revisa los datos: peso 30–200 kg, altura 120–230 cm, edad 12–100."
            return
        }
        state.guardarPerfil(UserProfile(
            pesoKg: p, alturaCm: a, edad: Int(e), sexo: sexo,
            proteinaGkg: (proteina * 10).rounded() / 10,
            factorActividad: 1.4))
    }
}
