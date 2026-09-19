-- Cuentas de capital inversor (tipo = 'capital_inversor').
--
-- No son cuentas de fondeo: no hay prop firm, ni fase, ni objetivo, ni
-- pérdida diaria, ni precio de compra. Lo que importa acá es otra cosa:
-- cuánto capital entró, cuánto se retiró y cuánto se ganó con eso.
--
-- Va en su propia vista y en su propio desplegable del panel, separada de
-- resumen_cuentas, porque los campos no son los mismos.
--
-- Correr en el SQL Editor de Supabase (rol postgres), después de
-- schema_tipo_cuenta.sql.

drop view if exists resumen_inversor;

create view resumen_inversor
with (security_invoker = true) as
select
  c.id,
  c.login,
  c.broker,
  c.alias,
  c.activa,
  e.saldo,
  e.equity,
  e.flotante,
  e.visto_en,
  coalesce(mv.aportado, 0) as aportado,
  coalesce(mv.retirado, 0) as retirado,
  -- Lo ganado desde el primer día: lo que hay en la cuenta, más lo que ya
  -- se sacó, menos todo lo que se puso.
  case
    when e.saldo is null then null
    else e.saldo + coalesce(mv.retirado, 0) - coalesce(mv.aportado, 0)
  end as resultado,
  d.dias_operados,
  d.dias_inactividad
from cuentas c
left join estado e on e.cuenta_id = c.id
left join lateral (
  select
    sum(m.monto) filter (where m.monto > 0) as aportado,
    sum(-m.monto) filter (where m.monto < 0) as retirado
  from movimientos m
  where m.cuenta_id = c.id
) mv on true
left join lateral (
  -- Mismo criterio que en las de fondeo: cuenta el día en que se ABRIÓ una
  -- operación, incluidas las que siguen abiertas. Acá el día se mide en UTC
  -- y no contra una hora de reset, porque no hay prop firm que la imponga.
  select
    count(distinct f.dia) as dias_operados,
    ((now() at time zone 'UTC')::date - max(f.dia)) as dias_inactividad
  from (
    select (o.abierta_en at time zone 'UTC')::date as dia
    from operaciones o
    where o.cuenta_id = c.id and o.abierta_en is not null
    union all
    select (p.abierta_en at time zone 'UTC')::date
    from posiciones p
    where p.cuenta_id = c.id and p.abierta_en is not null
  ) f
) d on true
where c.tipo = 'capital_inversor';
