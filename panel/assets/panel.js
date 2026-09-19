// Panel web - Centro de Monitoreo MT5
// Web estática: consulta Supabase directo desde el navegador. No tiene
// servidor propio. La key de acá es la "anon/public", pensada para ir
// en código publicado - sin sesión no deja hacer nada (RLS).

const SUPABASE_URL = "https://wjmupiiwwwngigqyggex.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_YZQ9ZA7GMFJJrceE4uLVIw_-4xFmXZG";

// Ojo: la variable NO se llama "supabase" a propósito - ese nombre ya lo
// usa la librería para su objeto global (window.supabase) y declarar un
// const con el mismo nombre tira "Identifier has already been declared".
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const METODOS = ["Media Cross", "Stand Alone"];

const SEGUNDOS_SEÑAL_VIDA = 90;    // más que esto sin novedades = puntito en rojo
const SEGUNDOS_SIN_TARJETA = 600;  // más que esto = la cuenta deja de tener tarjeta
const INTERVALO_REFRESCO_MS = 10_000;

const vistaLogin = document.getElementById("vista-login");
const vistaPanel = document.getElementById("vista-panel");
const formLogin = document.getElementById("form-login");
const errorLogin = document.getElementById("error-login");
const listaCuentas = document.getElementById("lista-cuentas");
const btnSalir = document.getElementById("btn-salir");
const plantillaCuenta = document.getElementById("plantilla-cuenta");
const cuerpoPlantillas = document.getElementById("cuerpo-plantillas");
const cuerpoResumen = document.getElementById("cuerpo-resumen");
const seccionInversor = document.getElementById("inversor-seccion");
const cuerpoInversor = document.getElementById("cuerpo-inversor");
const formPlantilla = document.getElementById("form-plantilla");

let temporizadorRefresco = null;
let plantillasCache = [];
let paresCache = [];

// Ids de las cuentas de capital inversor. Se llenan al cargar su tabla y
// sirven para que no aparezcan también en la de cuentas de fondeo.
let idsInversor = new Set();

// ---------------------------------------------------------------
// Autenticación
// ---------------------------------------------------------------

formLogin.addEventListener("submit", async (ev) => {
  ev.preventDefault();
  errorLogin.textContent = "";
  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;

  const { error } = await sb.auth.signInWithPassword({ email, password });
  if (error) {
    errorLogin.textContent = "No se pudo entrar: " + error.message;
  }
});

btnSalir.addEventListener("click", async () => {
  await sb.auth.signOut();
});

sb.auth.onAuthStateChange((_evento, sesion) => {
  if (sesion) {
    mostrarPanel();
  } else {
    mostrarLogin();
  }
});

function mostrarLogin() {
  vistaLogin.hidden = false;
  vistaPanel.hidden = true;
  if (temporizadorRefresco) clearInterval(temporizadorRefresco);
}

function mostrarPanel() {
  vistaLogin.hidden = true;
  vistaPanel.hidden = false;
  cargarPlantillas().then(refrescar);
  if (temporizadorRefresco) clearInterval(temporizadorRefresco);
  temporizadorRefresco = setInterval(refrescar, INTERVALO_REFRESCO_MS);
}

function refrescar() {
  if (arrastrando) return; // no mover el piso mientras se acomodan las tarjetas
  // Primero las de capital inversor: la tabla de fondeo necesita saber
  // cuáles son para no listarlas dos veces.
  cargarInversor().then(() => cargarBalance()).then(cargarResumen);
  cargarPares().then(cargarCuentas);
}

// ---------------------------------------------------------------
// Datos
// ---------------------------------------------------------------

async function cargarCuentas() {
  const { data, error } = await sb
    .from("cuentas")
    .select("*, estado(*), reglas(*)")
    .eq("activa", true)
    .order("alta_en");

  if (error) {
    listaCuentas.innerHTML = `<p class="error">Error cargando cuentas: ${error.message}</p>`;
    return;
  }

  // Las cuentas que ya no están en ningún MT5 se siguen viendo en la tabla de
  // arriba, pero no ocupan una tarjeta. El margen es holgado a propósito: que
  // una tarjeta no desaparezca porque el agente se reinició un minuto.
  const enVivo = data.filter((c) => {
    if (!c.estado?.visto_en) return false;
    return (Date.now() - new Date(c.estado.visto_en).getTime()) / 1000 <= SEGUNDOS_SIN_TARJETA;
  });

  if (!enVivo.length) {
    listaCuentas.innerHTML = `<p class="aviso">Ninguna cuenta está reportando en este momento.</p>`;
    return;
  }

  // No se vacía acá: de eso se encarga dibujarEnColumnas(), que además
  // sostiene el alto para que la página no dé un salto al refrescar.

  const grupos = new Map();
  const sueltas = [];
  for (const cuenta of enVivo) {
    if (cuenta.grupo) {
      if (!grupos.has(cuenta.grupo)) grupos.set(cuenta.grupo, []);
      grupos.get(cuenta.grupo).push(cuenta);
    } else {
      sueltas.push(cuenta);
    }
  }

  tarjetas = [];
  for (const [nombre, delGrupo] of grupos) {
    tarjetas.push({
      clave: `par:${nombre}`,
      cuentas: delGrupo,
      costo: costoDelPar(nombre),
      dibujar: () => renderizarPar(nombre, delGrupo),
    });
  }
  for (const cuenta of sueltas) {
    tarjetas.push({
      clave: `cuenta:${cuenta.id}`,
      cuentas: [cuenta],
      costo: 0,
      dibujar: () => renderizarCuenta(cuenta),
    });
  }

  // En el celular se apilan solas, primero las que más están costando. En la
  // computadora cada tarjeta va al lugar de la columna donde vos la dejaste.
  const movibles = !esPantallaChica();
  if (!movibles) tarjetas.sort((a, b) => b.costo - a.costo);

  for (const t of tarjetas) {
    // Una cuenta suelta llega como fragmento de la plantilla; un par, como
    // un contenedor ya armado. En los dos casos queremos el elemento.
    const nodo = t.dibujar();
    t.elemento = nodo instanceof DocumentFragment ? nodo.firstElementChild : nodo;
    if (movibles) hacerMovible(t);
  }

  dibujarEnColumnas();
}

// ---------------------------------------------------------------
// Orden de las tarjetas
// ---------------------------------------------------------------

const ANCHO_PANTALLA_CHICA = 700;
const ANCHO_TARJETA = 360;
const SEPARACION = 20;

let tarjetas = [];
let columnas = [];
let arrastrando = false;

function esPantallaChica() {
  return window.innerWidth <= ANCHO_PANTALLA_CHICA;
}

// Al cambiar el tamaño de la ventana entran más o menos columnas: se vuelven
// a repartir las tarjetas que ya están dibujadas, sin pedir datos de nuevo.
window.addEventListener("resize", () => {
  if (!arrastrando && tarjetas.length) dibujarEnColumnas();
});

function costoDelPar(nombreGrupo) {
  return paresCache
    .filter((p) => p.grupo === nombreGrupo)
    .reduce(
      (a, p) =>
        a +
        Math.abs(Number(p.spread) || 0) +
        Math.abs(Number(p.swaps) || 0) +
        Math.abs(Number(p.comisiones) || 0),
      0
    );
}

function valorGuardado(tarjeta, campo) {
  const valor = tarjeta.cuentas.map((c) => c[campo]).find((v) => v != null);
  return valor == null ? null : Number(valor);
}

// Las tarjetas viven en columnas fijas del ancho de una tarjeta, apiladas en
// orden. Así no hay superposiciones ni posiciones a medio camino: una tarjeta
// siempre ocupa un lugar concreto de una columna.
function dibujarEnColumnas() {
  // El panel se redibuja entero cada 10 segundos. Al vaciarlo la página se
  // encoge de golpe, el navegador no tiene a dónde scrollear y te devuelve
  // arriba de todo - se notaba sobre todo en el celular, donde la lista es
  // larga. Se le sostiene el alto mientras se rearma y se devuelve el scroll
  // donde estaba.
  const scrollPrevio = window.scrollY;
  const altoPrevio = listaCuentas.offsetHeight;
  if (altoPrevio) listaCuentas.style.minHeight = `${altoPrevio}px`;

  listaCuentas.innerHTML = "";

  // clientWidth incluye el relleno del panel, así que lo descuento antes de
  // ver cuántas columnas entran.
  const estilo = getComputedStyle(listaCuentas);
  const util =
    listaCuentas.clientWidth -
    parseFloat(estilo.paddingLeft) -
    parseFloat(estilo.paddingRight);

  const cantidad = esPantallaChica()
    ? 1
    : Math.max(1, Math.floor((util + SEPARACION) / (ANCHO_TARJETA + SEPARACION)));

  columnas = [];
  for (let i = 0; i < cantidad; i++) {
    const div = document.createElement("div");
    div.className = "columna";
    listaCuentas.appendChild(div);
    columnas.push(div);
  }

  const porColumna = Array.from({ length: cantidad }, () => []);
  const sinLugar = [];
  for (const t of tarjetas) {
    const col = valorGuardado(t, "columna");
    if (col == null || col >= cantidad) sinLugar.push(t);
    else porColumna[col].push(t);
  }

  for (const lista of porColumna) {
    lista.sort((a, b) => (valorGuardado(a, "orden") ?? 0) - (valorGuardado(b, "orden") ?? 0));
  }

  // Las que nunca se ubicaron van a la columna que tenga menos tarjetas.
  for (const t of sinLugar) {
    const masCorta = porColumna.reduce(
      (mejor, lista, i) => (lista.length < porColumna[mejor].length ? i : mejor),
      0
    );
    porColumna[masCorta].push(t);
  }

  porColumna.forEach((lista, i) => {
    for (const t of lista) columnas[i].appendChild(t.elemento);
  });

  listaCuentas.style.minHeight = "";
  if (window.scrollY !== scrollPrevio) window.scrollTo(0, scrollPrevio);
}

function hacerMovible(tarjeta) {
  const el = tarjeta.elemento;
  el.classList.add("movible");

  el.addEventListener("pointerdown", (ev) => {
    // Los controles de la tarjeta siguen funcionando: no se arrastra desde
    // un desplegable, un campo de texto o un botón.
    if (ev.target.closest("select, input, button, a, summary")) return;
    ev.preventDefault();

    const caja = el.getBoundingClientRect();
    const agarreX = ev.clientX - caja.left;
    const agarreY = ev.clientY - caja.top;

    // Un hueco del mismo alto marca el lugar que va a ocupar al soltarla.
    const hueco = document.createElement("div");
    hueco.className = "hueco";
    hueco.style.height = `${caja.height}px`;
    el.parentElement.insertBefore(hueco, el);

    arrastrando = true; // el refresco automático espera a que sueltes
    el.classList.add("arrastrando");
    el.style.width = `${caja.width}px`;
    el.style.left = `${caja.left}px`;
    el.style.top = `${caja.top}px`;

    const mover = (e) => {
      el.style.left = `${e.clientX - agarreX}px`;
      el.style.top = `${e.clientY - agarreY}px`;
      ubicarHueco(hueco, el, e.clientX, e.clientY);
    };

    const soltar = async () => {
      window.removeEventListener("pointermove", mover);
      window.removeEventListener("pointerup", soltar);
      window.removeEventListener("pointercancel", soltar);

      el.classList.remove("arrastrando");
      el.removeAttribute("style");
      hueco.parentElement.insertBefore(el, hueco);
      hueco.remove();

      // Recién suelto el freno del refresco cuando la base ya tiene la
      // ubicación nueva: si no, una lectura a medio camino trae la vieja y
      // la tarjeta salta de vuelta.
      await guardarUbicaciones();
      arrastrando = false;
    };

    window.addEventListener("pointermove", mover);
    window.addEventListener("pointerup", soltar);
    // Si el navegador corta el gesto (salir de la ventana, otro dedo), se
    // cierra igual: si no, el refresco quedaría frenado para siempre.
    window.addEventListener("pointercancel", soltar);
  });
}

// Mueve el hueco a la columna que está debajo del cursor, en la posición que
// corresponda según la altura.
function ubicarHueco(hueco, el, x, y) {
  // La columna cuyo centro quede más cerca del cursor, aunque el cursor se
  // haya salido del borde del panel.
  let destino = columnas[0];
  let menor = Infinity;
  for (const columna of columnas) {
    const caja = columna.getBoundingClientRect();
    const distancia = Math.abs(x - (caja.left + caja.width / 2));
    if (distancia < menor) {
      menor = distancia;
      destino = columna;
    }
  }

  const hermanas = [...destino.children].filter((h) => h !== hueco && h !== el);
  const siguiente = hermanas.find((h) => {
    const caja = h.getBoundingClientRect();
    return y < caja.top + caja.height / 2;
  });

  destino.insertBefore(hueco, siguiente ?? null);
}

async function guardarUbicaciones() {
  for (let i = 0; i < columnas.length; i++) {
    const hijas = [...columnas[i].children];
    for (let j = 0; j < hijas.length; j++) {
      const tarjeta = tarjetas.find((t) => t.elemento === hijas[j]);
      if (!tarjeta) continue;
      for (const c of tarjeta.cuentas) {
        // La copia en memoria se actualiza igual que la base: así un
        // redibujado por zoom o por cambio de tamaño no revive la ubicación
        // anterior mientras tanto.
        if (c.columna === i && c.orden === j) continue;
        c.columna = i;
        c.orden = j;
        const { error } = await sb
          .from("cuentas")
          .update({ columna: i, orden: j })
          .eq("id", c.id);
        if (error) {
          alert("No se pudo guardar la ubicación: " + error.message);
          return;
        }
      }
    }
  }
}

// En un par inverso el movimiento del precio se cancela entre las dos puntas,
// así que lo que queda del resultado combinado es el costo de operar: spread,
// comisiones y swaps.
async function cargarPares() {
  const { data, error } = await sb.from("resumen_pares").select("*");
  if (!error) paresCache = data;
}

function renderizarPar(nombreGrupo, cuentas) {
  const contenedor = document.createElement("article");
  contenedor.className = "par";

  const encabezado = document.createElement("header");
  encabezado.className = "par-header";
  const subtitulo = cuentas.find((c) => c.grupo_subtitulo)?.grupo_subtitulo;
  encabezado.innerHTML = `<span class="par-nombre">${nombreGrupo}</span>${subtitulo ? `<span class="par-subtitulo">${subtitulo}</span>` : ""}`;

  contenedor.appendChild(encabezado);

  // Master primero, después las slave.
  const orden = { master: 0, slave: 1 };
  const ordenadas = [...cuentas].sort((a, b) => (orden[a.rol] ?? 2) - (orden[b.rol] ?? 2));
  for (const cuenta of ordenadas) {
    contenedor.appendChild(renderizarCuenta(cuenta));
  }

  const costos = renderizarCostosDelPar(nombreGrupo);
  if (costos) contenedor.appendChild(costos);

  return contenedor;
}

// Lo que el par deja en el camino: una barra por cuenta, partida en spread,
// swap y comisión, más el total de las dos.
function renderizarCostosDelPar(nombreGrupo) {
  const filas = paresCache.filter((p) => p.grupo === nombreGrupo);
  if (!filas.length) return null;

  const bloque = document.createElement("div");
  bloque.className = "par-costos";

  let total = 0;
  for (const f of filas) {
    const partes = [
      { clase: "seg-spread", etiqueta: "spread", valor: Math.abs(Number(f.spread) || 0) },
      { clase: "seg-swap", etiqueta: "swap", valor: Math.abs(Number(f.swaps) || 0) },
      { clase: "seg-comision", etiqueta: "comisión", valor: Math.abs(Number(f.comisiones) || 0) },
    ];
    const suma = partes.reduce((a, p) => a + p.valor, 0);
    total += suma;

    const nombre = f.prop_firm || `#${f.login}`;
    const segmentos = suma > 0
      ? partes
          .filter((p) => p.valor > 0)
          .map((p) => `<span class="${p.clase}" style="width:${(p.valor / suma) * 100}%" title="${p.etiqueta} ${formatearMoneda(p.valor)}"></span>`)
          .join("")
      : "";

    const fila = document.createElement("div");
    fila.className = "costo-cuenta";
    fila.innerHTML = `
      <div class="costo-encabezado">
        <span class="costo-nombre">${nombre}</span>
        <span class="costo-total">${formatearMoneda(suma)}</span>
      </div>
      <div class="costo-barra">${segmentos}</div>
      <div class="costo-leyenda">
        ${partes.map((p) => `<span class="punto ${p.clase}"></span>${p.etiqueta} ${formatearMoneda(p.valor)}`).join(" ")}
      </div>`;
    bloque.appendChild(fila);
  }

  const resumen = document.createElement("div");
  resumen.className = "costo-resumen";
  resumen.innerHTML = `<span class="etiqueta">Costo del par</span><span>${formatearMoneda(total)}</span>`;
  bloque.appendChild(resumen);

  return bloque;
}

function renderizarCuenta(cuenta) {
  const nodo = plantillaCuenta.content.cloneNode(true);
  const estado = cuenta.estado; // 1:1
  const reglas = cuenta.reglas; // 1:1

  const partesTitulo = [cuenta.fase, cuenta.simbolo_principal].filter(Boolean);
  nodo.querySelector(".cuenta-alias").textContent = partesTitulo.length
    ? partesTitulo.join(" | ")
    : (cuenta.alias || `Cuenta ${cuenta.login}`);
  nodo.querySelector(".cuenta-login").textContent = `#${cuenta.login}`;
  nodo.querySelector(".cuenta-broker").textContent = cuenta.broker || "";

  const insigniaRol = nodo.querySelector(".insignia-rol");
  if (cuenta.rol) {
    insigniaRol.textContent = cuenta.rol.toUpperCase();
    insigniaRol.classList.add(`rol-${cuenta.rol}`);
  } else {
    insigniaRol.hidden = true;
  }

  const avisoSlave = nodo.querySelector(".aviso-slave");
  if (cuenta.rol === "slave" && cuenta.slave_allowed === false) {
    avisoSlave.hidden = false;
    avisoSlave.textContent = `⚠ slave en firma con slave_allowed=FALSE (${cuenta.prop_firm || "prop firm"}, login ${cuenta.login})`;
  }

  const indAlgo = nodo.querySelector(".algo-trading");
  const indSeñal = nodo.querySelector("[title='Señal de vida']");

  if (estado) {
    // Mismo símbolo que usa MT5: triángulo verde encendido, cuadrado rojo apagado.
    indAlgo.textContent = estado.algo_trading ? "▶" : "■";
    indAlgo.title = estado.algo_trading ? "Algo Trading encendido" : "Algo Trading apagado";
    indAlgo.classList.add(estado.algo_trading ? "on" : "off");
    const segundos = (Date.now() - new Date(estado.visto_en).getTime()) / 1000;
    indSeñal.classList.add(segundos <= SEGUNDOS_SEÑAL_VIDA ? "on" : "off");
    indSeñal.title = segundos <= SEGUNDOS_SEÑAL_VIDA
      ? "Con señal"
      : `Sin señal hace ${Math.round(segundos)}s`;

    ponerMetrica(nodo, ".m-saldo", estado.saldo);
    ponerMetrica(nodo, ".m-flotante", estado.flotante, true);
  } else {
    indAlgo.textContent = "■";
    indSeñal.classList.add("off");
    indSeñal.title = "Nunca dio señal";
  }

  renderizarObjetivos(nodo, estado, reglas);

  return nodo;
}

function renderizarObjetivos(nodo, estado, reglas) {
  const elHoy = nodo.querySelector(".valor-hoy");
  const elAcumulado = nodo.querySelector(".valor-acumulado");
  const elTextoObjetivo = nodo.querySelector(".texto-objetivo");
  const elTextoColchonDia = nodo.querySelector(".texto-colchon-dia");
  const elTextoColchonTotal = nodo.querySelector(".texto-colchon-total");
  const barraObjetivo = nodo.querySelector(".barra-objetivo-relleno");
  const barraColchonDia = nodo.querySelector(".barra-colchon-dia");
  const barraColchonTotal = nodo.querySelector(".barra-colchon-total");

  if (!estado) {
    elHoy.textContent = elAcumulado.textContent = "-";
    elTextoObjetivo.textContent = elTextoColchonDia.textContent = elTextoColchonTotal.textContent = "Sin datos";
    return;
  }

  const equity = estado.equity;
  const saldoInicial = reglas?.saldo_inicial;
  const hoy = estado.equity_inicio_dia != null ? equity - estado.equity_inicio_dia : null;
  const acumulado = saldoInicial != null ? equity - saldoInicial : null;

  ponerConSigno(elHoy, hoy, saldoInicial);
  ponerConSigno(elAcumulado, acumulado, saldoInicial);

  const objetivo = reglas?.objetivo_fase;
  if (objetivo != null && acumulado != null) {
    const faltan = objetivo - acumulado;
    elTextoObjetivo.innerHTML = faltan > 0
      ? `faltan ${vivo(faltan)} / ${formatearMoneda(objetivo)}`
      : "objetivo cumplido";
    ponerBarra(barraObjetivo, (acumulado / objetivo) * 100);
  } else {
    elTextoObjetivo.textContent = "Sin objetivo";
    ponerBarra(barraObjetivo, 0);
  }

  const drawdownMax = reglas?.drawdown_max;
  let colchonTotal = null;
  if (drawdownMax != null && saldoInicial != null) {
    colchonTotal = equity - saldoInicial + drawdownMax;
    const pct = (colchonTotal / drawdownMax) * 100;
    elTextoColchonTotal.innerHTML = `${vivo(colchonTotal)} (${Math.round(pct)}%)`;
    ponerBarra(barraColchonTotal, pct);
  } else {
    elTextoColchonTotal.textContent = "Sin reglas";
    ponerBarra(barraColchonTotal, 0);
  }

  // El colchón del día nunca puede superar lo que queda de colchón total:
  // aunque el permiso diario sea mayor, la cuenta revienta antes por la
  // pérdida máxima. Es como lo muestran las propias prop firms.
  const perdidaDiariaMax = reglas?.perdida_diaria_max;
  if (perdidaDiariaMax != null && hoy != null) {
    let colchon = perdidaDiariaMax + hoy;
    if (colchonTotal != null) colchon = Math.min(colchon, colchonTotal);
    const pct = (colchon / perdidaDiariaMax) * 100;
    elTextoColchonDia.innerHTML = `${vivo(colchon)} (${Math.round(pct)}%)`;
    ponerBarra(barraColchonDia, pct);
  } else {
    elTextoColchonDia.textContent = "Sin dato de hoy todavía";
    ponerBarra(barraColchonDia, 0);
  }
}

// Resalta el número que cambia, dejando el texto fijo en gris.
function vivo(v) {
  return `<span class="dato-vivo">${formatearMoneda(v)}</span>`;
}

function ponerBarra(el, pct) {
  el.style.width = `${Math.max(0, Math.min(100, pct))}%`;
  el.classList.toggle("critico", pct < 20);
  el.classList.toggle("alerta", pct >= 20 && pct < 50);
}

function ponerConSigno(el, v, base) {
  if (v == null) {
    el.textContent = "-";
    return;
  }
  const signo = v >= 0 ? "+" : "";
  let texto = signo + formatearMoneda(v);
  if (base) {
    const pct = ((v / base) * 100).toFixed(1).replace(".", ",");
    texto += ` <span class="pct-secundario">(${signo}${pct}%)</span>`;
  }
  el.innerHTML = texto;
  el.classList.add(v < 0 ? "negativo" : "positivo");
}

// ---------------------------------------------------------------
// Estado general de las cuentas de fondeo (una línea por cuenta)
// ---------------------------------------------------------------

async function cargarResumen() {
  let { data, error } = await sb
    .from("resumen_cuentas")
    .select("*")
    .eq("activa", true)
    // Las más activas arriba; las que nunca reportaron, al final.
    .order("dias_inactividad", { ascending: true, nullsFirst: false });

  if (error) {
    cuerpoResumen.innerHTML = `<tr><td colspan="12" class="error">${error.message}</td></tr>`;
    return;
  }

  // Pasado el límite de inactividad la cuenta ya está perdida: sale de la lista.
  data = data.filter((c) => (c.dias_inactividad ?? 0) <= 31);

  // Las de capital inversor tienen su propia tabla, con otros campos.
  data = data.filter((c) => !idsInversor.has(c.id));

  // Completar reglas es tarea del panel: el agente no escribe límites.
  let seCompletoAlgo = false;
  for (const c of data) {
    if (await completarReglas(c)) seCompletoAlgo = true;
  }
  if (seCompletoAlgo) {
    cargarResumen();
    cargarCuentas();
    return;
  }

  cuerpoResumen.innerHTML = "";
  for (const c of data) {
    // Si la prop firm no exige un mínimo de días, no hay nada que comparar.
    const dias = c.dias_operados == null
      ? "-"
      : c.min_dias_trading == null
        ? "N.A."
        : `${c.dias_operados} / ${c.min_dias_trading}`;

    const inactiva = c.dias_inactividad;
    const claseInactiva = inactiva != null && c.dias_inactividad_max != null
      ? (inactiva >= c.dias_inactividad_max ? "negativo"
         : inactiva >= c.dias_inactividad_max * 0.7 ? "alerta-texto" : "")
      : "";

    // Verde mientras la cuenta siga reportando desde algún MT5 logueado.
    const segundos = c.visto_en
      ? (Date.now() - new Date(c.visto_en).getTime()) / 1000
      : null;
    const viva = segundos != null && segundos <= SEGUNDOS_SEÑAL_VIDA;

    // Una cuenta caída ya no está ni viva ni muerta por conexión: está fuera.
    const fallida = c.estado_cuenta === "failed";
    const claseEstado = fallida ? "muerta" : viva ? "on" : "off";
    const tituloEstado = fallida
      ? "Cuenta caída"
      : viva ? "Logueada en un MT5" : "No está en ningún MT5";

    const fila = document.createElement("tr");
    fila.innerHTML = `
      <td><span class="indicador ${claseEstado}" title="${tituloEstado}"></span></td>
      <td>${c.prop_firm ?? "-"}</td>
      <td class="col-plan"></td>
      <td class="col-fase"></td>
      <td class="col-metodo"></td>
      <td class="col-cuenta">#${c.login}</td>
      <td>${formatearEntero(c.saldo_inicial)}</td>
      <td>${formatearMoneda(c.saldo)}</td>
      <td>${dias}</td>
      <td class="${claseInactiva}">${inactiva ?? "-"}</td>
      <td>${textoIdeaTrade(c)}</td>
      <td><span class="estado-cuenta estado-${(c.estado_cuenta || "").replace(" ", "-")}">${c.estado_cuenta ?? "-"}</span></td>
      <td class="col-precio"></td>
      <td title="${c.retiro_acumulado != null ? `Retiro bruto ${formatearDolares(c.retiro_acumulado)}` : ""}">${formatearDolares(retiroNeto(c))}</td>
    `;
    fila.querySelector(".col-precio").appendChild(campoPrecio(c));
    fila.querySelector(".col-plan").appendChild(selectorDePlan(c));
    fila.querySelector(".col-fase").appendChild(selectorDeFase(c));
    fila.querySelector(".col-metodo").appendChild(
      selectorDeCuenta(c, "metodo", METODOS)
    );
    cuerpoResumen.appendChild(fila);
  }

  cuerpoResumen.appendChild(filaDeTotales());
  actualizarTituloResumen(data);
}

// ---------------------------------------------------------------
// Cuentas de capital inversor (desplegable aparte, campos propios)
// ---------------------------------------------------------------
// No son cuentas de fondeo: no hay prop firm, fase, objetivo ni precio de
// compra. Lo que se mira es cuánto capital entró, cuánto se sacó y cuánto
// se ganó con eso.

async function cargarInversor() {
  const { data, error } = await sb
    .from("resumen_inversor")
    .select("*")
    .eq("activa", true)
    .order("dias_inactividad", { ascending: true, nullsFirst: false });

  if (error) {
    // Todavía sin la vista creada: la sección no se muestra y la tabla de
    // fondeo sigue funcionando como siempre.
    seccionInversor.hidden = true;
    idsInversor = new Set();
    return;
  }

  idsInversor = new Set(data.map((c) => c.id));
  seccionInversor.hidden = data.length === 0;
  if (!data.length) return;

  cuerpoInversor.innerHTML = "";
  for (const c of data) {
    const segundos = c.visto_en
      ? (Date.now() - new Date(c.visto_en).getTime()) / 1000
      : null;
    const viva = segundos != null && segundos <= SEGUNDOS_SEÑAL_VIDA;

    const rendimiento = c.resultado != null && c.aportado
      ? (Number(c.resultado) / Number(c.aportado)) * 100
      : null;

    const fila = document.createElement("tr");
    fila.innerHTML = `
      <td><span class="indicador ${viva ? "on" : "off"}" title="${viva ? "Logueada en un MT5" : "No está en ningún MT5"}"></span></td>
      <td>${c.broker ?? "-"}</td>
      <td class="col-cuenta">#${c.login}</td>
      <td>${formatearDolares(c.aportado)}</td>
      <td>${formatearMoneda(c.saldo)}</td>
      <td class="${Number(c.flotante) < 0 ? "negativo" : "positivo"}">${formatearMoneda(c.flotante)}</td>
      <td class="${Number(c.resultado) < 0 ? "negativo" : "positivo"}">${formatearDolares(c.resultado)}</td>
      <td class="${rendimiento < 0 ? "negativo" : "positivo"}">${rendimiento == null ? "-" : rendimiento.toFixed(1) + "%"}</td>
      <td>${formatearDolares(c.retirado)}</td>
      <td>${c.dias_operados ?? "-"}</td>
      <td>${c.dias_inactividad ?? "-"}</td>
    `;
    cuerpoInversor.appendChild(fila);
  }

  const total = data.reduce((a, c) => a + (Number(c.resultado) || 0), 0);
  document.getElementById("inversor-titulo").innerHTML =
    `Capital inversor · ${data.length}` +
    ` · resultado <span class="${total < 0 ? "negativo" : "positivo"}">${formatearDolares(total)}</span>`;
}

// Con la sección cerrada, el título tiene que decir lo esencial igual.
function actualizarTituloResumen(cuentas) {
  const resultado = balance.recuperado - balance.invertido;
  const caidas = cuentas.filter((c) => c.estado_cuenta === "failed").length;

  document.getElementById("resumen-titulo").innerHTML =
    `Cuentas de fondeo · ${cuentas.length}` +
    (caidas ? ` · ${caidas} caída${caidas > 1 ? "s" : ""}` : "") +
    ` · resultado <span class="${resultado < 0 ? "negativo" : "positivo"}">${formatearDolares(resultado)}</span>`;
}

// De lo retirado, la prop firm se queda con su parte: lo que vuelve es el
// porcentaje de reparto del plan.
function retiroNeto(c) {
  if (c.retiro_acumulado == null) return null;
  const reparto = plantillaDe(c)?.reparto_pct ?? 100;
  return Number(c.retiro_acumulado) * reparto / 100;
}

function campoPrecio(c) {
  // Texto y no número: el precio se escribe una sola vez y no tiene por qué
  // tener flechas ni cambiar sin querer con la rueda del mouse.
  const input = document.createElement("input");
  input.type = "text";
  input.inputMode = "decimal";
  input.className = "campo-precio";
  input.value = c.precio_compra ?? "";
  input.placeholder = "-";

  input.addEventListener("change", async () => {
    const limpio = input.value.trim().replace(",", ".");
    const valor = limpio === "" ? null : Number(limpio);
    if (valor != null && Number.isNaN(valor)) {
      alert("El precio tiene que ser un número.");
      input.value = c.precio_compra ?? "";
      return;
    }
    const { error } = await sb.from("cuentas").update({ precio_compra: valor }).eq("id", c.id);
    if (error) {
      alert("No se pudo guardar el precio: " + error.message);
      return;
    }
    refrescar();
  });

  return input;
}

// El balance se calcula sobre TODAS las cuentas, no sobre las que están a la
// vista: si una se oculta por inactividad, lo que costó y lo que dejó sigue
// contando.
let balance = { invertido: 0, recuperado: 0 };

async function cargarBalance() {
  const { data } = await sb.from("balance_financiero").select("*").limit(1);
  if (data?.[0]) {
    balance = {
      invertido: Number(data[0].invertido) || 0,
      recuperado: Number(data[0].recuperado) || 0,
    };
  }
}

function filaDeTotales() {
  const resultado = balance.recuperado - balance.invertido;

  const fila = document.createElement("tr");
  fila.className = "fila-total";
  fila.innerHTML = `
    <td colspan="12">
      Resultado de la operación
      <span class="${resultado < 0 ? "negativo" : "positivo"}">${formatearDolares(resultado)}</span>
    </td>
    <td>${formatearDolares(balance.invertido)}</td>
    <td>${formatearDolares(balance.recuperado)}</td>
  `;
  return fila;
}

function plantillaDe(c) {
  return plantillasCache.find(
    (p) => p.prop_firm === c.prop_firm && p.plan === c.plan && p.fase === c.fase
  );
}

// Desplegable genérico para elegir plan o fase. Mientras no haya plantillas
// cargadas para esa prop firm, muestra el valor como texto.
function selectorDeCuenta(cuenta, campo, opciones) {
  if (!opciones.length) {
    const texto = document.createElement("span");
    texto.textContent = cuenta[campo] ?? "-";
    return texto;
  }

  const select = document.createElement("select");
  select.className = "select-fase";
  select.innerHTML = `<option value="">— elegir —</option>` +
    opciones.map((o) => `<option value="${o}">${o}</option>`).join("");
  select.value = cuenta[campo] ?? "";

  select.addEventListener("change", async () => {
    const { error } = await sb
      .from("cuentas")
      .update({ [campo]: select.value || null })
      .eq("id", cuenta.id);
    if (error) {
      alert(`No se pudo guardar: ${error.message}`);
      return;
    }
    refrescar();
  });

  return select;
}

function selectorDePlan(cuenta) {
  const planes = [...new Set(
    plantillasCache.filter((p) => p.prop_firm === cuenta.prop_firm).map((p) => p.plan)
  )].filter(Boolean);
  return selectorDeCuenta(cuenta, "plan", planes);
}

// Pérdida por operación que dispara una advertencia de la prop firm. Se
// muestra en dinero y en porcentaje: "600,00 | 1,2%".
function textoIdeaTrade(c) {
  if (c.trade_idea == null) return "-";
  const monto = formatearEntero(c.trade_idea);
  const pct = plantillaDe(c)?.trade_idea_pct;
  return pct != null ? `${monto} | ${String(pct).replace(".", ",")}%` : monto;
}

// Convierte los porcentajes de la prop firm en los límites en dinero de esta
// cuenta, y completa el tamaño con el depósito inicial que registró MT5. Solo
// rellena lo que esté vacío: nunca pisa un valor cargado a mano.
async function completarReglas(c) {
  if (!c.prop_firm || !c.fase) return false;

  const plantilla = plantillaDe(c);
  if (!plantilla) return false;

  const saldoInicial = c.saldo_inicial ?? c.deposito_inicial;
  if (!saldoInicial) return false;

  const cambios = {};
  if (c.saldo_inicial == null) cambios.saldo_inicial = saldoInicial;

  const enDinero = {
    perdida_diaria_max: plantilla.perdida_diaria_max_pct,
    drawdown_max: plantilla.drawdown_max_pct,
    objetivo_fase: plantilla.objetivo_fase_pct,
    trade_idea: plantilla.trade_idea_pct,
  };
  for (const [campo, pct] of Object.entries(enDinero)) {
    if (pct != null && c[campo] == null) {
      cambios[campo] = Number((saldoInicial * pct / 100).toFixed(2));
    }
  }
  for (const campo of ["min_dias_trading", "hora_reset", "zona_horaria"]) {
    if (plantilla[campo] != null && c[campo] == null) cambios[campo] = plantilla[campo];
  }

  if (!Object.keys(cambios).length) return false;

  cambios.cuenta_id = c.id;
  const { error } = await sb.from("reglas").upsert(cambios, { onConflict: "cuenta_id" });
  if (error) {
    console.warn("No se pudieron completar las reglas:", error.message);
    return false;
  }
  return true;
}

// La fase es lo único que MT5 no puede saber, así que se elige acá. Al
// guardarla, el panel aplica los límites de la plantilla que corresponda.
function selectorDeFase(cuenta) {
  // Las fases disponibles dependen del plan: no es lo mismo uno de 1 paso
  // que uno de 2.
  const fases = plantillasCache
    .filter((p) => p.prop_firm === cuenta.prop_firm && p.plan === cuenta.plan)
    .map((p) => p.fase);
  return selectorDeCuenta(cuenta, "fase", fases);
}

// ---------------------------------------------------------------
// Reporte descargable
// ---------------------------------------------------------------

// Excel en español espera punto y coma como separador y coma decimal.
function celda(v) {
  if (v == null) return "";
  if (typeof v === "number") return String(v.toFixed(2)).replace(".", ",");
  return `"${String(v).replace(/"/g, '""')}"`;
}

function aCsv(filas) {
  return filas.map((f) => f.map(celda).join(";")).join("\r\n");
}

document.getElementById("btn-reporte").addEventListener("click", async () => {
  // El histórico completo, incluidas las cuentas que ya no se muestran.
  const { data, error } = await sb.from("flujo_mensual").select("*");
  if (error) {
    alert("No se pudo generar el reporte: " + error.message);
    return;
  }

  const filas = [
    ["FLUJO MENSUAL POR TIPO DE OPERACIÓN"],
    ["Mes", "Tipo", "Gastos", "Ingresos", "Neto"],
  ];

  const porTipo = {};
  for (const m of data) {
    const g = Number(m.gastos) || 0;
    const i = Number(m.ingresos) || 0;
    const tipo = m.metodo || "Sin asignar";
    filas.push([m.mes, tipo, g, i, i - g]);

    porTipo[tipo] = porTipo[tipo] || { gastos: 0, ingresos: 0 };
    porTipo[tipo].gastos += g;
    porTipo[tipo].ingresos += i;
  }

  filas.push([], ["TOTALES POR TIPO"], ["Tipo", "Gastos", "Ingresos", "Neto"]);
  let gastos = 0, ingresos = 0;
  for (const [tipo, t] of Object.entries(porTipo)) {
    filas.push([tipo, t.gastos, t.ingresos, t.ingresos - t.gastos]);
    gastos += t.gastos;
    ingresos += t.ingresos;
  }
  filas.push(["Total", gastos, ingresos, ingresos - gastos]);

  // El BOM es lo que hace que Excel respete los acentos.
  const blob = new Blob(["﻿" + aCsv(filas)], { type: "text/csv;charset=utf-8" });
  const enlace = document.createElement("a");
  enlace.href = URL.createObjectURL(blob);
  enlace.download = `monitoreo-mt5-${new Date().toISOString().slice(0, 10)}.csv`;
  enlace.click();
  URL.revokeObjectURL(enlace.href);
});

// ---------------------------------------------------------------
// Plantillas de reglas por prop firm + fase
// ---------------------------------------------------------------

async function cargarPlantillas() {
  const { data, error } = await sb
    .from("reglas_plantillas")
    .select("*")
    .order("prop_firm")
    .order("plan")
    .order("fase");

  if (error) {
    cuerpoPlantillas.innerHTML = `<tr><td colspan="10" class="error">Error: ${error.message}</td></tr>`;
    return;
  }

  plantillasCache = data;
  renderizarPlantillas();
}

function renderizarPlantillas() {
  cuerpoPlantillas.innerHTML = "";
  for (const p of plantillasCache) {
    const fila = document.createElement("tr");
    fila.innerHTML = `
      <td>${p.prop_firm}</td>
      <td>${p.plan ?? "-"}</td>
      <td>${p.fase}</td>
      <td>${formatearPct(p.perdida_diaria_max_pct)}</td>
      <td>${formatearPct(p.drawdown_max_pct)}</td>
      <td>${formatearPct(p.objetivo_fase_pct)}</td>
      <td>${p.min_dias_trading ?? "-"}</td>
      <td>${formatearPct(p.trade_idea_pct)}</td>
      <td>${p.hora_reset ?? "-"} ${p.zona_horaria ?? ""}</td>
      <td><button type="button" class="btn-borrar-plantilla">Borrar</button></td>
    `;
    fila.querySelector(".btn-borrar-plantilla").addEventListener("click", () => borrarPlantilla(p.id));
    cuerpoPlantillas.appendChild(fila);
  }
}

formPlantilla.addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const form = ev.target;
  const datos = {};
  for (const campo of ["prop_firm", "plan", "fase", "perdida_diaria_max_pct", "drawdown_max_pct", "objetivo_fase_pct", "min_dias_trading", "trade_idea_pct", "hora_reset", "zona_horaria", "fuente_url"]) {
    const valor = form.elements[campo].value;
    datos[campo] = valor === "" ? null : valor;
  }

  const { error } = await sb.from("reglas_plantillas").upsert(datos, { onConflict: "prop_firm,plan,fase" });
  if (error) {
    alert("No se pudo guardar la plantilla: " + error.message);
    return;
  }
  form.reset();
  form.elements.zona_horaria.value = "UTC";
  await cargarPlantillas();
});

async function borrarPlantilla(id) {
  if (!confirm("¿Borrar esta plantilla?")) return;
  const { error } = await sb.from("reglas_plantillas").delete().eq("id", id);
  if (error) {
    alert("No se pudo borrar: " + error.message);
    return;
  }
  await cargarPlantillas();
}

// ---------------------------------------------------------------
// Formato
// ---------------------------------------------------------------

function ponerMetrica(nodo, selector, valor, coloreable) {
  const el = nodo.querySelector(selector);
  el.textContent = formatearMoneda(valor);
  if (coloreable && valor != null) {
    el.classList.add(valor < 0 ? "negativo" : "positivo");
  }
}

function formatearMoneda(v) {
  if (v == null) return "-";
  return Number(v).toLocaleString("es", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatearEntero(v) {
  if (v == null) return "-";
  return Number(v).toLocaleString("es", { maximumFractionDigits: 0 });
}

// Solo para lo que entra y sale de tu bolsillo: precios pagados y retiros.
// El signo va antes del símbolo ("-$1.234"), no entre medio.
function formatearDolares(v) {
  if (v == null) return "-";
  const n = Number(v);
  return `${n < 0 ? "-" : ""}$${Math.abs(n).toLocaleString("es", { maximumFractionDigits: 0 })}`;
}

function formatearPct(v) {
  if (v == null) return "-";
  return `${v}%`;
}

// ---------------------------------------------------------------
// Arranque
// ---------------------------------------------------------------

(async () => {
  const { data: { session } } = await sb.auth.getSession();
  if (session) mostrarPanel();
  else mostrarLogin();
})();
