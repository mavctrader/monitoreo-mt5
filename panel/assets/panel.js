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

const SEGUNDOS_SEÑAL_VIDA = 90; // más que esto sin novedades = cuenta marcada en rojo
const INTERVALO_REFRESCO_MS = 10_000;

const vistaLogin = document.getElementById("vista-login");
const vistaPanel = document.getElementById("vista-panel");
const formLogin = document.getElementById("form-login");
const errorLogin = document.getElementById("error-login");
const listaCuentas = document.getElementById("lista-cuentas");
const btnSalir = document.getElementById("btn-salir");
const plantillaCuenta = document.getElementById("plantilla-cuenta");
const cuerpoPlantillas = document.getElementById("cuerpo-plantillas");
const formPlantilla = document.getElementById("form-plantilla");

let temporizadorRefresco = null;
let plantillasCache = [];

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
  cargarPlantillas().then(cargarCuentas);
  if (temporizadorRefresco) clearInterval(temporizadorRefresco);
  temporizadorRefresco = setInterval(cargarCuentas, INTERVALO_REFRESCO_MS);
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

  if (!data.length) {
    listaCuentas.innerHTML = `<p class="aviso">Todavía no hay cuentas dando señales.</p>`;
    return;
  }

  listaCuentas.innerHTML = "";

  const grupos = new Map();
  const sueltas = [];
  for (const cuenta of data) {
    if (cuenta.grupo) {
      if (!grupos.has(cuenta.grupo)) grupos.set(cuenta.grupo, []);
      grupos.get(cuenta.grupo).push(cuenta);
    } else {
      sueltas.push(cuenta);
    }
  }

  for (const [nombreGrupo, cuentasDelGrupo] of grupos) {
    listaCuentas.appendChild(renderizarPar(nombreGrupo, cuentasDelGrupo));
  }
  for (const cuenta of sueltas) {
    listaCuentas.appendChild(renderizarCuenta(cuenta));
  }
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

  return contenedor;
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
// Plantillas de reglas por prop firm + fase
// ---------------------------------------------------------------

async function cargarPlantillas() {
  const { data, error } = await sb
    .from("reglas_plantillas")
    .select("*")
    .order("prop_firm")
    .order("fase");

  if (error) {
    cuerpoPlantillas.innerHTML = `<tr><td colspan="8" class="error">Error: ${error.message}</td></tr>`;
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
      <td>${p.fase}</td>
      <td>${formatearPct(p.perdida_diaria_max_pct)}</td>
      <td>${formatearPct(p.drawdown_max_pct)}</td>
      <td>${formatearPct(p.objetivo_fase_pct)}</td>
      <td>${p.min_dias_trading ?? "-"}</td>
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
  for (const campo of ["prop_firm", "fase", "perdida_diaria_max_pct", "drawdown_max_pct", "objetivo_fase_pct", "min_dias_trading", "hora_reset", "zona_horaria", "fuente_url"]) {
    const valor = form.elements[campo].value;
    datos[campo] = valor === "" ? null : valor;
  }

  const { error } = await sb.from("reglas_plantillas").upsert(datos, { onConflict: "prop_firm,fase" });
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
