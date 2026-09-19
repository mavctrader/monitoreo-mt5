-- Resultado por activo de cada cuenta: cuánto le suma o le resta cada
-- símbolo al portafolio, con sus costos y su peor caída a la vista.
--
-- Pensado para las cuentas de capital inversor (Darwinex Zero), que se
-- manejan como un portafolio y no como una cuenta de fondeo: ahí lo que
-- interesa no es el colchón contra un límite, sino qué instrumento aporta.
--
-- Sirve igual para cualquier cuenta, así que la vista no filtra por tipo.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

-- El swap que llevan acumulado las posiciones todavía abiertas. Lo reporta
-- el recolector de capital inversor; los otros no lo mandan y queda vacío.
alter table posiciones add column if not exists swap numeric;

-- Peor caída de cada activo desde su mejor momento, y cuándo tocó fondo.
-- Se arma con la curva de resultado acumulado de ese símbolo, operación
-- cerrada tras operación cerrada.
drop view if exists drawdown_activos;

create view drawdown_activos
with (security_invoker = true) as
with curva as (
  select
    o.cuenta_id,
    o.simbolo,
    o.cerrada_en,
    sum(coalesce(o.beneficio, 0) + coalesce(o.comision, 0) + coalesce(o.swap, 0))
      over (partition by o.cuenta_id, o.simbolo
            order by o.cerrada_en, o.ticket
            rows between unbounded preceding and current row) as acumulado
  from operaciones o
  where o.simbolo is not null and o.cerrada_en is not null
),
con_pico as (
  select
    c.*,
    -- El pico arranca en cero: si la primera operación ya pierde, esa
    -- pérdida es drawdown igual.
    greatest(0, max(c.acumulado) over (
      partition by c.cuenta_id, c.simbolo
      order by c.cerrada_en
      rows between unbounded preceding and current row)) as pico
  from curva c
)
select distinct on (cuenta_id, simbolo)
  cuenta_id,
  simbolo,
  (acumulado - pico) as drawdown_max,
  cerrada_en as drawdown_en
from con_pico
order by cuenta_id, simbolo, (acumulado - pico) asc, cerrada_en asc;


drop view if exists resumen_activos;

create view resumen_activos
with (security_invoker = true) as
select
  t.cuenta_id,
  t.simbolo,
  t.cerradas,
  t.abiertas,
  t.beneficio,
  t.flotante,
  t.comision,
  t.swap,
  t.spread,
  t.neto,
  dd.drawdown_max,
  dd.drawdown_en
from (
  select
    x.cuenta_id,
    x.simbolo,
    sum(x.cerradas)::int as cerradas,
    sum(x.abiertas)::int as abiertas,
    sum(x.beneficio)     as beneficio,
    sum(x.flotante)      as flotante,
    sum(x.comision)      as comision,
    sum(x.swap)          as swap,
    sum(x.spread)        as spread,
    -- Lo que el activo le pone o le saca al portafolio. La comisión ya viene
    -- en negativo y el swap con su signo, así que se suman.
    --
    -- El spread NO se resta acá a propósito: es lo que costó cruzar la
    -- horquilla al abrir, y eso ya está metido en el precio de entrada, o sea
    -- ya está descontado del beneficio. Se muestra aparte para saber cuánto
    -- del resultado se fue en eso, pero restarlo otra vez sería contarlo dos
    -- veces.
    sum(x.beneficio) + sum(x.flotante) + sum(x.comision) + sum(x.swap) as neto
  from (
    -- Operaciones ya cerradas
    select
      o.cuenta_id, o.simbolo,
      1 as cerradas, 0 as abiertas,
      coalesce(o.beneficio, 0) as beneficio,
      0::numeric as flotante,
      coalesce(o.comision, 0) as comision,
      coalesce(o.swap, 0) as swap,
      0::numeric as spread
    from operaciones o
    where o.simbolo is not null

    union all

    -- Posiciones todavía abiertas: entran por el flotante, y con el swap que
    -- ya llevan acumulado sin haberse cerrado
    select
      p.cuenta_id, p.simbolo,
      0, 1,
      0::numeric,
      coalesce(p.beneficio, 0),
      0::numeric,
      coalesce(p.swap, 0),
      0::numeric
    from posiciones p
    where p.simbolo is not null

    union all

    -- Spread medido por el recolector al abrir cada posición
    select
      s.cuenta_id, s.simbolo,
      0, 0,
      0::numeric, 0::numeric, 0::numeric, 0::numeric,
      coalesce(s.costo, 0)
    from spreads s
    where s.simbolo is not null
  ) x
  group by x.cuenta_id, x.simbolo
) t
left join drawdown_activos dd
       on dd.cuenta_id = t.cuenta_id and dd.simbolo = t.simbolo;
