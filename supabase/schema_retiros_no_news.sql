-- Un castigo por operar en noticia NO es un retiro.
--
-- Atlas Funded le quitó a la cuenta 212153902 la ganancia de una operación
-- hecha en noticia: un movimiento de -596,50 el 10/11/2026 con el comentario
-- "news:20104007". Las dos vistas que cuentan los retiros toman cualquier
-- movimiento negativo del historial de MT5 como plata retirada, así que el
-- panel mostraba "retirado 537" (596,50 x 90% de reparto) en una cuenta de la
-- que no se retiró nada, y lo sumaba como ingreso del mes.
--
-- MT5 no distingue: para el historial las dos cosas son un asiento de balance
-- en negativo. Lo único que las separa es el comentario que escribe la prop
-- firm. Por eso el filtro va por ahí. Si otra firma usa otra palabra para lo
-- mismo, hay que agregarla a las dos condiciones.
--
-- Las dos van con "create or replace": así conservan sus permisos y
-- balance_financiero, que depende de flujo_mensual, no se cae.
--
-- Corrido el 14/11/2026.

create or replace view resumen_cuentas
with (security_invoker = true) as
select
  c.id,
  c.login,
  c.prop_firm,
  c.plan,
  c.fase,
  c.metodo,
  c.orden,
  c.alias,
  c.activa,
  c.resultado,
  c.precio_compra,
  coalesce(m.retirado, c.retiro_acumulado) as retiro_acumulado,
  r.saldo_inicial,
  r.objetivo_fase,
  r.drawdown_max,
  r.perdida_diaria_max,
  r.min_dias_trading,
  r.dias_inactividad_max,
  r.hora_reset,
  r.zona_horaria,
  r.trade_idea,
  dep.monto as deposito_inicial,
  e.saldo,
  e.equity,
  e.visto_en,
  d.dias_operados,
  coalesce(d.dias_inactividad,
           (now() at time zone coalesce(r.zona_horaria, 'Europe/Athens'::text))::date
           - (dep.ocurrido_en at time zone coalesce(r.zona_horaria, 'Europe/Athens'::text))::date)
    as dias_inactividad,
  case
    when r.saldo_inicial is null then null::text
    when c.resultado is not null then c.resultado
    when r.saldo_inicial is not null and r.drawdown_max is not null
         and e.equity <= (r.saldo_inicial - r.drawdown_max) then 'failed'::text
    when d.dias_inactividad is not null and r.dias_inactividad_max is not null
         and d.dias_inactividad >= r.dias_inactividad_max then 'failed'::text
    when r.objetivo_fase is not null and r.saldo_inicial is not null
         and (e.equity - r.saldo_inicial) >= r.objetivo_fase
         and coalesce(d.dias_operados, 0::bigint) >= coalesce(r.min_dias_trading, 0)
         and not (exists (select 1 from posiciones p where p.cuenta_id = c.id))
      then 'passed'::text
    else 'en curso'::text
  end as estado_cuenta
from cuentas c
  left join reglas r on r.cuenta_id = c.id
  left join estado e on e.cuenta_id = c.id
  left join lateral (
    select count(distinct f.dia) as dias_operados,
           (now() at time zone coalesce(r.zona_horaria, 'Europe/Athens'::text))::date
           - max(f.dia) as dias_inactividad
      from (
        select (o.abierta_en at time zone coalesce(r.zona_horaria, 'Europe/Athens'::text))::date as dia
          from operaciones o
         where o.cuenta_id = c.id and o.abierta_en is not null
        union all
        select (p.abierta_en at time zone coalesce(r.zona_horaria, 'Europe/Athens'::text))::date as dia
          from posiciones p
         where p.cuenta_id = c.id and p.abierta_en is not null) f) d on true
  left join lateral (
    select sum(- mv.monto) as retirado
      from movimientos mv
     where mv.cuenta_id = c.id
       and mv.monto < 0::numeric
       -- Lo que la prop firm te quita por romper una regla no es un retiro.
       and coalesce(mv.comentario, '') not like 'news:%') m on true
  left join lateral (
    select mv.monto, mv.ocurrido_en
      from movimientos mv
     where mv.cuenta_id = c.id and mv.monto > 0::numeric
     order by mv.ocurrido_en
     limit 1) dep on true;


create or replace view flujo_mensual
with (security_invoker = true) as
with base as (
  select c.id as cuenta_id,
         c.metodo,
         coalesce(p.reparto_pct, 100::numeric) as pct,
         c.precio_compra,
         coalesce((select min(mv.ocurrido_en) from movimientos mv
                    where mv.cuenta_id = c.id and mv.monto > 0::numeric),
                  c.alta_en) as comprada_en
    from cuentas c
    left join reglas_plantillas p
           on p.prop_firm = c.prop_firm and p.plan = c.plan and p.fase = c.fase
)
select mes, metodo, sum(gastos) as gastos, sum(ingresos) as ingresos
from (
  select date_trunc('month'::text, b.comprada_en)::date as mes,
         b.metodo, b.precio_compra as gastos, 0 as ingresos
    from base b
   where b.precio_compra is not null

  union all

  select date_trunc('month'::text, mv.ocurrido_en)::date,
         b.metodo, 0, (- mv.monto) * b.pct / 100::numeric
    from movimientos mv
    join base b on b.cuenta_id = mv.cuenta_id
   where mv.monto < 0::numeric
     -- Mismo caso que arriba: un castigo no es plata que cobraste.
     and coalesce(mv.comentario, '') not like 'news:%'
     and not (exists (select 1 from retiros r where r.cuenta_id = mv.cuenta_id))

  union all

  select date_trunc('month'::text, coalesce(r.solicitado_en, r.creado_en::date)::timestamptz)::date,
         b.metodo, 0, coalesce(r.neto, r.bruto * b.pct / 100::numeric)
    from retiros r
    join base b on b.cuenta_id = r.cuenta_id
   where r.estado = 'aprobado'::text

  union all

  select date_trunc('month'::text, g.fecha::timestamptz)::date,
         g.metodo, g.monto, 0
    from gastos g) t
group by mes, metodo
order by mes desc, metodo;


-- Verificación: la cuenta de Atlas y el balance general.
select login, retiro_acumulado, saldo, equity
  from resumen_cuentas where login = 212153902;
