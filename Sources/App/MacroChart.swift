import SwiftUI

/// Mini gráfico de barras que se anima (crece desde 0, escalonado izq→der)
/// la primera vez que aparece. Los valores representan el reparto del dato
/// de la tarjeta entre las comidas del día.
struct MiniBarChart: View {
    let values: [Double]
    var color: Color = Theme.mint
    var maxHeight: CGFloat = 34
    var barWidth: CGFloat = 5
    var spacing: CGFloat = 3.5

    @State private var grown = false

    private var normalized: [CGFloat] {
        let m = max(values.max() ?? 1, 0.0001)
        return values.map { CGFloat(max($0, 0) / m) }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(normalized.enumerated()), id: \.offset) { i, h in
                Capsule(style: .continuous)
                    .fill(color.opacity(0.45 + 0.55 * Double(h)))
                    .frame(width: barWidth, height: grown ? max(3, maxHeight * h) : 3)
                    // Al aparecer: crece desde 0 con revelado escalonado izq→der.
                    .animation(.easeOut(duration: 0.5).delay(Double(i) * 0.05), value: grown)
                    // Al refrescar datos: la altura se re-anima suavemente.
                    .animation(.easeOut(duration: 0.45), value: h)
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .onAppear { grown = true }
    }
}

/// Tarjeta de un dato de entrenamiento (Energía, Carbohidratos, …) con su
/// mini-gráfico a la derecha.
struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    let chartValues: [Double]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased())
                    .font(Theme.cardLabel)
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(Theme.metricValue)
                        .foregroundStyle(Theme.darkest)
                    Text(unit)
                        .font(Theme.metricUnit)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            MiniBarChart(values: chartValues)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .fill(Theme.cardBackground))
    }
}

/// Contenedor "DATA DE ENTRENAMIENTO": 5 tarjetas (3 + 2) sobre fondo smoke.
struct TrainingDataGrid: View {
    let plan: DayPlan

    /// Reparto de un macro entre las comidas del día (para el gráfico).
    private func porComida(_ key: (PlannedMeal) -> Double) -> [Double] {
        plan.meals.map(key)
    }

    /// Pauta de hidratación del día (antes / durante / después / resto).
    private var aguaSchedule: [Double] {
        let h = plan.targets.horasEntreno
        if h > 0 {
            return [0.5, max(0.4, 0.55 * h), 0.6, max(0.4, plan.targets.aguaLitros - 1.5 - 0.55 * h)]
        }
        // Día sin entreno: repartida pareja en 4 momentos.
        let q = plan.targets.aguaLitros / 4
        return [q, q, q, q]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Data de entrenamiento")
                .padding(.leading, 4)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    MetricCard(label: "Energía", value: Fmt.kcal(plan.targets.kcal),
                               unit: "kcal", chartValues: porComida { $0.kcal })
                    MetricCard(label: "Carbohidratos", value: Fmt.g(plan.targets.carbs),
                               unit: String(format: "%.0f g/kg", plan.targets.carbsGkg),
                               chartValues: porComida { $0.carbs })
                    MetricCard(label: "Proteína", value: Fmt.g(plan.targets.prot),
                               unit: "Reparar", chartValues: porComida { $0.prot })
                }
                HStack(spacing: 12) {
                    MetricCard(label: "Grasa", value: Fmt.g(plan.targets.grasa),
                               unit: "Mínimo sano", chartValues: porComida { $0.grasa })
                    MetricCard(label: "Agua", value: String(format: "%.1f L", plan.targets.aguaLitros),
                               unit: plan.targets.horasEntreno > 0
                                    ? String(format: "Incl. %.1fh de entreno", plan.targets.horasEntreno)
                                    : "Día sin entreno",
                               chartValues: aguaSchedule)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Theme.containerRadius, style: .continuous)
            .fill(Theme.smoke))
    }
}
