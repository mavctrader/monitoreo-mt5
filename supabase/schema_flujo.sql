-- Flujo mensual de gastos e ingresos, por tipo de operación, y el balance
-- acumulado que sale de ahí.
--
-- Estas dos vistas se habían creado sueltas en el editor de Supabase y nunca
-- quedaron en el repositorio. Esta es su definición, ya con los retiros
-- cargados a mano incluidos.
--
-- Los ingresos tienen dos orígenes y hay que evitar contarlos dos veces:
--   - el historial de MT5, cuando la prop firm paga dentro de la cuenta
--   - la tabla `retiros`, cuando paga por fuera (y ahí sabemos el neto real
--     y si la solicitud salió rechazada)
-- Una cuenta que tenga retiros cargados a mano deja de sumar por el primero.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

drop view if exists balance_financiero;
drop view if exists flujo_mensual;

create view flujo_mensual
with (security_invoker = true) as
with base as (
  select
    c.id as cuenta_id,
    c.metodo,
    coalesce(p.reparto_pct, 100::numeric) as pct,
    c.precio_compra,
    -- El mes de compra es el del primer ingreso de dinero; si nunca reportó
    -- uno, el día que la cuenta se dio de alta.
    coalesce((select min(mv.ocurrido_en) from movimientos mv
               where mv.cuenta_id = c.id and mv.monto > 0::numeric), c.alta_en) as comprada_en
  from cuentas c
  left join reglas_plantillas p
         on p.prop_firm = c.prop_firm and p.plan = c.plan and p.fase = c.fase
)
select
  mes,
  metodo,
  sum(gastos)   as gastos,
  sum(ingresos) as ingresos
from (
  -- Lo que pagaste por cada cuenta, en el mes en que la compraste
  select date_trunc('month'::text, b.comprada_en)::date as mes,
         b.metodo,
         b.precio_compra as gastos,
         0 as ingresos
  from base b
  where b.precio_compra is not null

  union all

  -- Retiros que salieron de la cuenta y quedaron en el historial de MT5
  select date_trunc('month'::text, mv.ocurrido_en)::date,
         b.metodo,
         0,
         (- mv.monto) * b.pct / 100::numeric
  from movimientos mv
  join base b on b.cuenta_id = mv.cuenta_id
  where mv.monto < 0::numeric
    and not exists (select 1 from retiros r where r.cuenta_id = mv.cuenta_id)

  union all

  -- Retiros cargados a mano: ya traen el neto que la prop firm pagó. Los
  -- rechazados no entran: nunca fueron un ingreso.
  select date_trunc('month'::text, coalesce(r.solicitado_en, r.creado_en::date))::date,
         b.metodo,
         0,
         coalesce(r.neto, r.bruto * b.pct / 100::numeric)
  from retiros r
  join base b on b.cuenta_id = r.cuenta_id
  where r.estado = 'aprobado'

  union all

  -- Gastos sueltos que no son compra de cuenta
  select date_trunc('month'::text, g.fecha::timestamp with time zone)::date,
         g.metodo,
         g.monto,
         0
  from gastos g
) t
group by mes, metodo
order by mes desc, metodo;


create view balance_financiero
with (security_invoker = true) as
select
  coalesce((select sum(flujo_mensual.gastos)   from flujo_mensual), 0::numeric) as invertido,
  coalesce((select sum(flujo_mensual.ingresos) from flujo_mensual), 0::numeric) as recuperado;
