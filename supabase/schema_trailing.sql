-- Drawdown trailing.
--
-- Hasta ahora todas las prop firms cargadas usaban drawdown estático: el piso
-- es fijo, saldo inicial menos lo permitido. Atlas Funded lo usa trailing: el
-- piso persigue al equity más alto que alcanzó la cuenta y no se detiene
-- nunca.
--
--   piso = equity_maximo - drawdown_max
--
-- La diferencia no es cosmética: en una cuenta de 50.000 que subió a 55.000,
-- el piso estático estaría en 47.500 y el trailing en 52.250. Tratarlo como
-- estático muestra mucho más colchón del que hay.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

-- La marca de agua de cada cuenta: el equity más alto que llegó a tener.
-- La mantiene el agente, nunca baja.
alter table estado add column if not exists equity_maximo numeric;

-- Qué tipo de drawdown usa cada plan, y la copia por cuenta que el panel
-- completa desde la plantilla.
alter table reglas_plantillas add column if not exists drawdown_trailing boolean not null default false;
alter table reglas            add column if not exists drawdown_trailing boolean not null default false;

update reglas_plantillas
   set drawdown_trailing = true
 where prop_firm = 'Atlas Funded';

-- Las cuentas que ya tengan reglas cargadas de ese plan se corrigen también.
update reglas r
   set drawdown_trailing = true
  from cuentas c
 where r.cuenta_id = c.id and c.prop_firm = 'Atlas Funded';

-- Punto de partida de la marca de agua: sin histórico de equity, lo más
-- prudente es arrancar en el saldo inicial. Si la cuenta ya está en ganancia,
-- el agente la sube sola en el primer ciclo.
update estado e
   set equity_maximo = greatest(coalesce(e.equity, 0), coalesce(r.saldo_inicial, 0))
  from reglas r
 where r.cuenta_id = e.cuenta_id and e.equity_maximo is null;
