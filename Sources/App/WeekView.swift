import SwiftUI
import AppKit

/// Proyección de los próximos 7 días + lista de compras consolidada.
struct WeekView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var dias: [DiaProyectado] = []
    @State private var lista: [(categoria: String, items: [ItemCompra])] = []
    @State private var copiado = false

    private let fmtDia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "EEEE d"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Semana y compras").font(.title2.bold())
                    Text("Proyección de los próximos 7 días según tu plantilla y carreras")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copiar()
                } label: {
                    Label(copiado ? "¡Copiada!" : "Copiar lista", systemImage: copiado ? "checkmark" : "doc.on.doc")
                }
                .tint(.orange)
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Lista de compras
                    Text("Lista de compras").font(.title3.bold())
                    if lista.isEmpty {
                        Text("Completa tu perfil para generar la proyección.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lista, id: \.categoria) { grupo in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(grupo.categoria)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.orange)
                            ForEach(grupo.items) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("•")
                                    Text(item.nombre)
                                    Spacer()
                                    Text(item.detalle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.callout)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                    }

                    Text("Las cantidades son aproximadas y suben si tu entrenamiento real pide porciones más grandes. Si cambias platos con ↻ durante la semana, la lista varía un poco.")
                        .font(.caption).foregroundStyle(.tertiary)

                    Divider()

                    // Menú proyectado
                    Text("Menú proyectado").font(.title3.bold())
                    ForEach(dias) { dia in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(fmtDia.string(from: dia.fecha).capitalized)
                                    .font(.callout.weight(.semibold))
                                etiquetaDia(dia)
                                if let nota = dia.notaEntreno {
                                    Text("· \(nota)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            ForEach(dia.meals) { m in
                                Text("\(m.slot.label): \(m.recipe.nombre)\(m.porciones != 1 ? " \(Fmt.porciones(m.porciones))" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 640, height: 720)
        .onAppear { calcular() }
    }

    @ViewBuilder
    private func etiquetaDia(_ dia: DiaProyectado) -> some View {
        switch dia.estado {
        case .diaDeCarrera(let c):
            Label("Carrera: \(c.nombre)", systemImage: "flag.checkered")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
        case .enCarga:
            Label(dia.tipo.label, systemImage: dia.tipo.icono)
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
        case .normal:
            Label(dia.tipo.label, systemImage: dia.tipo.icono)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func calcular() {
        dias = state.proyectarSemana()
        lista = ShoppingList.generar(dias: dias)
    }

    private func copiar() {
        let texto = ShoppingList.textoParaCopiar(dias: dias, lista: lista)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        copiado = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiado = false }
    }
}
