import SwiftUI

/// "QUE COMER HOY" — lista de comidas clicable (izquierda) + detalle de la
/// comida seleccionada (derecha) que cambia al elegir cada una.
struct MealSection: View {
    let plan: DayPlan
    let dieta: Dieta
    let onOtraReceta: (MealSlot) -> Void

    @State private var selected: MealSlot = .preEntreno

    private var current: PlannedMeal? {
        plan.meals.first { $0.slot == selected } ?? plan.meals.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Que comer hoy")
                .padding(.leading, 4)

            HStack(alignment: .top, spacing: 24) {
                lista
                    .frame(width: 250)
                Divider().overlay(Theme.border)
                if let meal = current {
                    detalle(meal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(meal.slot)                     // recompone al cambiar de slot
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: Lista (maestro)

    private var lista: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(plan.meals) { meal in
                let activo = meal.slot == current?.slot
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selected = meal.slot }
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Theme.mint)
                            .frame(width: 9, height: 9)
                            .opacity(activo ? 1 : 0)
                        Text(meal.slot.label)
                            .font(activo ? Theme.mealItemActive : Theme.mealItem)
                            .foregroundStyle(activo ? Theme.mint : Theme.muted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(activo ? [.isSelected] : [])
            }
        }
    }

    // MARK: Detalle

    @ViewBuilder
    private func detalle(_ meal: PlannedMeal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: meal.slot.icono)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.darkest)
                .frame(height: 32)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(meal.slot.label.uppercased()) (\(hora(meal.slot)))")
                    .font(Theme.cardLabel)
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)

                Text(meal.recipe.nombreResuelto(para: dieta))
                    .font(Theme.detailTitle)
                    .foregroundStyle(Theme.darkest)

                Text("\(Fmt.kcal(meal.kcal)) kcal, C \(Fmt.g(meal.carbs)), P \(Fmt.g(meal.prot)), G \(Fmt.g(meal.grasa)), \(meal.recipe.tiempoMin) min")
                    .font(Theme.detailMacros)
                    .foregroundStyle(Theme.mint)

                Text(meal.recipe.ingredientesResueltos(para: dieta).joined(separator: ", "))
                    .font(Theme.detailBody)
                    .foregroundStyle(Theme.darkest.opacity(0.75))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.top, 14)

            botones(meal)
                .padding(.top, 16)
        }
    }

    private func botones(_ meal: PlannedMeal) -> some View {
        HStack(spacing: 12) {
            Button {
                onOtraReceta(meal.slot)
            } label: {
                Text("OTRA RECETA")
                    .font(Theme.buttonLabel)
                    .tracking(1)
                    .foregroundStyle(Theme.darkest)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            // Presente por diseño; la pantalla interna de receta queda fuera
            // de este alcance. .disabled(true) lo marca como no disponible
            // para VoiceOver (a diferencia de allowsHitTesting) sin cambiar su
            // aspecto de CTA del Figma.
            Button {} label: {
                HStack(spacing: 10) {
                    Text("COMO PREPARARLO (\(meal.recipe.tiempoMin) MIN)")
                        .font(Theme.buttonLabel)
                        .tracking(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.white)
                .padding(.horizontal, 24)
                .frame(height: 44)
                .background(Capsule().fill(Theme.dark))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityHint("Disponible próximamente")
        }
    }

    private func hora(_ slot: MealSlot) -> String {
        switch slot {
        case .preEntreno: return "4:15 AM"
        case .desayuno: return plan.targets.dayType == .largo ? "8:30–9:00 AM" : "8:00 AM"
        case .almuerzo: return "1:00 PM"
        case .snack: return "4:30 PM"
        case .cena: return "7:30 PM"
        }
    }
}
