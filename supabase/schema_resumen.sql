-- Estado general de cada cuenta de fondeo, para la línea horizontal del panel:
-- prop firm | fase | cuenta | tamaño | saldo | días operados/mínimos |
-- días inactiva | passed/failed | retiro acumulado
--
-- Correr en el SQL Editor de Supabase (rol postgres).

alter table cuentas add column if not exists resultado text check (resultado in ('passed', 'failed'));
alter table cuentas add column if not exists retiro_acumulado numeric;

alter table reglas add column if not exists min_dias_trading integer;
alter table reglas add column if not exists dias_inactividad_max integer default 30;

-- Cada cuenta hereda los días mínimos de la plantilla de su prop firm y fase.
update reglas r
set min_dias_trading = p.min_dias_trading
from cuentas c, reglas_plantillas p
where r.cuenta_id = c.id
  and p.prop_firm = c.prop_firm
  and p.fase = c.fase
  and r.min_dias_trading is null;

-- Los días se cuentan contra la hora de reset de la prop firm, no contra la
-- medianoche local, para que coincidan con lo que muestran sus paneles.
create or replace view resumen_cuentas
with (security_invoker = true) as
select
  c.id,
  c.login,
  c.prop_firm,
  c.fase,
  c.alias,
  c.activa,
  c.resultado,
  -- Lo retirado sale del historial de MT5; el campo manual solo sirve de
  -- respaldo cuando la prop firm paga por fuera de la cuenta.
  coalesce(m.retirado, c.retiro_acumulado) as retiro_acumulado,
  r.saldo_inicial,
  r.objetivo_fase,
  r.drawdown_max,
  r.perdida_diaria_max,
  r.min_dias_trading,
  r.dias_inactividad_max,
  r.hora_reset,
  r.zona_horaria,
  -- Primer ingreso de dinero del historial: el tamaño con el que se compró
  -- la cuenta. Sirve para completar saldo_inicial sin cargarlo a mano.
  (select mv.monto from movimientos mv
    where mv.cuenta_id = c.id and mv.monto > 0
    order by mv.ocurrido_en limit 1) as deposito_inicial,
  e.saldo,
  e.equity,
  e.visto_en,
  d.dias_operados,
  d.dias_inactividad,
  case
    -- Sin reglas cargadas no es una cuenta de fondeo: no hay nada que juzgar.
    when r.saldo_inicial is null then null
    when c.resultado is not null then c.resultado
    when r.saldo_inicial is not null and r.drawdown_max is not null
         and e.equity <= r.saldo_inicial - r.drawdown_max then 'failed'
    when d.dias_inactividad is not null and r.dias_inactividad_max is not null
         and d.dias_inactividad >= r.dias_inactividad_max then 'failed'
    when r.objetivo_fase is not null and r.saldo_inicial is not null
         and e.equity - r.saldo_inicial >= r.objetivo_fase
         and coalesce(d.dias_operados, 0) >= coalesce(r.min_dias_trading, 0)
         and not exists (select 1 from posiciones p where p.cuenta_id = c.id) then 'passed'
    else 'en curso'
  end as estado_cuenta
from cuentas c
left join reglas r on r.cuenta_id = c.id
left join estado e on e.cuenta_id = c.id
left join lateral (
  -- Se cuentan los días en que se ABRIÓ alguna operación, que es como lo
  -- miden las prop firms. Incluye las posiciones todavía abiertas: si se
  -- abrió algo hoy y sigue vivo, no está en el histórico pero cuenta igual.
  select
    count(distinct f.dia) as dias_operados,
    ((now() at time zone coalesce(r.zona_horaria, 'Europe/Athens'))::date - max(f.dia)) as dias_inactividad
  from (
    select (o.abierta_en at time zone coalesce(r.zona_horaria, 'Europe/Athens'))::date as dia
    from operaciones o
    where o.cuenta_id = c.id and o.abierta_en is not null
    union all
    select (p.abierta_en at time zone coalesce(r.zona_horaria, 'Europe/Athens'))::date
    from posiciones p
    where p.cuenta_id = c.id and p.abierta_en is not null
  ) f
) d on true
left join lateral (
  select sum(-mv.monto) as retirado
  from movimientos mv
  where mv.cuenta_id = c.id and mv.monto < 0
) m on true;
