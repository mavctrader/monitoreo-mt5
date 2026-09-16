"""Agente del Centro de Monitoreo MT5.

Corre en la VPS. Lee la carpeta Common (donde el EA recolector deja el
estado de cada cuenta) y la sincroniza con Supabase; en sentido
contrario, baja las órdenes (parar / arrancar / descargar) que vengan
del panel. Vigila los límites de prop firm cada segundo, en el propio
proceso, sin subir nada a Supabase hasta que algo cruce un límite.

Contrato de archivos en Common\\Files\\MonitoreoMT5\\ (todos UTF-8):

  Escribe el EA recolector, lee este agente:
    estado_<login>.json          saldo, equity, flotante, margen, algo_trading
    posiciones_<login>.json      {"posiciones": [...]}
    operaciones_<login>.jsonl    una operación cerrada por línea (JSON)
    graficos_<login>.json        {"graficos": [{"grafico_id",...}]}
    ordenes_hechas_<login>.txt   ids de órdenes DESCARGAR ya ejecutadas

  Escribe este agente, lee el EA recolector:
    ordenes_pendientes_<login>.txt   líneas "id|grafico_id" (DESCARGAR)

  Escribe este agente, lee el interruptor de cada bot (Interruptor.mqh):
    interruptor_<login>_<grafico_id>.json   {"estado": "parado"|"arrancado"}

  Escribe el interruptor, lee este agente:
    bot_estado_<login>_<grafico_id>.json    {"confirmado": "..."}
"""

import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from supabase import Client, create_client

# Bajo pythonw.exe (sin consola) sys.stdout/stderr son None y print()
# rompe. Se redirige a un log propio; corriendo con python.exe normal
# (consola visible) esto no se activa y los prints se ven en pantalla.
if sys.stdout is None:
    _log = open(Path(__file__).resolve().parent / "agente.log", "a", encoding="utf-8", buffering=1)
    sys.stdout = _log
    sys.stderr = _log

load_dotenv()

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_ANON_KEY = os.environ["SUPABASE_ANON_KEY"]
AGENTE_EMAIL = os.environ["AGENTE_EMAIL"]
AGENTE_PASSWORD = os.environ["AGENTE_PASSWORD"]

COMUN = Path(os.environ.get(
    "COMMON_PATH",
    Path(os.environ["APPDATA"]) / "MetaQuotes" / "Terminal" / "Common" / "Files" / "MonitoreoMT5",
))

INTERVALO_VIGILANCIA = 1   # segundos: límites de prop firm, local
INTERVALO_ORDENES = 5      # segundos: entregar/confirmar parar-arrancar-descargar
INTERVALO_DATOS = 60       # segundos: estado, posiciones, operaciones, bots, reglas

PATRON_BOT_ESTADO = re.compile(r"bot_estado_(\d+)_(-?\d+)\.json$")


# --------------------------------------------------------------------
# Utilidades de archivo
# --------------------------------------------------------------------

def leer_json(archivo: Path):
    if not archivo.exists():
        return None
    try:
        return json.loads(archivo.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def escribir_json(archivo: Path, datos: dict):
    archivo.parent.mkdir(parents=True, exist_ok=True)
    archivo.write_text(json.dumps(datos, ensure_ascii=False), encoding="utf-8")


def agregar_linea(archivo: Path, linea: str):
    archivo.parent.mkdir(parents=True, exist_ok=True)
    with archivo.open("a", encoding="utf-8") as f:
        f.write(linea + "\n")


def logins_detectados():
    logins = set()
    for archivo in COMUN.glob("estado_*.json"):
        login = archivo.stem.replace("estado_", "")
        if login.isdigit():
            logins.add(login)
    return sorted(logins)


# --------------------------------------------------------------------
# Conexión
# --------------------------------------------------------------------

def conectar() -> Client:
    cliente = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    cliente.auth.sign_in_with_password({"email": AGENTE_EMAIL, "password": AGENTE_PASSWORD})
    return cliente


# --------------------------------------------------------------------
# Alta de cuentas y sincronización de datos (cada minuto)
# --------------------------------------------------------------------

def id_cuenta(cliente: Client, login: str, broker: str) -> str:
    """Devuelve el id de la cuenta, dándola de alta la primera vez que se ve."""
    existente = cliente.table("cuentas").select("id").eq("login", int(login)).limit(1).execute()
    if existente.data:
        return existente.data[0]["id"]
    creada = cliente.table("cuentas").insert({"login": int(login), "broker": broker}).execute()
    return creada.data[0]["id"]


# cuenta_id -> (equity_inicio_dia, limite_del_dia_en_utc). Se siembra al
# arrancar leyendo lo que ya había en Supabase, para no perder el punto de
# referencia del día si el agente se reinicia a mitad de jornada.
cache_inicio_dia: dict = {}


def sembrar_cache_inicio_dia(cliente: Client):
    filas = cliente.table("estado").select("cuenta_id,equity_inicio_dia,equity_inicio_dia_en").execute()
    for f in filas.data:
        if f["equity_inicio_dia"] is not None and f["equity_inicio_dia_en"] is not None:
            cache_inicio_dia[f["cuenta_id"]] = (
                f["equity_inicio_dia"],
                datetime.fromisoformat(f["equity_inicio_dia_en"]),
            )


def zona_de(nombre):
    """UTC no pasa por zoneinfo: Windows no trae la base de zonas horarias
    (sin el paquete tzdata, ZoneInfo('UTC') revienta)."""
    if not nombre or nombre.strip().upper() == "UTC":
        return timezone.utc
    try:
        return ZoneInfo(nombre)
    except Exception:
        print(f"[zona] '{nombre}' no disponible, se usa UTC")
        return timezone.utc


def limite_dia_actual(ahora_utc: datetime, hora_reset, zona_horaria) -> datetime:
    """Última hora de reset ya cruzada, en UTC. Sin reglas, asume 00:00 UTC."""
    ahora_local = ahora_utc.astimezone(zona_de(zona_horaria))
    if hora_reset:
        h, m = (int(x) for x in str(hora_reset).split(":")[:2])
    else:
        h, m = 0, 0
    limite_local = ahora_local.replace(hour=h, minute=m, second=0, microsecond=0)
    if ahora_local < limite_local:
        limite_local -= timedelta(days=1)
    return limite_local.astimezone(timezone.utc)


def actualizar_inicio_dia(cuenta_id: str, equity: float, reglas):
    """Devuelve (equity_inicio_dia, limite) vigente, actualizando la caché
    si se cruzó una nueva hora de reset desde la última vez."""
    ahora = datetime.now(timezone.utc)
    hora_reset = reglas.get("hora_reset") if reglas else None
    zona = reglas.get("zona_horaria") if reglas else None
    limite = limite_dia_actual(ahora, hora_reset, zona)

    anterior = cache_inicio_dia.get(cuenta_id)
    if anterior is None or anterior[1] < limite:
        cache_inicio_dia[cuenta_id] = (equity, limite)
        return equity, limite
    return anterior


def subir_estado(cliente: Client, cuenta_id: str, estado: dict, reglas=None):
    equity = estado.get("equity")
    equity_inicio_dia, limite = (None, None)
    if equity is not None:
        equity_inicio_dia, limite = actualizar_inicio_dia(cuenta_id, equity, reglas)

    cliente.table("estado").upsert({
        "cuenta_id": cuenta_id,
        "saldo": estado.get("saldo"),
        "equity": equity,
        "flotante": estado.get("flotante"),
        "margen_libre": estado.get("margen_libre"),
        "algo_trading": estado.get("algo_trading"),
        "visto_en": estado.get("visto_en"),
        "equity_inicio_dia": equity_inicio_dia,
        "equity_inicio_dia_en": limite.isoformat() if limite else None,
    }, on_conflict="cuenta_id").execute()


def sincronizar_posiciones(cliente: Client, cuenta_id: str, login: str):
    datos = leer_json(COMUN / f"posiciones_{login}.json")
    if datos is None:
        return
    cliente.table("posiciones").delete().eq("cuenta_id", cuenta_id).execute()
    filas = [
        {
            "cuenta_id": cuenta_id,
            "ticket": p["ticket"],
            "simbolo": p.get("simbolo"),
            "tipo": p.get("tipo"),
            "volumen": p.get("volumen"),
            "apertura": p.get("apertura"),
            "sl": p.get("sl"),
            "tp": p.get("tp"),
            "beneficio": p.get("beneficio"),
            "abierta_en": p.get("abierta_en"),
        }
        for p in datos.get("posiciones", [])
    ]
    if filas:
        cliente.table("posiciones").insert(filas).execute()


def sincronizar_operaciones(cliente: Client, cuenta_id: str, login: str):
    archivo = COMUN / f"operaciones_{login}.jsonl"
    if not archivo.exists():
        return
    filas = []
    for linea in archivo.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea:
            continue
        try:
            op = json.loads(linea)
        except json.JSONDecodeError:
            continue
        filas.append({
            "cuenta_id": cuenta_id,
            "ticket": op["ticket"],
            "simbolo": op.get("simbolo"),
            "tipo": op.get("tipo"),
            "volumen": op.get("volumen"),
            "entrada": op.get("entrada"),
            "salida": op.get("salida"),
            "beneficio": op.get("beneficio"),
            "comision": op.get("comision"),
            "abierta_en": op.get("abierta_en"),
            "cerrada_en": op.get("cerrada_en"),
        })
    if not filas:
        return
    cliente.table("operaciones").upsert(
        filas, on_conflict="cuenta_id,ticket", ignore_duplicates=True
    ).execute()
    archivo.unlink()  # el EA solo agrega; el agente vacía el archivo tras subirlo


def sincronizar_bots(cliente: Client, cuenta_id: str, login: str):
    datos = leer_json(COMUN / f"graficos_{login}.json")
    if datos is None:
        return
    filas = [
        {
            "cuenta_id": cuenta_id,
            "grafico_id": g["grafico_id"],
            "simbolo": g.get("simbolo"),
            "periodo": g.get("periodo"),
            "nombre": (cache_plantillas.get(g.get("grafico_id")) or {}).get("nombre_ea"),
        }
        for g in datos.get("graficos", [])
    ]
    if filas:
        cliente.table("bots").upsert(filas, on_conflict="cuenta_id,grafico_id").execute()


# cuenta_id -> (rol, grupo, simbolo) ya escrito, para no repetir el update.
cache_pares: dict = {}

# grafico_id -> datos del EA leídos de su plantilla. Se conservan aunque la
# plantilla se borre, hasta que el recolector la vuelva a escribir.
cache_plantillas: dict = {}

CARPETA_TERMINALES = Path(os.environ["APPDATA"]) / "MetaQuotes" / "Terminal"
PATRON_TPL = re.compile(r"MonitoreoMT5_tpl_(\d+)\.tpl$", re.IGNORECASE)
PATRON_SIMBOLO = re.compile(r"[A-Za-z0-9._,:]{1,40}$")
PATRON_MAPEO = re.compile(r"[A-Za-z0-9._]{2,20}:[A-Za-z0-9._]{2,20}$")


def grupo_desde_canal(canal):
    """'master.json1' -> 'Master 1'. Sin número, 'Master'."""
    m = re.search(r"master\.json(\d*)\s*$", canal or "", re.IGNORECASE)
    if not m:
        return None
    numero = m.group(1)
    return f"Master {numero}" if numero else "Master"


def leer_texto_plantilla(ruta: Path):
    """MT5 guarda las plantillas en UTF-16; algunas builds en UTF-8."""
    datos = ruta.read_bytes()
    if datos[:2] in (b"\xff\xfe", b"\xfe\xff"):
        texto = datos.decode("utf-16", errors="ignore")
    else:
        texto = datos.decode("utf-8", errors="ignore")
    return texto.replace("\x00", "")


def parsear_plantilla(ruta: Path):
    """Del archivo de plantilla saca SOLO el nombre del EA, el archivo de
    canal (master.jsonN) y el símbolo que opera. El resto de los parámetros
    del EA -contraseñas incluidas- no se lee ni se guarda en ningún lado."""
    try:
        texto = leer_texto_plantilla(ruta)
    except OSError:
        return None

    dentro = False
    nombre = canal = simbolo = mapeo = None
    anterior = ""
    for linea in texto.splitlines():
        linea = linea.strip()
        if "<expert>" in linea:
            dentro = True
            continue
        if "</expert>" in linea:
            break
        if not dentro:
            continue

        # El nombre del EA viene como path=Experts\Hobbiecode_CT_Master.ex5
        if nombre is None and linea.startswith("path="):
            nombre = linea.split("\\")[-1].rsplit(".", 1)[0]

        valor = linea.split("=", 1)[1].strip() if "=" in linea else ""

        # El mapeo del slave ("NDX100:NAS100.x") es inconfundible por su forma.
        if mapeo is None and PATRON_MAPEO.match(valor):
            mapeo = valor.split(":")[-1]

        pos = linea.find("master.json")
        if canal is None and pos >= 0:
            canal = linea[pos:].strip()
            # En el master el símbolo va en el parámetro justo anterior.
            previo = anterior.split("=", 1)[1].strip() if "=" in anterior else ""
            if PATRON_SIMBOLO.match(previo):
                simbolo = previo.split(":")[-1]

        anterior = linea

    if not nombre and not canal:
        return None
    return {
        "nombre_ea": nombre or "",
        "canal": canal or "",
        "simbolo_operado": mapeo or simbolo or "",
    }


def leer_plantillas():
    """Recorre las plantillas que dejó el recolector en todos los terminales,
    las interpreta y las borra (el recolector las vuelve a escribir)."""
    for ruta in CARPETA_TERMINALES.glob("*/MQL5/Profiles/Templates/MonitoreoMT5_tpl_*.tpl"):
        m = PATRON_TPL.search(ruta.name)
        if not m:
            continue
        datos = parsear_plantilla(ruta)
        if datos:
            cache_plantillas[int(m.group(1))] = datos
        try:
            ruta.unlink()
        except OSError:
            pass


def sincronizar_par(cliente: Client, cuenta_id: str, login: str):
    """Arma y desarma el par master/slave siguiendo lo que hay en el MT5: el
    recolector reporta qué EA tiene cada gráfico y a qué archivo master.jsonN
    apunta, y las dos puntas del par comparten ese archivo. Si se retiran los
    EAs de copia, el par se deshace."""
    datos = leer_json(COMUN / f"graficos_{login}.json")
    if not datos or not datos.get("graficos"):
        return  # sin inventario de gráficos no se concluye nada

    rol = grupo = simbolo = None
    for g in datos["graficos"]:
        ea = cache_plantillas.get(g.get("grafico_id"))
        if not ea:
            continue
        posible = grupo_desde_canal(ea["canal"])
        if not posible:
            continue
        nombre = ea["nombre_ea"].lower()
        if "slave" in nombre:
            rol, grupo = "slave", posible
        elif "master" in nombre:
            rol, grupo = "master", posible
        else:
            continue
        simbolo = ea["simbolo_operado"] or None
        break

    if cache_pares.get(cuenta_id) == (rol, grupo, simbolo):
        return

    cambios = {"rol": rol, "grupo": grupo}
    if simbolo:
        cambios["simbolo_principal"] = simbolo
    cliente.table("cuentas").update(cambios).eq("id", cuenta_id).execute()
    cache_pares[cuenta_id] = (rol, grupo, simbolo)
    print(f"[par] cuenta {login}: {rol or 'sin par'} {grupo or ''} {simbolo or ''}".strip())


def sincronizar_datos(cliente: Client, cache_cuentas: dict, cache_reglas: dict):
    leer_plantillas()
    for login in logins_detectados():
        estado = leer_json(COMUN / f"estado_{login}.json")
        if estado is None:
            continue

        if login not in cache_cuentas:
            cache_cuentas[login] = id_cuenta(cliente, login, estado.get("broker", ""))
        cuenta_id = cache_cuentas[login]

        subir_estado(cliente, cuenta_id, estado, cache_reglas.get(cuenta_id))
        sincronizar_posiciones(cliente, cuenta_id, login)
        sincronizar_operaciones(cliente, cuenta_id, login)
        sincronizar_bots(cliente, cuenta_id, login)
        sincronizar_par(cliente, cuenta_id, login)


def leer_reglas(cliente: Client, cache_cuentas: dict) -> dict:
    if not cache_cuentas:
        return {}
    filas = cliente.table("reglas").select("*").in_("cuenta_id", list(cache_cuentas.values())).execute()
    return {f["cuenta_id"]: f for f in filas.data}


# --------------------------------------------------------------------
# Órdenes: parar / arrancar / descargar (cada 5 segundos)
# --------------------------------------------------------------------

def procesar_ordenes(cliente: Client, cache_cuentas: dict):
    pendientes = (
        cliente.table("ordenes")
        .select("id,tipo,bots(grafico_id),cuentas(login)")
        .eq("estado", "pendiente")
        .execute()
    )

    for orden in pendientes.data:
        cuenta = orden.get("cuentas")
        bot = orden.get("bots")
        if not cuenta or not bot:
            continue
        login = str(cuenta["login"])
        grafico_id = bot["grafico_id"]

        if orden["tipo"] == "DESCARGAR":
            agregar_linea(COMUN / f"ordenes_pendientes_{login}.txt", f'{orden["id"]}|{grafico_id}')
        else:  # PARAR o ARRANCAR
            estado_interruptor = "parado" if orden["tipo"] == "PARAR" else "arrancado"
            escribir_json(COMUN / f"interruptor_{login}_{grafico_id}.json", {"estado": estado_interruptor})

        cliente.table("ordenes").update({
            "estado": "entregada",
            "entregada_en": datetime.now(timezone.utc).isoformat(),
        }).eq("id", orden["id"]).execute()

    confirmar_descargas(cliente)
    confirmar_interruptores(cliente, cache_cuentas)


def confirmar_descargas(cliente: Client):
    for archivo in COMUN.glob("ordenes_hechas_*.txt"):
        ids = [l.strip() for l in archivo.read_text(encoding="utf-8").splitlines() if l.strip()]
        for id_orden in ids:
            cliente.table("ordenes").update({
                "estado": "hecha",
                "hecha_en": datetime.now(timezone.utc).isoformat(),
            }).eq("id", id_orden).execute()
        if ids:
            archivo.unlink()


def confirmar_interruptores(cliente: Client, cache_cuentas: dict):
    for archivo in COMUN.glob("bot_estado_*.json"):
        m = PATRON_BOT_ESTADO.search(archivo.name)
        if not m:
            continue
        login, grafico_id = m.group(1), int(m.group(2))
        cuenta_id = cache_cuentas.get(login)
        datos = leer_json(archivo)
        if not datos or not cuenta_id:
            continue
        cliente.table("bots").update({
            "confirmado": datos.get("confirmado"),
            "confirmado_en": datetime.now(timezone.utc).isoformat(),
        }).eq("cuenta_id", cuenta_id).eq("grafico_id", grafico_id).execute()

        confirmado = datos.get("confirmado")
        if confirmado in ("parado", "arrancado"):
            tipo_orden = "PARAR" if confirmado == "parado" else "ARRANCAR"
            cliente.table("ordenes").update({
                "estado": "hecha",
                "hecha_en": datetime.now(timezone.utc).isoformat(),
            }).eq("cuenta_id", cuenta_id).eq("tipo", tipo_orden).eq("estado", "entregada").execute()


# --------------------------------------------------------------------
# Vigilancia de límites (cada segundo, local, sin salir a internet)
# --------------------------------------------------------------------

def vigilar_limites(cliente: Client, cache_cuentas: dict, cache_reglas: dict, cruzados: dict):
    for login, cuenta_id in cache_cuentas.items():
        reglas = cache_reglas.get(cuenta_id)
        if not reglas:
            continue
        estado = leer_json(COMUN / f"estado_{login}.json")
        if not estado or estado.get("equity") is None:
            continue

        equity = estado["equity"]
        saldo_inicial = reglas.get("saldo_inicial")
        drawdown_max = reglas.get("drawdown_max")

        # Pérdida diaria (perdida_diaria_max) queda pendiente: depende de la
        # hora de reset de cada prop firm, que el diseño todavía no define
        # (ver docs/, sección "Por decidir"). Se agrega cuando se resuelva.

        if not saldo_inicial or not drawdown_max:
            continue

        cruzo = (saldo_inicial - equity) >= drawdown_max
        ya_avisado = cruzados.get(cuenta_id, False)

        if cruzo and not ya_avisado:
            subir_estado(cliente, cuenta_id, estado, reglas)
            cruzados[cuenta_id] = True
        elif not cruzo and ya_avisado:
            cruzados[cuenta_id] = False


# --------------------------------------------------------------------
# Bucle principal
# --------------------------------------------------------------------

def principal():
    cliente = conectar()
    cache_cuentas: dict = {}
    cache_reglas: dict = {}
    cruzados: dict = {}

    sembrar_cache_inicio_dia(cliente)

    t_datos = t_ordenes = 0.0

    print(f"Agente conectado. Leyendo {COMUN}")

    while True:
        ahora = time.monotonic()

        if ahora - t_datos >= INTERVALO_DATOS:
            try:
                sincronizar_datos(cliente, cache_cuentas, cache_reglas)
                cache_reglas = leer_reglas(cliente, cache_cuentas)
            except Exception as e:
                print(f"[datos] error: {e}")
            t_datos = ahora

        if ahora - t_ordenes >= INTERVALO_ORDENES:
            try:
                procesar_ordenes(cliente, cache_cuentas)
            except Exception as e:
                print(f"[ordenes] error: {e}")
            t_ordenes = ahora

        try:
            vigilar_limites(cliente, cache_cuentas, cache_reglas, cruzados)
        except Exception as e:
            print(f"[vigilancia] error: {e}")

        time.sleep(INTERVALO_VIGILANCIA)


if __name__ == "__main__":
    principal()
