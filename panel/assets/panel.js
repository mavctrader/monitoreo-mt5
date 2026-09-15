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
const plantillaBot = document.getElementById("plantilla-bot");

let temporizadorRefresco = null;

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
  cargarCuentas();
  if (temporizadorRefresco) clearInterval(temporizadorRefresco);
  temporizadorRefresco = setInterval(cargarCuentas, INTERVALO_REFRESCO_MS);
}

// ---------------------------------------------------------------
// Datos
// ---------------------------------------------------------------

async function cargarCuentas() {
  const { data, error } = await sb
    .from("cuentas")
    .select("*, estado(*), reglas(*), bots(*), posiciones(*)")
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
  for (const cuenta of data) {
    listaCuentas.appendChild(renderizarCuenta(cuenta));
  }
}

function renderizarCuenta(cuenta) {
  const nodo = plantillaCuenta.content.cloneNode(true);
  const estado = cuenta.estado; // 1:1
  const reglas = cuenta.reglas; // 1:1

  nodo.querySelector(".cuenta-alias").textContent = cuenta.alias || `Cuenta ${cuenta.login}`;
  nodo.querySelector(".cuenta-login").textContent = `#${cuenta.login}`;
  nodo.querySelector(".cuenta-broker").textContent = cuenta.broker || "";

  const indAlgo = nodo.querySelector(".algo-trading");
  const indSeñal = nodo.querySelector("[title='Señal de vida']");

  if (estado) {
    indAlgo.classList.add(estado.algo_trading ? "on" : "off");
    const segundos = (Date.now() - new Date(estado.visto_en).getTime()) / 1000;
    indSeñal.classList.add(segundos <= SEGUNDOS_SEÑAL_VIDA ? "on" : "off");
    indSeñal.title = segundos <= SEGUNDOS_SEÑAL_VIDA
      ? "Con señal"
      : `Sin señal hace ${Math.round(segundos)}s`;

    ponerMetrica(nodo, ".m-saldo", estado.saldo);
    ponerMetrica(nodo, ".m-equity", estado.equity);
    ponerMetrica(nodo, ".m-flotante", estado.flotante, true);
    ponerMetrica(nodo, ".m-margen", estado.margen_libre);
  } else {
    indSeñal.classList.add("off");
    indSeñal.title = "Nunca dio señal";
  }

  const elDrawdown = nodo.querySelector(".m-drawdown");
  if (reglas?.drawdown_max != null && reglas?.saldo_inicial != null && estado) {
    const restante = reglas.drawdown_max - (reglas.saldo_inicial - estado.equity);
    elDrawdown.textContent = formatearMoneda(restante);
    elDrawdown.classList.add(restante < 0 ? "negativo" : "positivo");
  } else {
    elDrawdown.textContent = "Sin reglas";
  }

  // Bots
  const listaBots = nodo.querySelector(".lista-bots");
  if (!cuenta.bots.length) {
    listaBots.innerHTML = `<p class="aviso">Sin gráficos detectados todavía.</p>`;
  }
  for (const bot of cuenta.bots) {
    listaBots.appendChild(renderizarBot(cuenta.id, bot));
  }

  // Posiciones
  const cuerpoTabla = nodo.querySelector(".tabla-posiciones tbody");
  const avisoSinPosiciones = nodo.querySelector(".sin-posiciones");
  if (!cuenta.posiciones.length) {
    avisoSinPosiciones.hidden = false;
  } else {
    for (const p of cuenta.posiciones) {
      const fila = document.createElement("tr");
      fila.innerHTML = `
        <td>${p.simbolo ?? ""}</td>
        <td>${p.tipo ?? ""}</td>
        <td>${p.volumen ?? ""}</td>
        <td>${formatearNumero(p.apertura)}</td>
        <td>${formatearNumero(p.sl)}</td>
        <td>${formatearNumero(p.tp)}</td>
        <td class="${(p.beneficio ?? 0) < 0 ? "negativo" : "positivo"}">${formatearMoneda(p.beneficio)}</td>
      `;
      cuerpoTabla.appendChild(fila);
    }
  }

  // Reglas
  const formReglas = nodo.querySelector(".form-reglas");
  if (reglas) {
    for (const campo of ["saldo_inicial", "perdida_diaria_max", "drawdown_max", "objetivo_fase", "hora_reset", "zona_horaria"]) {
      if (reglas[campo] != null) formReglas.elements[campo].value = reglas[campo];
    }
  }
  formReglas.addEventListener("submit", (ev) => guardarReglas(ev, cuenta.id));

  return nodo;
}

function renderizarBot(cuentaId, bot) {
  const nodo = plantillaBot.content.cloneNode(true);
  nodo.querySelector(".bot-nombre").textContent = `${bot.simbolo ?? "?"} ${bot.periodo ?? ""}`.trim();
  nodo.querySelector(".bot-confirmado").textContent = bot.confirmado ? `· ${bot.confirmado}` : "";

  nodo.querySelector(".btn-arrancar").addEventListener("click", () => crearOrden(cuentaId, bot.id, "ARRANCAR"));
  nodo.querySelector(".btn-parar").addEventListener("click", () => crearOrden(cuentaId, bot.id, "PARAR"));
  nodo.querySelector(".btn-descargar").addEventListener("click", () => {
    if (confirm("Descargar cierra el gráfico del bot. Es el último recurso, no el botón de todos los días. ¿Seguro?")) {
      crearOrden(cuentaId, bot.id, "DESCARGAR");
    }
  });

  return nodo;
}

async function crearOrden(cuentaId, botId, tipo) {
  const { error } = await sb.from("ordenes").insert({
    cuenta_id: cuentaId,
    bot_id: botId,
    tipo,
    estado: "pendiente",
  });
  if (error) {
    alert("No se pudo mandar la orden: " + error.message);
    return;
  }
  setTimeout(cargarCuentas, 1500);
}

async function guardarReglas(ev, cuentaId) {
  ev.preventDefault();
  const form = ev.target;
  const datos = { cuenta_id: cuentaId };
  for (const campo of ["saldo_inicial", "perdida_diaria_max", "drawdown_max", "objetivo_fase", "hora_reset", "zona_horaria"]) {
    const valor = form.elements[campo].value;
    datos[campo] = valor === "" ? null : valor;
  }

  const { error } = await sb.from("reglas").upsert(datos, { onConflict: "cuenta_id" });
  const aviso = form.querySelector(".guardado-ok");
  if (error) {
    alert("No se pudieron guardar las reglas: " + error.message);
    return;
  }
  aviso.hidden = false;
  setTimeout(() => { aviso.hidden = true; }, 2000);
  cargarCuentas();
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

function formatearNumero(v) {
  if (v == null) return "-";
  return Number(v).toLocaleString("es", { maximumFractionDigits: 5 });
}

// ---------------------------------------------------------------
// Arranque
// ---------------------------------------------------------------

(async () => {
  const { data: { session } } = await sb.auth.getSession();
  if (session) mostrarPanel();
  else mostrarLogin();
})();
