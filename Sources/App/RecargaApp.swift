import SwiftUI

@main
struct RecargaApp: App {
    @StateObject private var state: AppState

    init() {
        if CommandLine.arguments.contains("--selftest") {
            exit(runSelfTest())
        }
        _state = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 660, minHeight: 700)
        }
        .defaultSize(width: 760, height: 940)
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var mostrarAjustes = false

    var body: some View {
        Group {
            if let err = state.recetasError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text("No pude cargar el recetario").font(.headline)
                    Text(err).font(.callout).foregroundStyle(.secondary)
                }
                .padding(40)
            } else if state.profile == nil {
                OnboardingView()
            } else {
                TodayView(mostrarAjustes: $mostrarAjustes)
            }
        }
        .sheet(isPresented: $mostrarAjustes) {
            SettingsView().environmentObject(state)
        }
        .task { await state.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await state.refreshSiToca() }
        }
    }
}

// MARK: Formato de números

enum Fmt {
    static let entero: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "es_PE")
        return f
    }()

    static func kcal(_ v: Double) -> String {
        (entero.string(from: NSNumber(value: v)) ?? "\(Int(v))")
    }

    static func g(_ v: Double) -> String { "\(Int(v.rounded())) g" }

    static func porciones(_ v: Double) -> String {
        v == v.rounded() ? "×\(Int(v))" : String(format: "×%.2g", v)
    }
}
