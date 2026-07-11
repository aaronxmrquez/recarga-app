import Foundation

// MARK: - Proyección de la semana

struct DiaProyectado: Identifiable {
    let fecha: Date
    let tipo: DayType
    let estado: EstadoCarrera
    let meals: [PlannedMeal]
    /// Título del entreno programado en Garmin, si existe.
    let notaEntreno: String?
    var id: String { Fechas.clave(fecha) }
}

enum WeekPlanner {

    /// Simula el plan de los próximos días tal como lo hará la app día a día:
    /// misma semilla por fecha y el historial se va acumulando, así la
    /// proyección coincide con lo que se sugerirá (si el entreno real coincide
    /// con la plantilla).
    static func proyectar(
        desde inicio: Date,
        dias nDias: Int,
        profile: UserProfile,
        template: TrainingTemplate,
        carreras: [Carrera],
        recetas: [Recipe],
        historia: MealHistory,
        garmin: [String: GarminWorkout] = [:]
    ) -> [DiaProyectado] {
        var hist = historia
        var out: [DiaProyectado] = []
        let cal = Calendar.current

        // Prioridad por día: carrera > entreno programado en Garmin > plantilla.
        func base(_ fecha: Date) -> DayType {
            garmin[Fechas.clave(fecha)].flatMap { GarminPlan.tipoDe($0) } ?? template.tipo(para: fecha)
        }

        for i in 0..<nDias {
            guard let fecha = cal.date(byAdding: .day, value: i, to: inicio) else { continue }
            let estado = RaceCalendar.estado(para: fecha, carreras: carreras)
            let tipo = RaceCalendar.tipoEfectivo(plantilla: base(fecha), estado: estado)
            let planWatch = garmin[Fechas.clave(fecha)]

            let sig = cal.date(byAdding: .day, value: 1, to: fecha) ?? fecha
            let estadoSig = RaceCalendar.estado(para: sig, carreras: carreras)
            let tipoSig = RaceCalendar.tipoEfectivo(plantilla: base(sig), estado: estadoSig)

            let kcal: Double
            let horas: Double
            if case .diaDeCarrera(let c) = estado {
                kcal = c.distanciaKm * profile.pesoKg
                horas = c.distanciaKm / 10
            } else if tipo == .descanso || tipo == .carga {
                kcal = 0
                horas = 0
            } else if let w = planWatch, GarminPlan.tipoDe(w) != nil {
                kcal = GarminPlan.kcalEstimada(w, pesoKg: profile.pesoKg)
                    ?? NutritionEngine.kcalEstimada(tipo: tipo, pesoKg: profile.pesoKg)
                horas = w.duracionSeg.map { Double($0) / 3600 }
                    ?? NutritionEngine.horasEstimadas(tipo: tipo)
            } else {
                kcal = NutritionEngine.kcalEstimada(tipo: tipo, pesoKg: profile.pesoKg)
                horas = NutritionEngine.horasEstimadas(tipo: tipo)
            }

            let targets = NutritionEngine.dayTargets(
                profile: profile, dayType: tipo, trainingKcal: kcal, horasEntreno: horas)
            let mealTargets = NutritionEngine.mealTargets(day: targets, manana: tipoSig)
            let planner = MealPlanner(recetas: recetas, history: hist)
            let meals = planner.plan(
                fecha: fecha, targets: mealTargets, fijadas: hist[Fechas.clave(fecha)] ?? [:])

            var registro: [String: String] = [:]
            for m in meals { registro[m.slot.rawValue] = m.recipe.id }
            hist[Fechas.clave(fecha)] = registro

            out.append(DiaProyectado(
                fecha: fecha, tipo: tipo, estado: estado, meals: meals,
                notaEntreno: planWatch?.titulo))
        }
        return out
    }
}

// MARK: - Lista de compras

struct ItemCompra: Identifiable {
    let nombre: String
    let categoria: String
    var gramos: Double = 0
    var mililitros: Double = 0
    var unidades: Double = 0
    var comidas: Int = 0
    var id: String { nombre }

    var detalle: String {
        var partes: [String] = []
        if gramos > 0 {
            let g = max(50, (gramos / 50).rounded(.up) * 50)
            partes.append(g >= 1000 ? String(format: "≈ %.1f kg", g / 1000) : "≈ \(Int(g)) g")
        }
        if mililitros > 0 {
            let ml = max(100, (mililitros / 100).rounded(.up) * 100)
            partes.append(ml >= 1000 ? String(format: "≈ %.1f L", ml / 1000) : "≈ \(Int(ml)) ml")
        }
        if unidades > 0 {
            partes.append("≈ \(Int(unidades.rounded(.up))) und")
        }
        partes.append("\(comidas) comida\(comidas == 1 ? "" : "s")")
        return partes.joined(separator: " · ")
    }
}

enum ShoppingList {

    static let ordenCategorias = [
        "Frutas y verduras", "Menestras y granos", "Proteínas",
        "Panes y fideos", "Despensa", "Otros",
    ]

    private struct Def {
        let nombre: String
        let categoria: String
        let claves: [String]
    }

    // Mapa de ingredientes del recetario → ítem de mercado.
    // El matching es por palabra completa y de clave más larga a más corta.
    private static let defs: [Def] = [
        // Frutas y verduras
        Def(nombre: "Plátano", categoria: "Frutas y verduras", claves: ["plátanos", "plátano"]),
        Def(nombre: "Manzana", categoria: "Frutas y verduras", claves: ["manzana"]),
        Def(nombre: "Papaya", categoria: "Frutas y verduras", claves: ["papaya"]),
        Def(nombre: "Naranja (jugo)", categoria: "Frutas y verduras", claves: ["jugo de naranja", "naranja"]),
        Def(nombre: "Limón", categoria: "Frutas y verduras", claves: ["limones", "limón"]),
        Def(nombre: "Mango", categoria: "Frutas y verduras", claves: ["mango"]),
        Def(nombre: "Granadilla", categoria: "Frutas y verduras", claves: ["granadilla"]),
        Def(nombre: "Mandarina", categoria: "Frutas y verduras", claves: ["mandarinas", "mandarina"]),
        Def(nombre: "Palta", categoria: "Frutas y verduras", claves: ["palta"]),
        Def(nombre: "Tomate", categoria: "Frutas y verduras", claves: ["tomate"]),
        Def(nombre: "Cebolla china", categoria: "Frutas y verduras", claves: ["cebolla china"]),
        Def(nombre: "Cebolla", categoria: "Frutas y verduras", claves: ["cebolla roja", "cebolla"]),
        Def(nombre: "Salsa/ensalada criolla (cebolla, limón, culantro)", categoria: "Frutas y verduras", claves: ["salsa criolla", "ensalada criolla"]),
        Def(nombre: "Ají amarillo", categoria: "Frutas y verduras", claves: ["ají amarillo"]),
        Def(nombre: "Ají panca", categoria: "Despensa", claves: ["ají panca"]),
        Def(nombre: "Ají limo", categoria: "Frutas y verduras", claves: ["ají limo"]),
        Def(nombre: "Rocoto", categoria: "Frutas y verduras", claves: ["rocoto"]),
        Def(nombre: "Ají", categoria: "Frutas y verduras", claves: ["ají"]),
        Def(nombre: "Camote", categoria: "Frutas y verduras", claves: ["camotes", "camote"]),
        Def(nombre: "Papa seca", categoria: "Despensa", claves: ["papa seca"]),
        Def(nombre: "Papa", categoria: "Frutas y verduras", claves: ["papas amarillas", "papa amarilla", "papas", "papa"]),
        Def(nombre: "Yuca", categoria: "Frutas y verduras", claves: ["yuca"]),
        Def(nombre: "Zanahoria", categoria: "Frutas y verduras", claves: ["zanahoria"]),
        Def(nombre: "Zapallo", categoria: "Frutas y verduras", claves: ["zapallo macre", "zapallo"]),
        Def(nombre: "Choclo", categoria: "Frutas y verduras", claves: ["choclo"]),
        Def(nombre: "Pimiento", categoria: "Frutas y verduras", claves: ["pimiento"]),
        Def(nombre: "Espinaca", categoria: "Frutas y verduras", claves: ["espinaca"]),
        Def(nombre: "Apio", categoria: "Frutas y verduras", claves: ["apio"]),
        Def(nombre: "Vainitas", categoria: "Frutas y verduras", claves: ["vainitas"]),
        Def(nombre: "Holantao", categoria: "Frutas y verduras", claves: ["holantao"]),
        Def(nombre: "Olluco", categoria: "Frutas y verduras", claves: ["olluco"]),
        Def(nombre: "Champiñones", categoria: "Frutas y verduras", claves: ["champiñones"]),
        Def(nombre: "Lechuga", categoria: "Frutas y verduras", claves: ["lechuga"]),
        Def(nombre: "Verduras de hoja (ensalada)", categoria: "Frutas y verduras", claves: ["ensalada verde"]),
        Def(nombre: "Pepino", categoria: "Frutas y verduras", claves: ["pepino"]),
        Def(nombre: "Brócoli", categoria: "Frutas y verduras", claves: ["brócoli"]),
        Def(nombre: "Culantro", categoria: "Frutas y verduras", claves: ["culantro"]),
        Def(nombre: "Albahaca", categoria: "Frutas y verduras", claves: ["albahaca"]),
        Def(nombre: "Hierbabuena", categoria: "Frutas y verduras", claves: ["hierbabuena"]),
        Def(nombre: "Kion", categoria: "Frutas y verduras", claves: ["kion"]),
        Def(nombre: "Ajo", categoria: "Frutas y verduras", claves: ["ajo"]),
        Def(nombre: "Arvejas", categoria: "Frutas y verduras", claves: ["arvejitas", "arvejas"]),
        Def(nombre: "Habas", categoria: "Frutas y verduras", claves: ["habas verdes", "habas secas", "habas"]),
        // Menestras y granos
        Def(nombre: "Quinua pop", categoria: "Menestras y granos", claves: ["quinua pop"]),
        Def(nombre: "Quinua", categoria: "Menestras y granos", claves: ["quinua"]),
        Def(nombre: "Kiwicha", categoria: "Menestras y granos", claves: ["kiwicha"]),
        Def(nombre: "Tarwi (chocho)", categoria: "Menestras y granos", claves: ["tarwi", "chocho"]),
        Def(nombre: "Lentejas", categoria: "Menestras y granos", claves: ["lentejas", "lenteja"]),
        Def(nombre: "Frejol canario", categoria: "Menestras y granos", claves: ["frejol canario"]),
        Def(nombre: "Frejol negro", categoria: "Menestras y granos", claves: ["frejol negro"]),
        Def(nombre: "Frejoles", categoria: "Menestras y granos", claves: ["frejoles"]),
        Def(nombre: "Pallares", categoria: "Menestras y granos", claves: ["pallares"]),
        Def(nombre: "Garbanzos", categoria: "Menestras y granos", claves: ["garbanzos", "garbanzo"]),
        Def(nombre: "Arroz integral", categoria: "Menestras y granos", claves: ["arroz integral"]),
        Def(nombre: "Arroz", categoria: "Menestras y granos", claves: ["arroz"]),
        Def(nombre: "Avena", categoria: "Menestras y granos", claves: ["avena"]),
        Def(nombre: "Morón (cebada)", categoria: "Menestras y granos", claves: ["morón", "cebada"]),
        Def(nombre: "Maíz chulpe / cancha", categoria: "Menestras y granos", claves: ["maíz chulpe", "canchita", "cancha"]),
        Def(nombre: "Maíz morado", categoria: "Menestras y granos", claves: ["maíz morado"]),
        // Soya y proteínas
        Def(nombre: "Tofu firme", categoria: "Proteínas", claves: ["tofu"]),
        Def(nombre: "Leche de soya fortificada", categoria: "Proteínas", claves: ["leche de soya"]),
        Def(nombre: "Soya texturizada", categoria: "Proteínas", claves: ["soya texturizada"]),
        Def(nombre: "Proteína de arveja", categoria: "Proteínas", claves: ["proteína de arveja"]),
        Def(nombre: "Hummus", categoria: "Proteínas", claves: ["hummus"]),
        Def(nombre: "Mayonesa vegana", categoria: "Proteínas", claves: ["mayonesa vegana"]),
        Def(nombre: "Huevos", categoria: "Proteínas", claves: ["huevo duro", "huevos fritos", "huevo frito", "huevos", "huevo"]),
        Def(nombre: "Pollo", categoria: "Proteínas", claves: ["pechuga de pollo", "pollo deshilachado", "presa de pollo", "pechuga", "pollo"]),
        Def(nombre: "Pavita", categoria: "Proteínas", claves: ["pavita"]),
        Def(nombre: "Carne de res", categoria: "Proteínas", claves: ["carne molida", "lomo o bistec", "bistec", "lomo"]),
        Def(nombre: "Pescado", categoria: "Proteínas", claves: ["pescado fresco", "bonito o jurel", "pescado", "bonito", "jurel"]),
        Def(nombre: "Atún", categoria: "Proteínas", claves: ["atún"]),
        Def(nombre: "Queso fresco", categoria: "Proteínas", claves: ["queso fresco", "queso"]),
        Def(nombre: "Yogurt", categoria: "Proteínas", claves: ["yogurt griego", "yogurt"]),
        Def(nombre: "Leche", categoria: "Proteínas", claves: ["leche evaporada", "leche entera", "leche"]),
        Def(nombre: "Granola", categoria: "Despensa", claves: ["granola"]),
        Def(nombre: "Mayonesa", categoria: "Despensa", claves: ["mayonesa"]),
        Def(nombre: "Galletas de soda", categoria: "Despensa", claves: ["galletas de soda"]),
        Def(nombre: "Vinagre", categoria: "Despensa", claves: ["vinagre"]),
        // Panes y fideos
        Def(nombre: "Pan", categoria: "Panes y fideos", claves: ["panes franceses", "panes integrales", "pan de molde", "pan francés", "pan integral", "pan tostado", "tostadas", "panes", "pan"]),
        Def(nombre: "Tallarines", categoria: "Panes y fideos", claves: ["tallarines"]),
        Def(nombre: "Fideos canuto", categoria: "Panes y fideos", claves: ["fideos canuto", "fideos"]),
        Def(nombre: "Tortillas de trigo", categoria: "Panes y fideos", claves: ["tortillas de trigo"]),
        // Despensa
        Def(nombre: "Dátiles", categoria: "Despensa", claves: ["dátiles", "dátil"]),
        Def(nombre: "Mermelada", categoria: "Despensa", claves: ["mermelada"]),
        Def(nombre: "Chancaca / miel de caña", categoria: "Despensa", claves: ["chancaca", "miel de caña"]),
        Def(nombre: "Canela", categoria: "Despensa", claves: ["canela"]),
        Def(nombre: "Clavo de olor", categoria: "Despensa", claves: ["clavo"]),
        Def(nombre: "Maicena", categoria: "Despensa", claves: ["maicena"]),
        Def(nombre: "Azúcar", categoria: "Despensa", claves: ["azúcar"]),
        Def(nombre: "Pasas", categoria: "Despensa", claves: ["pasas"]),
        Def(nombre: "Cacao", categoria: "Despensa", claves: ["cacao"]),
        Def(nombre: "Chía", categoria: "Despensa", claves: ["chía"]),
        Def(nombre: "Maca", categoria: "Despensa", claves: ["maca"]),
        Def(nombre: "Cúrcuma", categoria: "Despensa", claves: ["cúrcuma"]),
        Def(nombre: "Mantequilla de maní", categoria: "Despensa", claves: ["mantequilla de maní"]),
        Def(nombre: "Maní", categoria: "Despensa", claves: ["maní"]),
        Def(nombre: "Sillao", categoria: "Despensa", claves: ["sillao"]),
        Def(nombre: "Aceite de oliva", categoria: "Despensa", claves: ["aceite de oliva"]),
        Def(nombre: "Aceitunas", categoria: "Despensa", claves: ["aceitunas"]),
        Def(nombre: "Sal", categoria: "Despensa", claves: ["pizca de sal", "sal"]),
        Def(nombre: "Comino", categoria: "Despensa", claves: ["comino"]),
        Def(nombre: "Orégano", categoria: "Despensa", claves: ["orégano"]),
        Def(nombre: "Sacha inchi", categoria: "Despensa", claves: ["sacha inchi"]),
        Def(nombre: "Nueces", categoria: "Despensa", claves: ["nueces"]),
        Def(nombre: "Lúcuma (pulpa)", categoria: "Despensa", claves: ["pulpa de lúcuma", "lúcuma"]),
        Def(nombre: "Harina de garbanzo", categoria: "Despensa", claves: ["harina de garbanzo"]),
        Def(nombre: "Pepitas de zambo", categoria: "Despensa", claves: ["pepitas de zambo"]),
        Def(nombre: "Mazamorra morada (o maíz morado)", categoria: "Despensa", claves: ["mazamorra morada"]),
        Def(nombre: "Humitas (sin queso)", categoria: "Otros", claves: ["humitas"]),
    ]

    private static let ignorar = ["agua o mate", "café o emoliente", "agua"]
    private static let palabrasMedida = ["cdas", "cda", "cdtas", "cdta", "tazas", "taza", "pizca", "chorrito", "puñado", "vaso", "trozo"]

    /// (clave, índice de def) ordenadas de más larga a más corta.
    private static let clavesOrdenadas: [(String, Int)] = {
        var out: [(String, Int)] = []
        for (i, d) in defs.enumerated() {
            for c in d.claves { out.append((c, i)) }
        }
        return out.sorted { $0.0.count > $1.0.count }
    }()

    /// Busca `clave` como palabra completa dentro de `texto`.
    private static func rangoPalabra(_ clave: String, en texto: String) -> Range<String.Index>? {
        var desde = texto.startIndex
        while desde < texto.endIndex,
              let r = texto.range(of: clave, range: desde..<texto.endIndex) {
            let antesOK = r.lowerBound == texto.startIndex
                || !texto[texto.index(before: r.lowerBound)].isLetter
            let despuesOK = r.upperBound == texto.endIndex || !texto[r.upperBound].isLetter
            if antesOK && despuesOK { return r }
            desde = r.upperBound
        }
        return nil
    }

    static func generar(dias: [DiaProyectado]) -> [(categoria: String, items: [ItemCompra])] {
        var items: [String: ItemCompra] = [:]

        for dia in dias {
            for meal in dia.meals {
                for linea in meal.recipe.ingredientes {
                    procesar(linea, porciones: meal.porciones, en: &items)
                }
            }
        }

        var porCategoria: [String: [ItemCompra]] = [:]
        for item in items.values {
            porCategoria[item.categoria, default: []].append(item)
        }
        return ordenCategorias.compactMap { cat in
            guard var lista = porCategoria[cat], !lista.isEmpty else { return nil }
            lista.sort { ($0.comidas, $0.nombre) > ($1.comidas, $1.nombre) }
            return (cat, lista)
        }
    }

    private static func procesar(_ linea: String, porciones: Double, en items: inout [String: ItemCompra]) {
        var texto = linea.lowercased()
        for ig in ignorar {
            if let r = rangoPalabra(ig, en: texto) { texto.replaceSubrange(r, with: "■") }
        }

        // Cantidad: "250 g", "400 ml", "1.5 kg" en cualquier parte de la línea.
        var gramos = 0.0, ml = 0.0, unidades = 0.0
        if let m = try? NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l)(?![a-záéíóúñ])"#)
            .firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)),
           let rNum = Range(m.range(at: 1), in: texto),
           let rUni = Range(m.range(at: 2), in: texto),
           let valor = Double(texto[rNum].replacingOccurrences(of: ",", with: ".")) {
            switch texto[rUni] {
            case "kg": gramos = valor * 1000
            case "g": gramos = valor
            case "l": ml = valor * 1000
            default: ml = valor
            }
        } else if !palabrasMedida.contains(where: { rangoPalabra($0, en: texto) != nil }),
                  let m = try? NSRegularExpression(pattern: #"^\s*(\d+)(?![\d/])\s"#)
                      .firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)),
                  let rNum = Range(m.range(at: 1), in: texto),
                  let valor = Double(texto[rNum]) {
            unidades = valor
        }

        var encontrados: [Int] = []
        for (clave, i) in clavesOrdenadas {
            while let r = rangoPalabra(clave, en: texto) {
                if !encontrados.contains(where: { defs[$0].nombre == defs[i].nombre }) {
                    encontrados.append(i)
                }
                texto.replaceSubrange(r, with: "■")
            }
        }

        if encontrados.isEmpty {
            let limpio = linea.trimmingCharacters(in: .whitespaces)
            guard texto.contains(where: \.isLetter) else { return }
            var it = items[limpio] ?? ItemCompra(nombre: limpio, categoria: "Otros")
            it.comidas += 1
            items[limpio] = it
            return
        }

        let soloUno = encontrados.count == 1
        for i in encontrados {
            let def = defs[i]
            var it = items[def.nombre] ?? ItemCompra(nombre: def.nombre, categoria: def.categoria)
            it.comidas += 1
            if soloUno {
                it.gramos += gramos * porciones
                it.mililitros += ml * porciones
                it.unidades += unidades * porciones
            }
            items[def.nombre] = it
        }
    }

    // MARK: Texto para copiar

    static func textoParaCopiar(dias: [DiaProyectado], lista: [(categoria: String, items: [ItemCompra])]) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "EEE d MMM"

        var out = "LISTA DE COMPRAS — Recarga\n"
        if let primero = dias.first, let ultimo = dias.last {
            out += "Semana del \(f.string(from: primero.fecha)) al \(f.string(from: ultimo.fecha))\n"
        }
        for (cat, items) in lista {
            out += "\n\(cat.uppercased())\n"
            for it in items {
                out += "• \(it.nombre) — \(it.detalle)\n"
            }
        }
        out += "\nMENÚ DE LA SEMANA\n"
        for dia in dias {
            out += "\n\(f.string(from: dia.fecha).capitalized) · \(dia.tipo.label)\n"
            for m in dia.meals {
                out += "  \(m.slot.label): \(m.recipe.nombre)\n"
            }
        }
        return out
    }
}
