# Recarga 🏃‍♂️🌱

App nativa de macOS que te dice **qué comer hoy** (desayuno, almuerzo, cena y snacks) según tu entrenamiento de corredor — vegana y con recetario peruano. Se conecta a **Strava** para leer tus entrenos reales y ajusta las comidas al desgaste del día y a lo que toca mañana.

## Cómo funciona

1. **Tu plantilla semanal** (Ajustes → Semana) dice qué toca cada día: rodaje suave, series, fondo, descanso o carga pre-maratón. Strava sabe lo que *ya corriste*; la plantilla sabe lo que *viene* — con ambas, la cena de hoy se adelanta al fondo de mañana.
2. **El motor de nutrición** calcula los objetivos del día: BMR (Mifflin-St Jeor) + gasto del entreno (calorías de Strava, o ~1 kcal × kg × km si no hay dato). Carbohidratos periodizados por tipo de día (descanso 4 g/kg → fondo 9 g/kg → carga 11 g/kg), proteína 1.8–2.0 g/kg repartida en 4–5 tomas, grasa con piso de 0.8 g/kg. Reglas de los position stands ISSN/ACSM.
3. **El planificador** elige del recetario (55 platos veganos peruanos etiquetados con macros) la combinación que cubre cada comida, escala porciones, evita repetir lo de los últimos 3 días y cuida el checklist vegano-runner: hierro + vitamina C, omega-3 (sacha inchi, chía), calcio y recordatorio de B12.

El día está pensado para quien entrena de madrugada: pre-entreno ligero ~4:15 am, desayuno como comida de recuperación al volver, y cena que carga glucógeno si mañana hay fondo.

## Conectar Strava (una sola vez, ~5 min)

1. Entra a <https://www.strava.com/settings/api> y crea tu app personal:
   - **Application Name**: Recarga (o lo que quieras)
   - **Category**: Training
   - **Authorization Callback Domain**: `localhost`
2. Copia el **Client ID** y el **Client Secret**.
3. En Recarga: ⚙︎ → Strava → pega ambos → "Conectar con Strava" → autoriza en el navegador.

Los tokens quedan solo en tu Mac (`~/Library/Application Support/Recarga/`, permisos 0600). Con suscripción de pago de Strava el acceso a la API está incluido. La app usa ~10–20 requests/día de los 2,000 permitidos.

## Build y uso

```bash
./build.sh                  # compila build/Recarga.app
./build.sh release test     # compila y corre el selftest del motor (sin UI)
./build.sh release run      # compila y abre la app
./build.sh release install  # instala en /Applications
```

Compila con `swiftc` directo + SDK de macOS 15.5 (el SwiftPM de los CLT de esta máquina está roto — mismo patrón que Dicta). Requiere macOS 14+, Apple Silicon.

## Estructura

```
Sources/Core/    # portable a iOS: modelos, motor, planificador, cliente Strava
Sources/App/     # UI SwiftUI de macOS
Resources/       # recipes.json — el recetario (55 platos, macros por porción)
Support/         # Info.plist
```

`Sources/Core` no importa AppKit/SwiftUI: para la versión iOS solo hay que escribir pantallas nuevas.

## Roadmap

- **Fase 2**: lista de compras semanal, vista de la semana (carga vs ingesta), detección automática post-entreno, editor de recetas.
- **Fase 3**: menús generativos con la API de Claude, asistente de carb-loading de semana de maratón, hidratación/sodio para fondos con calor, port a iOS (requiere Xcode), notificaciones de ventana de recuperación.

## Nota

Recarga orienta, no prescribe: no reemplaza a un nutricionista deportivo ni consejo médico. Los tokens de Strava y tus datos nunca salen de tu Mac.
