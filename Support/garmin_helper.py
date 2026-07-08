#!/usr/bin/env python3
"""Helper de Recarga para Garmin Connect (API no oficial vía garminconnect/garth).

Uso:
  garmin_helper.py <tokens_dir> login          # stdin: email\npassword\nmfa(opcional)\n
  garmin_helper.py <tokens_dir> fetch [dias]   # imprime JSON de entrenos programados

El login guarda tokens (~1 año) en tokens_dir; las credenciales van solo a
Garmin y no se almacenan. fetch lee el calendario de Garmin Connect y devuelve
los entrenamientos PROGRAMADOS (los que TrainingPeaks empuja al reloj).
"""
import datetime
import json
import sys
import warnings

warnings.filterwarnings("ignore")


def fallar(msg, codigo=1):
    print(json.dumps({"error": str(msg)[:400]}))
    sys.exit(codigo)


def main():
    if len(sys.argv) < 3:
        fallar("uso: garmin_helper.py <tokens_dir> <login|fetch> [dias]")
    tokens_dir, cmd = sys.argv[1], sys.argv[2]

    try:
        from garminconnect import Garmin
    except Exception as e:
        fallar(f"garminconnect no está instalado en el venv: {e}")

    if cmd == "login":
        email = sys.stdin.readline().strip()
        password = sys.stdin.readline().strip()
        # Si la cuenta tiene MFA, garth pide el código con input(), que lee
        # la tercera línea de stdin.
        try:
            g = Garmin(email=email, password=password)
            g.login()
            g.garth.dump(tokens_dir)
        except Exception as e:
            texto = str(e) or type(e).__name__
            if "mfa" in texto.lower() or "code" in texto.lower():
                fallar(f"Garmin pidió código MFA: {texto}", 42)
            fallar(f"No pude iniciar sesión en Garmin: {texto}")
        nombre = None
        try:
            nombre = g.get_full_name()
        except Exception:
            pass
        print(json.dumps({"ok": True, "nombre": nombre}))
        return

    if cmd == "fetch":
        dias = int(sys.argv[3]) if len(sys.argv) > 3 else 14
        try:
            g = Garmin()
            g.login(tokens_dir)
        except Exception as e:
            fallar(f"Sesión de Garmin expirada o inválida — reconecta en Ajustes: {e}")

        hoy = datetime.date.today()
        fin = hoy + datetime.timedelta(days=dias)

        # El índice de mes del calendar-service es 0-based; pedimos meses de
        # sobra y filtramos por fecha para no depender del indexado.
        meses = set()
        for delta_mes in (0, 1):
            y, m = hoy.year, hoy.month - 1 + delta_mes
            y2, m2 = fin.year, fin.month - 1 + delta_mes
            for yy, mm in ((y, m - 1), (y, m), (y2, m2 - 1), (y2, m2)):
                if mm < 0:
                    yy, mm = yy - 1, mm + 12
                if mm > 11:
                    yy, mm = yy + 1, mm - 12
                meses.add((yy, mm))

        items = []
        for (y, m) in sorted(meses):
            try:
                data = g.connectapi(f"/calendar-service/year/{y}/month/{m}") or {}
                items += data.get("calendarItems") or []
            except Exception:
                continue

        vistos = set()
        out = []
        for it in items:
            if it.get("itemType") != "workout":
                continue
            fecha = it.get("date") or ""
            if not (hoy.isoformat() <= fecha <= fin.isoformat()):
                continue
            wid = it.get("workoutId")
            clave = (fecha, wid, it.get("title"))
            if clave in vistos:
                continue
            vistos.add(clave)

            det = {}
            if wid and len(out) < 14:
                try:
                    det = g.connectapi(f"/workout-service/workout/{wid}") or {}
                except Exception:
                    det = {}

            deporte = (
                ((det.get("sportType") or {}).get("sportTypeKey"))
                or it.get("sportTypeKey")
                or ""
            )
            intervalos = False
            for seg in det.get("workoutSegments") or []:
                for paso in seg.get("workoutSteps") or []:
                    tipo_paso = (paso.get("stepType") or {}).get("stepTypeKey", "")
                    if (
                        paso.get("type") == "RepeatGroupDTO"
                        or tipo_paso == "repeat"
                        or (paso.get("numberOfIterations") or 0) > 1
                    ):
                        intervalos = True

            out.append({
                "fecha": fecha,
                "titulo": it.get("title") or det.get("workoutName") or "Entrenamiento",
                "deporte": deporte,
                "duracionSeg": det.get("estimatedDurationInSecs"),
                "distanciaM": det.get("estimatedDistanceInMeters"),
                "intervalos": intervalos,
            })

        print(json.dumps(out))
        return

    fallar(f"comando desconocido: {cmd}")


if __name__ == "__main__":
    main()
