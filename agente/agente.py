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

_print_original = print


def print(*args, **kwargs):  # noqa: A001 - se reemplaza a propósito
    """Todo lo que se registre lleva fecha y hora: sin eso no se puede saber
    si una línea del log es de recién o de hace días."""
    marca = datetime.now().strftime("%d/%m %H:%M:%S")
    _print_original(marca, *args, **kwargs)


load_dotenv()

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_ANON_KEY = os.environ["SUPABASE_ANON_KEY"]
AGENTE_EMAIL = os.environ["AGENTE_EMAIL"]
AGENTE_PASSWORD = os.environ["AGENTE_PASSWORD"]

COMUN = Path(os.environ.get(
    "COMMON_PATH",
    Path(os.environ["APPDATA"]) / "MetaQuotes" / "Terminal" / "Common" / "Files" / "MonitoreoMT5",
))

# Nombre corto de esta máquina, que se antepone al nombre de cada par.
#
# El código de correspondencia del copiador identifica un par dentro de UN
# terminal, no entre máquinas: dos VPS pueden tener las dos un "código 1" y
# entonces los dos pares se llamarían igual y el panel los mezclaría en un
# solo cuadro. Pasó. Lo mismo vale para el master.jsonN del copiador viejo.
#
# Vacío por defecto: una instalación que no lo configure se comporta igual
# que antes.
PREFIJO_PARES = os.environ.get("PREFIJO_PARES", "")

# Un archivo del recolector que no se actualiza hace este rato no es una
# cuenta conectada: es lo que quedó cuando la sacaron del terminal. Se borra.
# Generoso a propósito: un reinicio de la VPS o un MT5 que tarda en levantar
# no tienen que disparar la limpieza, y si se borra de más no se pierde nada
# -el recolector reescribe esos archivos enteros cada pocos segundos.
MINUTOS_ARCHIVO_MUERTO = int(os.environ.get("MINUTOS_ARCHIVO_MUERTO", "30"))

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


def archivo_vivo(archivo: Path) -> bool:
    """Si el recolector lo tocó hace poco, la cuenta está conectada acá."""
    try:
        return (time.time() - archivo.stat().st_mtime) < MINUTOS_ARCHIVO_MUERTO * 60
    except OSError:
        return False


def limpiar_archivos_muertos():
    """Borra los retratos que dejó una cuenta que ya no está en el terminal.

    El recolector escribe estado_<cuenta>.json mientras la cuenta está
    logueada; al sacarla deja de escribirlo, pero el archivo queda con los
    últimos valores. El agente lo leía igual y subía ese retrato viejo cada
    minuto. Si además esa cuenta se mudó a otra VPS, los dos agentes escriben
    sobre la misma fila y se pisan: una consulta daba un saldo y la siguiente
    otro. Pasó con una cuenta de FTMO.

    Solo se borran los tres archivos que son fotos del momento y se reescriben
    enteros cada pocos segundos. Los .jsonl de operaciones y movimientos NO se
    tocan: son histórico que puede estar todavía sin subir."""
    for patron in ("estado_*.json", "posiciones_*.json", "graficos_*.json"):
        for archivo in COMUN.glob(patron):
            if archivo_vivo(archivo):
                continue
            try:
                archivo.unlink()
                print(f"[limpieza] {archivo.name}: sin actualizarse hace más de "
                      f"{MINUTOS_ARCHIVO_MUERTO} min, borrado")
            except OSError as e:
                print(f"[limpieza] no se pudo borrar {archivo.name}: {e}")


def logins_detectados():
    """Las cuentas que algun terminal esta reportando.

    El login 0 se descarta: es lo que devuelve MT5 cuando el terminal no
    tiene ninguna cuenta logueada, y sin este filtro el agente lo daba de
    alta como si fuera una cuenta mas. El recolector tambien lo frena desde
    la version 1.03, pero esto cubre a los terminales que todavia corran una
    anterior.

    Y solo cuentan los archivos vivos: uno que el recolector no toca hace
    rato es el resto de una cuenta que ya se sacó del terminal."""
    logins = set()
    for archivo in COMUN.glob("estado_*.json"):
        login = archivo.stem.replace("estado_", "")
        if login.isdigit() and int(login) != 0 and archivo_vivo(archivo):
            logins.add(login)
    return sorted(logins)


# --------------------------------------------------------------------
# Conexión
# --------------------------------------------------------------------

def conectar() -> Client:
    cliente = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    autenticar(cliente)
    return cliente


def autenticar(cliente: Client):
    cliente.auth.sign_in_with_password({"email": AGENTE_EMAIL, "password": AGENTE_PASSWORD})


def sesion_vencida(error) -> bool:
    """Supabase firma la sesión con un token que vence.

    Cuando vence, TODAS las llamadas fallan con PGRST303 "JWT expired", y
    como el bucle principal atrapa los errores y sigue, el agente queda vivo
    reintentando a ciegas: la tarea de Windows informa "corriendo" y el panel
    se congela sin que nadie se entere. Pasó, y estuvo cinco horas así."""
    texto = str(error)
    return "PGRST303" in texto or "JWT expired" in texto


def renovar_si_vencio(cliente: Client, error) -> bool:
    """Rehace el login si el error fue por token vencido."""
    if not sesion_vencida(error):
        return False
    try:
        autenticar(cliente)
        print("[sesion] token vencido, autenticado de nuevo")
        return True
    except Exception as e:
        print(f"[sesion] no se pudo renovar: {e}")
        return False


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


# cuenta_id -> equity más alto que llegó a tener. Es la referencia del
# drawdown trailing: el piso persigue a ese máximo.
cache_equity_max: dict = {}

# Se apaga solo si Supabase todavía no tiene la columna, para no romper la
# subida del estado por un campo que es opcional.
hay_equity_maximo = True


def sembrar_cache_equity_max(cliente: Client):
    global hay_equity_maximo
    try:
        filas = cliente.table("estado").select("cuenta_id,equity_maximo").execute()
    except Exception:
        hay_equity_maximo = False
        print("[trailing] sin columna 'equity_maximo' todavía")
        return
    for f in filas.data:
        if f.get("equity_maximo") is not None:
            cache_equity_max[f["cuenta_id"]] = float(f["equity_maximo"])


def piso_drawdown(cuenta_id: str, reglas) -> float:
    """Hasta dónde puede caer el equity antes de romper la pérdida máxima.

    Con drawdown estático el piso es fijo: saldo inicial menos el permitido.

    Con trailing el piso persigue al equity más alto alcanzado y no se
    detiene nunca: si la cuenta llegó a 55.000, el piso queda en 52.250
    aunque haya arrancado en 50.000."""
    saldo_inicial = reglas.get("saldo_inicial")
    drawdown_max = reglas.get("drawdown_max")
    if not saldo_inicial or not drawdown_max:
        return None

    piso = saldo_inicial - drawdown_max
    if reglas.get("drawdown_trailing"):
        maximo = cache_equity_max.get(cuenta_id, saldo_inicial)
        piso = maximo - drawdown_max
    return piso


def subir_estado(cliente: Client, cuenta_id: str, estado: dict, reglas=None):
    global hay_equity_maximo
    equity = estado.get("equity")
    equity_inicio_dia, limite = (None, None)
    equity_maximo = None
    if equity is not None:
        equity_inicio_dia, limite = actualizar_inicio_dia(cuenta_id, equity, reglas)
        # El máximo nunca baja: es la marca de agua de la cuenta.
        equity_maximo = max(cache_equity_max.get(cuenta_id, equity), equity)
        cache_equity_max[cuenta_id] = equity_maximo

    fila = {
        "cuenta_id": cuenta_id,
        "saldo": estado.get("saldo"),
        "equity": equity,
        "flotante": estado.get("flotante"),
        "margen_libre": estado.get("margen_libre"),
        "algo_trading": estado.get("algo_trading"),
        "visto_en": estado.get("visto_en"),
        "equity_inicio_dia": equity_inicio_dia,
        "equity_inicio_dia_en": limite.isoformat() if limite else None,
    }
    if hay_equity_maximo:
        fila["equity_maximo"] = equity_maximo

    try:
        cliente.table("estado").upsert(fila, on_conflict="cuenta_id").execute()
    except Exception:
        if not hay_equity_maximo:
            raise
        # La columna todavía no existe: se sigue sin ella.
        hay_equity_maximo = False
        print("[trailing] sin columna 'equity_maximo' todavía")
        fila.pop("equity_maximo", None)
        cliente.table("estado").upsert(fila, on_conflict="cuenta_id").execute()


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
            # Lo escribe el recolector de capital inversor; los otros no lo
            # mandan todavía y queda vacío, que es lo mismo que antes.
            # Que robot abrio la posicion. Solo lo manda el recolector de
            # capital inversor; en los otros queda vacio.
            "magic": p.get("magic"),
            "swap": p.get("swap"),
            "abierta_en": p.get("abierta_en"),
        }
        for p in datos.get("posiciones", [])
        if p.get("ticket") is not None
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
        if op.get("ticket") is None:
            continue  # línea de una versión que no conocemos: se ignora
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
            "swap": op.get("swap"),
            "magic": op.get("magic"),
            "abierta_en": op.get("abierta_en"),
            "cerrada_en": op.get("cerrada_en"),
        })
    if not filas:
        return
    cliente.table("operaciones").upsert(
        filas, on_conflict="cuenta_id,ticket", ignore_duplicates=True
    ).execute()
    archivo.unlink()  # el EA solo agrega; el agente vacía el archivo tras subirlo


def sincronizar_spreads(cliente: Client, cuenta_id: str, login: str):
    """Lo que costó cruzar el spread en cada posición, medido por el
    recolector al abrirse. Solo crece, como las operaciones."""
    archivo = COMUN / f"spreads_{login}.jsonl"
    if not archivo.exists():
        return
    filas = []
    for linea in archivo.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea:
            continue
        try:
            s = json.loads(linea)
        except json.JSONDecodeError:
            continue
        if s.get("ticket") is None:
            continue  # línea de una versión que no conocemos: se ignora
        filas.append({
            "cuenta_id": cuenta_id,
            "ticket": s["ticket"],
            "simbolo": s.get("simbolo"),
            "volumen": s.get("volumen"),
            "magic": s.get("magic"),
            "costo": s.get("costo"),
            "medido_en": s.get("medido_en"),
        })
    if not filas:
        return
    cliente.table("spreads").upsert(
        filas, on_conflict="cuenta_id,ticket", ignore_duplicates=True
    ).execute()
    archivo.unlink()


def sincronizar_movimientos(cliente: Client, cuenta_id: str, login: str):
    """Depósitos y retiros que registra MT5. Mismo criterio que operaciones:
    solo se agregan, nunca se pisan."""
    archivo = COMUN / f"movimientos_{login}.jsonl"
    if not archivo.exists():
        return
    filas = []
    for linea in archivo.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea:
            continue
        try:
            mov = json.loads(linea)
        except json.JSONDecodeError:
            continue
        if mov.get("ticket") is None:
            continue  # línea de una versión que no conocemos: se ignora
        filas.append({
            "cuenta_id": cuenta_id,
            "ticket": mov["ticket"],
            "monto": mov.get("monto"),
            "comentario": mov.get("comentario"),
            "ocurrido_en": mov.get("ocurrido_en"),
        })
    if not filas:
        return
    cliente.table("movimientos").upsert(
        filas, on_conflict="cuenta_id,ticket", ignore_duplicates=True
    ).execute()
    archivo.unlink()



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
            "nombre": (plantilla_de(login, g.get("grafico_id")) or {}).get("nombre_ea"),
            # Con esto el panel sabe que bot hizo cada operacion.
            "magic": (plantilla_de(login, g.get("grafico_id")) or {}).get("magic"),

        }
        for g in datos.get("graficos", [])
    ]
    if filas:
        cliente.table("bots").upsert(filas, on_conflict="cuenta_id,grafico_id").execute()

    # Los gráficos que se cerraron se borran. Si no, la tabla solo crece y
    # quedan fantasmas: el panel seguiría creyendo que un activo sigue en la
    # cartera mucho después de que le sacaste el bot.
    vivos = [f["grafico_id"] for f in filas]
    borrado = cliente.table("bots").delete().eq("cuenta_id", cuenta_id)
    if vivos:
        borrado = borrado.not_.in_("grafico_id", vivos)
    borrado.execute()


# cuenta_id -> (rol, grupo, simbolo) ya escrito, para no repetir el update.
cache_pares: dict = {}

# (cuenta, grafico) -> datos del EA leídos de su plantilla. Se conservan aunque la
# plantilla se borre, hasta que el recolector la vuelva a escribir.
cache_plantillas: dict = {}

# Dónde viven los terminales MT5, para encontrar las plantillas de los
# gráficos. Una instalación normal los pone bajo %APPDATA%, pero una portable
# va donde se la descomprima (en la segunda VPS, C:\MetaTrader). Se pueden
# sumar carpetas desde el .env con TERMINALES_PATHS, separadas por punto y
# coma; la carpeta Common no cambia, así que el resto de los datos llega igual
# aunque esto esté mal configurado.
CARPETAS_TERMINALES = [Path(os.environ["APPDATA"]) / "MetaQuotes" / "Terminal"] + [
    Path(p.strip())
    for p in os.environ.get("TERMINALES_PATHS", "").split(";")
    if p.strip()
]
# La plantilla lleva cuenta y gráfico: MonitoreoMT5_tpl_<cuenta>_<gráfico>.tpl
#
# El número de gráfico solo es único DENTRO de su terminal. Con terminales
# portables -que son copias de una misma carpeta- varios arrastran los mismos
# números, y como este agente lee las plantillas de todos los terminales
# juntas, sin la cuenta no hay forma de saber cuál es cuál: una pisaba a la
# otra y seis cuentas de tres pares distintos quedaron en un solo grupo.
#
# Las plantillas con el nombre viejo, sin cuenta, se ignoran a propósito. Un
# terminal sin recompilar se queda sin detección de par, que es preferible a
# que se agrupe mal.
PATRON_TPL = re.compile(r"MonitoreoMT5_tpl_(\d+)_(\d+)\.tpl$", re.IGNORECASE)
PATRON_SIMBOLO = re.compile(r"[A-Za-z0-9._,:]{1,40}$")
PATRON_MAPEO = re.compile(r"[A-Za-z0-9._]{2,20}:[A-Za-z0-9._]{2,20}$")
PATRON_MAGIC = re.compile(r"^\d{1,18}$")


def plantilla_de(login, grafico_id):
    """Lo que el recolector leyó del gráfico <grafico_id> de la cuenta <login>.

    Pedir siempre la cuenta además del gráfico es lo que evita que una cuenta
    termine leyendo la plantilla de otra. Si falta, se devuelve None y esa
    cuenta se queda sin detección — que es lo correcto: mejor no saber que
    saber mal."""
    if grafico_id is None:
        return None
    return cache_plantillas.get((int(login), int(grafico_id)))


def es_mapeo_de_simbolos(valor):
    """"NDX100:NAS100.x" es un mapeo de símbolos; "00:00" es una hora de
    reseteo. Tienen la misma forma, y la hora se colaba como si fuera un
    símbolo. Los símbolos siempre llevan alguna letra, las horas nunca."""
    if not PATRON_MAPEO.match(valor):
        return False
    izquierda, derecha = valor.split(":", 1)
    return any(c.isalpha() for c in izquierda) and any(c.isalpha() for c in derecha)


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
    del EA -contraseñas incluidas- no se lee ni se guarda en ningún lado.

    La única excepción es el número mágico, y se lee con dos candados: el
    nombre del parámetro tiene que contener "magic" y el valor tiene que ser
    entero. Una contraseña no cumple ninguna de las dos. Hace falta para
    saber qué bot es cada uno en la cuenta de incubación, donde conviven
    varios en el mismo terminal."""
    try:
        texto = leer_texto_plantilla(ruta)
    except OSError:
        return None

    dentro = False
    nombre = canal = simbolo = mapeo = magic = codigo_par = None
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

        # El mapeo del slave ("NDX100:NAS100.x") se reconoce por su forma.
        if mapeo is None and es_mapeo_de_simbolos(valor):
            mapeo = valor.split(":")[-1]

        pos = linea.find("master.json")
        if canal is None and pos >= 0:
            canal = linea[pos:].strip()
            # En el master el símbolo va en el parámetro justo anterior.
            previo = anterior.split("=", 1)[1].strip() if "=" in anterior else ""
            if PATRON_SIMBOLO.match(previo):
                simbolo = previo.split(":")[-1]

        clave = linea.split("=", 1)[0].strip().lower() if "=" in linea else ""

        # El numero magico del bot: la clave tiene que decir "magic" y el
        # valor ser entero. Una contrasena no cumple ninguna de las dos.
        if magic is None and "magic" in clave and PATRON_MAGIC.match(valor):
            magic = int(valor)

        # El codigo de correspondencia del copiador nuevo (InpCodigoPar): el
        # mismo numero en las dos puntas es lo que las enlaza, igual que antes
        # lo hacia el archivo master.jsonN.
        if codigo_par is None and "codigopar" in clave and PATRON_MAGIC.match(valor):
            codigo_par = int(valor)

        # El simbolo que replica el primario (InpSimbolos). El del secundario
        # viene como mapeo "ORIGEN:DESTINO" y lo agarra es_mapeo_de_simbolos
        # arriba. Vacio en el primario significa "todos", y ahi no hay nada
        # que poner. La clave se compara exacta para no pisar la deteccion
        # del copiador viejo, que saca el simbolo de otro lado.
        if simbolo is None and clave == "inpsimbolos" and valor and ":" not in valor \
                and PATRON_SIMBOLO.match(valor):
            simbolo = valor.split(",")[0]

        anterior = linea

    if not nombre and not canal and codigo_par is None:
        return None
    return {
        "nombre_ea": nombre or "",
        "canal": canal or "",
        "simbolo_operado": mapeo or simbolo or "",
        "magic": magic,
        "codigo_par": codigo_par,
    }


def leer_plantillas():
    """Recorre las plantillas que dejó el recolector en todos los terminales y
    las interpreta. No se borran: el recolector las sobrescribe, y si se
    borraran, un reinicio del agente dejaría los pares sin detectar hasta que
    el recolector las volviera a escribir."""
    for carpeta in CARPETAS_TERMINALES:
        if not carpeta.exists():
            continue
        for ruta in carpeta.glob("*/MQL5/Profiles/Templates/MonitoreoMT5_tpl_*.tpl"):
            m = PATRON_TPL.search(ruta.name)
            if not m:
                continue
            datos = parsear_plantilla(ruta)
            if datos:
                # La clave es (cuenta, gráfico): el gráfico solo no alcanza.
                cache_plantillas[(int(m.group(1)), int(m.group(2)))] = datos


def sincronizar_par(cliente: Client, cuenta_id: str, login: str):
    """Arma y desarma el par siguiendo lo que hay en el MT5. El recolector
    reporta qué EA tiene cada gráfico y con qué parámetros, y las dos puntas
    comparten una clave: el código de correspondencia en el copiador nuevo,
    el archivo master.jsonN en el viejo. Si se retiran los EAs de copia, el
    par se deshace.

    Una cuenta marcada con par_manual queda afuera: hay copiadores que no
    dejan rastro legible y ahí el par se carga a mano."""
    if cuenta_id in cache_par_manual:
        return  # el par se cargó a mano: no es asunto del agente

    datos = leer_json(COMUN / f"graficos_{login}.json")
    if not datos or not datos.get("graficos"):
        return  # sin inventario de gráficos no se concluye nada

    rol = grupo = simbolo = None
    for g in datos["graficos"]:
        ea = plantilla_de(login, g.get("grafico_id"))
        if not ea:
            continue
        nombre = (ea.get("nombre_ea") or "").lower()

        # Copiador nuevo (EA_SX_Primario / EA_SX_Secundario): las dos puntas
        # comparten el código de correspondencia, y el rol sale del nombre
        # del EA. Va primero porque es el sistema al que se está migrando.
        if ea.get("codigo_par") is not None and ("primario" in nombre or "secundario" in nombre):
            rol = "primario" if "primario" in nombre else "secundario"
            grupo = f"Par {ea['codigo_par']}"
            simbolo = ea.get("simbolo_operado") or None
            break

        posible = grupo_desde_canal(ea["canal"])
        if not posible:
            continue
        if "slave" in nombre:
            rol, grupo = "slave", posible
        elif "master" in nombre:
            rol, grupo = "master", posible
        else:
            continue
        simbolo = ea["simbolo_operado"] or None
        break

    # El nombre del par lleva delante el de la máquina: dos VPS pueden usar
    # el mismo código de correspondencia sin que sus pares se confundan.
    #
    # El separador lo pone el agente. Poner el espacio en el .env no sirve:
    # la librería que lo lee recorta los espacios del final del valor.
    if grupo and PREFIJO_PARES:
        grupo = f"{PREFIJO_PARES} {grupo}"

    if cache_pares.get(cuenta_id) == (rol, grupo, simbolo):
        return

    cambios = {"rol": rol, "grupo": grupo}
    if simbolo:
        cambios["simbolo_principal"] = simbolo
    cliente.table("cuentas").update(cambios).eq("id", cuenta_id).execute()
    cache_pares[cuenta_id] = (rol, grupo, simbolo)
    print(f"[par] cuenta {login}: {rol or 'sin par'} {grupo or ''} {simbolo or ''}".strip())


# --------------------------------------------------------------------
# Versiones del recolector
# --------------------------------------------------------------------
# En la VPS conviven varias versiones del EA recolector a la vez, cada una en
# cuentas distintas (la A quedó cerrada operando las cuentas cross, la B sigue
# en desarrollo). El agente tiene que entenderlas a todas: lee cada campo con
# .get(), ignora lo que no conoce y nunca da por sentado que un campo existe.
#
# La versión A no escribe el campo "version" porque se cerró antes de que se
# inventara: si no viene, es esa.
VERSION_BASE = "A"

# login -> versión que reportó, para que aparezca en el log una sola vez.
versiones: dict = {}


def anotar_version(login: str, estado: dict):
    version = estado.get("version") or VERSION_BASE
    if versiones.get(login) != version:
        versiones[login] = version
        print(f"[version] cuenta {login}: recolector {version}")


def sincronizar_datos(cliente: Client, cache_cuentas: dict, cache_reglas: dict):
    limpiar_archivos_muertos()
    leer_plantillas()
    for login in logins_detectados():
        estado = leer_json(COMUN / f"estado_{login}.json")
        if estado is None:
            continue

        if login not in cache_cuentas:
            cache_cuentas[login] = id_cuenta(cliente, login, estado.get("broker", ""))
        cuenta_id = cache_cuentas[login]

        anotar_version(login, estado)

        # Cada cuenta se sincroniza por su cuenta: si una falla -porque la
        # escribió una versión del recolector que no conocemos, o porque el
        # archivo estaba a medio escribir- las demás siguen subiendo igual.
        try:
            subir_estado(cliente, cuenta_id, estado, cache_reglas.get(cuenta_id))
            sincronizar_posiciones(cliente, cuenta_id, login)
            sincronizar_operaciones(cliente, cuenta_id, login)
            sincronizar_movimientos(cliente, cuenta_id, login)
            sincronizar_spreads(cliente, cuenta_id, login)
            sincronizar_bots(cliente, cuenta_id, login)
            sincronizar_par(cliente, cuenta_id, login)
            autoconfigurar(cliente, cuenta_id, login)
        except Exception as e:
            # Un token vencido no es un problema de esta cuenta sino de la
            # sesión entera: se deja subir para que el bucle principal
            # renueve el login en vez de repetir el mismo error por cuenta.
            if sesion_vencida(e):
                raise
            print(f"[datos] cuenta {login} ({versiones.get(login, VERSION_BASE)}): {e}")


# Cuentas ya autoconfiguradas en esta corrida, para no reintentar cada minuto.
autoconfiguradas: set = set()


def autoconfigurar(cliente: Client, cuenta_id: str, login: str):
    """Le pone a una cuenta nueva la prop firm y el tipo, deduciéndolos del
    nombre del broker que reporta MT5.

    El tipo importa tanto como el nombre: decide qué se le dibuja en el panel
    y si el agente le vigila los límites de prop firm. Sin esto, una cuenta
    de Darwinex Zero recién dada de alta entra como 'fondeo' y le aparecen
    Objetivo y Colchón, que ahí no significan nada.

    Los límites en dinero NO se calculan acá: el agente no escribe reglas, a
    propósito, para que un problema en la VPS no toque los límites. De eso se
    encarga el panel, que además necesita que le indiquen la fase."""
    if cuenta_id in autoconfiguradas:
        return

    cuenta = (
        cliente.table("cuentas").select("prop_firm,tipo,broker")
        .eq("id", cuenta_id).single().execute().data
    )
    if not cuenta.get("broker"):
        autoconfiguradas.add(cuenta_id)
        return

    # Si la columna 'tipo' todavía no existe en Supabase, se sigue sin ella:
    # el nombre de la prop firm no tiene por qué esperar a que corras el SQL.
    try:
        equivalencia = (
            cliente.table("brokers_prop_firm")
            .select("prop_firm,tipo").eq("broker", cuenta["broker"]).limit(1).execute()
        )
    except Exception:
        equivalencia = (
            cliente.table("brokers_prop_firm")
            .select("prop_firm").eq("broker", cuenta["broker"]).limit(1).execute()
        )
    if not equivalencia.data:
        return  # broker desconocido: se reintenta cuando se cargue la equivalencia

    fila = equivalencia.data[0]
    cambios = {}

    if not cuenta.get("prop_firm") and fila.get("prop_firm"):
        cambios["prop_firm"] = fila["prop_firm"]

    # El tipo solo se corrige mientras siga en el valor por defecto: si lo
    # cambiaste a mano, el agente no te lo pisa.
    if fila.get("tipo") and (cuenta.get("tipo") or TIPO_FONDEO) == TIPO_FONDEO \
            and fila["tipo"] != TIPO_FONDEO:
        cambios["tipo"] = fila["tipo"]

    if cambios:
        cliente.table("cuentas").update(cambios).eq("id", cuenta_id).execute()
        print(f"[auto] cuenta {login}: " + ", ".join(f"{k} {v}" for k, v in cambios.items()))

    autoconfiguradas.add(cuenta_id)


def leer_reglas(cliente: Client, cache_cuentas: dict) -> dict:
    if not cache_cuentas:
        return {}
    filas = cliente.table("reglas").select("*").in_("cuenta_id", list(cache_cuentas.values())).execute()
    return {f["cuenta_id"]: f for f in filas.data}


# --------------------------------------------------------------------
# Tipos de cuenta
# --------------------------------------------------------------------
# No todas las cuentas se miran igual. Las de fondeo tienen reglas de prop
# firm (pérdida diaria, drawdown, objetivo) y se dan por perdidas al cruzarlas.
# Una cuenta de capital inversor no tiene nada de eso: aplicarle esa
# vigilancia la marcaría "failed" sin sentido.
TIPO_FONDEO = "fondeo"

# cuenta_id -> tipo. Se refresca con las reglas, una vez por minuto.
cache_tipos: dict = {}


def leer_tipos(cliente: Client, cache_cuentas: dict) -> dict:
    """Sin dato se asume cuenta de fondeo, que es lo que eran todas antes de
    que existiera esta distinción.

    Si la columna todavía no existe en Supabase, el agente sigue andando
    como antes: no hay que coordinar el orden entre subir este archivo y
    correr el SQL."""
    if not cache_cuentas:
        return {}
    try:
        filas = (
            cliente.table("cuentas").select("id,tipo,par_manual")
            .in_("id", list(cache_cuentas.values())).execute()
        )
    except Exception as e:
        global aviso_tipos
        if not aviso_tipos:
            aviso_tipos = True
            print(f"[tipos] sin columna 'tipo' todavía, todas se tratan como fondeo: {e}")
        return {}

    # De paso se anota qué cuentas tienen el par puesto a mano, para no
    # deshacérselo en sincronizar_par.
    cache_par_manual.clear()
    for f in filas.data:
        if f.get("par_manual"):
            cache_par_manual.add(f["id"])

    return {f["id"]: (f.get("tipo") or TIPO_FONDEO) for f in filas.data}


# Para no repetir el aviso de columna faltante en cada ciclo.
aviso_tipos = False

# Cuentas cuyo par se cargó a mano. El agente no les toca rol ni grupo: no
# todos los copiadores dejan un rastro que se pueda leer, y perder el par en
# cada ciclo sería peor que no detectarlo.
cache_par_manual: set = set()


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
        # Solo las cuentas de fondeo tienen reglas de prop firm que vigilar.
        if cache_tipos.get(cuenta_id, TIPO_FONDEO) != TIPO_FONDEO:
            continue

        reglas = cache_reglas.get(cuenta_id)
        if not reglas:
            continue
        estado = leer_json(COMUN / f"estado_{login}.json")
        if not estado or estado.get("equity") is None:
            continue

        equity = estado["equity"]

        # La marca de agua se actualiza también acá, no solo al subir a
        # Supabase. Esta vuelta corre cada segundo sobre el archivo que el EA
        # refresca cada cinco; la subida es cada sesenta. Con trailing, un
        # pico de equity que pase dentro de ese minuto y no se registre deja
        # el piso más abajo del que la prop firm está usando de verdad.
        anterior = cache_equity_max.get(cuenta_id)
        if anterior is None or equity > anterior:
            cache_equity_max[cuenta_id] = equity

        # Equity en cero: la prop firm dio de baja la cuenta. Pasa cuando se
        # rompe una regla operando fuera de la VPS, así que el panel no ve la
        # caída, solo el resultado.
        if equity == 0:
            marcar_violacion(cliente, cuenta_id, login, "cuenta cerrada por la prop firm")
            continue
        saldo_inicial = reglas.get("saldo_inicial")
        drawdown_max = reglas.get("drawdown_max")
        perdida_diaria_max = reglas.get("perdida_diaria_max")

        # Con trailing el piso no es fijo: persigue al equity más alto, hasta
        # congelarse en el saldo inicial.
        piso = piso_drawdown(cuenta_id, reglas)
        rota_total = bool(piso is not None and equity <= piso)

        # La pérdida diaria se mide contra el equity con el que arrancó el día.
        # Hay que detectarla en el momento: al día siguiente el contador se
        # reinicia y la violación ya no se ve en los números.
        inicio_dia = cache_inicio_dia.get(cuenta_id)
        rota_diaria = bool(perdida_diaria_max and inicio_dia
                           and (inicio_dia[0] - equity) >= perdida_diaria_max)

        if rota_total or rota_diaria:
            marcar_violacion(cliente, cuenta_id, login,
                             "pérdida máxima" if rota_total else "pérdida diaria")

        cruzo = rota_total or rota_diaria
        ya_avisado = cruzados.get(cuenta_id, False)

        if cruzo and not ya_avisado:
            subir_estado(cliente, cuenta_id, estado, reglas)
            cruzados[cuenta_id] = True
        elif not cruzo and ya_avisado:
            cruzados[cuenta_id] = False


# Cuentas ya marcadas como rotas, para no repetir el update.
violadas: set = set()


def marcar_violacion(cliente: Client, cuenta_id: str, login: str, motivo: str):
    """Una violación no se deshace: la cuenta queda 'failed' para siempre,
    aunque al día siguiente los números vuelvan a estar en orden."""
    if cuenta_id in violadas:
        return
    cliente.table("cuentas").update({"resultado": "failed"}).eq("id", cuenta_id).execute()
    violadas.add(cuenta_id)
    print(f"[violacion] cuenta {login}: {motivo}")


# --------------------------------------------------------------------
# Bucle principal
# --------------------------------------------------------------------

SEGUNDOS_REINTENTO_ARRANQUE = 30


def arrancar() -> Client:
    """Conecta y siembra las cachés, reintentando hasta lograrlo.

    Antes esto corría sin protección: si Supabase tardaba en responder justo
    en ese momento, la excepción mataba el proceso y la VPS se quedaba sin
    agente hasta que alguien lo notara. Un problema de red de medio minuto
    no puede tumbar algo que tiene que correr solo."""
    while True:
        try:
            cliente = conectar()
            sembrar_cache_inicio_dia(cliente)
            sembrar_cache_equity_max(cliente)
            return cliente
        except Exception as e:
            print(f"[arranque] no se pudo conectar, se reintenta en {SEGUNDOS_REINTENTO_ARRANQUE}s: {e}")
            time.sleep(SEGUNDOS_REINTENTO_ARRANQUE)


def principal():
    cliente = arrancar()
    cache_cuentas: dict = {}
    cache_reglas: dict = {}
    cruzados: dict = {}

    t_datos = t_ordenes = 0.0

    print(f"Agente conectado. Leyendo {COMUN}")

    while True:
        # Red de seguridad: los tres bloques de adentro ya atrapan lo suyo,
        # pero cualquier error fuera de ellos terminaba el proceso y la VPS
        # se quedaba sin agente. Acá se anota y se sigue en la vuelta
        # siguiente, pase lo que pase.
        try:
            ahora = time.monotonic()

            if ahora - t_datos >= INTERVALO_DATOS:
                try:
                    sincronizar_datos(cliente, cache_cuentas, cache_reglas)
                    cache_reglas = leer_reglas(cliente, cache_cuentas)
                    cache_tipos.update(leer_tipos(cliente, cache_cuentas))
                except Exception as e:
                    if not renovar_si_vencio(cliente, e):
                        print(f"[datos] error: {e}")
                t_datos = ahora

            if ahora - t_ordenes >= INTERVALO_ORDENES:
                try:
                    procesar_ordenes(cliente, cache_cuentas)
                except Exception as e:
                    if not renovar_si_vencio(cliente, e):
                        print(f"[ordenes] error: {e}")
                t_ordenes = ahora

            try:
                vigilar_limites(cliente, cache_cuentas, cache_reglas, cruzados)
            except Exception as e:
                if not renovar_si_vencio(cliente, e):
                    print(f"[vigilancia] error: {e}")

        except Exception as e:
            print(f"[bucle] error inesperado: {e}")

        time.sleep(INTERVALO_VIGILANCIA)



if __name__ == "__main__":
    principal()
