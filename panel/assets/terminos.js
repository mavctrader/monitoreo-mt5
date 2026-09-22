// Términos de contrato por prop firm. Página aparte del panel: se consulta
// antes de configurar un robot, no en el monitoreo del día a día.
//
// Comparte el mismo proyecto de Supabase y la misma sesión que el panel
// (supabase-js la guarda en el navegador), así que si ya entraste allá, acá
// entrás derecho.

const SUPABASE_URL = "https://wjmupiiwwwngigqyggex.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_YZQ9ZA7GMFJJrceE4uLVIw_-4xFmXZG";

// Igual que en el panel: no se llama "supabase" para no chocar con el objeto
// global de la librería.
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const vistaLogin = document.getElementById("vista-login");
const vistaTerminos = document.getElementById("vista-terminos");
const formLogin = document.getElementById("form-login");
const errorLogin = document.getElementById("error-login");
const listaFirmas = document.getElementById("lista-firmas");
const detalle = document.getElementById("detalle");
const tituloFirma = document.getElementById("titulo-firma");
const actualizado = document.getElementById("actualizado");
const campoNotas = document.getElementById("notas");
const campoFuente = document.getElementById("fuente");
const btnGuardar = document.getElementById("btn-guardar");
const abrirFuente = document.getElementById("abrir-fuente");
const estadoGuardado = document.getElementById("estado-guardado");
const formFirma = document.getElementById("form-firma");

let firmas = [];
let firmaActual = null;

// ---------------------------------------------------------------
// Autenticación
// ---------------------------------------------------------------

formLogin.addEventListener("submit", async (ev) => {
  ev.preventDefault();
  errorLogin.textContent = "";
  const { error } = await sb.auth.signInWithPassword({
    email: document.getElementById("email").value.trim(),
    password: document.getElementById("password").value,
  });
  if (error) errorLogin.textContent = "No se pudo entrar: " + error.message;
});

sb.auth.onAuthStateChange((_evento, sesion) => {
  vistaLogin.hidden = !!sesion;
  vistaTerminos.hidden = !sesion;
  if (sesion) cargarFirmas();
});

// ---------------------------------------------------------------
// Firmas
// ---------------------------------------------------------------

async function cargarFirmas() {
  const { data, error } = await sb
    .from("terminos_firma")
    .select("*")
    .order("prop_firm");

  if (error) {
    listaFirmas.innerHTML = `<p class="error">${error.message}</p>`;
    return;
  }

  firmas = data;
  dibujarLista();

  // Si la URL trae ?firma=... se abre esa directo: así el botón del panel
  // puede llevarte a la firma de la cuenta que estabas mirando.
  const pedida = new URLSearchParams(location.search).get("firma");
  const abrir = pedida && firmas.find((f) => f.prop_firm === pedida);
  if (abrir) mostrar(abrir.prop_firm);
  else if (firmaActual) mostrar(firmaActual);
}

function dibujarLista() {
  listaFirmas.innerHTML = "";
  if (!firmas.length) {
    listaFirmas.innerHTML = `<p class="tenue">Todavía no hay ninguna firma cargada.</p>`;
    return;
  }
  for (const f of firmas) {
    const boton = document.createElement("button");
    boton.className = "firma" + (f.prop_firm === firmaActual ? " activa" : "");
    // Un punto al lado de las que todavía están en blanco, para ver de un
    // golpe cuáles te falta escribir.
    boton.innerHTML = `${f.prop_firm}${f.notas && f.notas.trim() ? "" : `<span class="sin-datos" title="Sin términos cargados">·</span>`}`;
    boton.addEventListener("click", () => mostrar(f.prop_firm));
    listaFirmas.appendChild(boton);
  }
}

function mostrar(nombre) {
  const f = firmas.find((x) => x.prop_firm === nombre);
  if (!f) return;

  firmaActual = nombre;
  detalle.hidden = false;
  tituloFirma.textContent = nombre;
  campoNotas.value = f.notas || "";
  campoFuente.value = f.fuente_url || "";
  estadoGuardado.textContent = "";

  actualizado.textContent = f.notas && f.notas.trim()
    ? `actualizado el ${new Date(f.actualizado_en).toLocaleDateString("es", { day: "2-digit", month: "2-digit", year: "numeric" })}`
    : "sin cargar";

  abrirFuente.hidden = !f.fuente_url;
  if (f.fuente_url) abrirFuente.href = f.fuente_url;

  dibujarLista();
}

btnGuardar.addEventListener("click", async () => {
  if (!firmaActual) return;

  btnGuardar.disabled = true;
  estadoGuardado.textContent = "Guardando...";

  const { error } = await sb
    .from("terminos_firma")
    .update({
      notas: campoNotas.value,
      fuente_url: campoFuente.value.trim() || null,
      actualizado_en: new Date().toISOString(),
    })
    .eq("prop_firm", firmaActual);

  btnGuardar.disabled = false;

  if (error) {
    estadoGuardado.textContent = "No se pudo guardar: " + error.message;
    estadoGuardado.className = "error";
    return;
  }

  estadoGuardado.textContent = "Guardado";
  estadoGuardado.className = "tenue";
  await cargarFirmas();
});

formFirma.addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const nombre = document.getElementById("firma-nueva").value.trim();
  if (!nombre) return;

  const { error } = await sb.from("terminos_firma").insert({ prop_firm: nombre });
  if (error) {
    alert("No se pudo agregar: " + error.message);
    return;
  }
  document.getElementById("firma-nueva").value = "";
  firmaActual = nombre;
  await cargarFirmas();
});

// Aviso al salir con cambios sin guardar: es justo el dato que no querés
// perder por cerrar la pestaña.
window.addEventListener("beforeunload", (ev) => {
  const f = firmas.find((x) => x.prop_firm === firmaActual);
  if (!f) return;
  const cambio = campoNotas.value !== (f.notas || "")
    || campoFuente.value !== (f.fuente_url || "");
  if (cambio) ev.preventDefault();
});
