-- Cuenta de incubación: un solo terminal MT5 donde conviven varios bots a
-- prueba, cada uno en su gráfico. Acá no interesa el saldo de la cuenta
-- sino cada bot por separado: cuál va ganando y cuál no.
--
-- A cada bot lo identifica su número mágico, que viene en cada operación y
-- en cada posición. El nombre sale de la plantilla del gráfico donde está
-- puesto, que el Agente ya lee.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

-- Tipo de cuenta nuevo. 'fondeo' sigue siendo el valor por defecto.
--   fondeo            cuenta de prop firm
--   capital_inversor  portafolio propio (Darwinex Zero)
--   incubadora        bots a prueba, uno por gráfico
-- La columna ya existe; esto solo deja el valor anotado para quien lea.

-- El número mágico del bot que hay en cada gráfico, leído de su plantilla.
alter table bots add column if not exists magic bigint;


-- Resultado de cada bot, por número mágico.
--
-- El ranking es ganancia sobre drawdown: cuánto ganó dividido por su peor
-- caída. Un bot que gana 1.000 habiendo llegado a estar 100 abajo vale más
-- que uno que gana los mismos 1.000 después de estar 900 abajo — el segundo
-- te hace pasar un mal momento que el primero no.
drop view if exists resumen_bots;

create view resumen_bots
with (security_invoker = true) as
with cerradas as (
  select
    o.cuenta_id,
    o.magic,
    o.ticket,
    o.simbolo,
    o.cerrada_en,
    coalesce(o.beneficio, 0) + coalesce(o.comision, 0) + coalesce(o.swap, 0) as resultado
  from operaciones o
  where o.magic is not null and o.magic <> 0 and o.cerrada_en is not null
),
curva as (
  select
    c.*,
    sum(c.resultado) over (partition by c.cuenta_id, c.magic
                           order by c.cerrada_en, c.ticket
                           rows between unbounded preceding and current row) as acumulado
  from cerradas c
),
con_pico as (
  select
    v.*,
    -- El pico arranca en cero: si el bot empieza perdiendo, esa pérdida
    -- ya es drawdown.
    greatest(0, max(v.acumulado) over (partition by v.cuenta_id, v.magic
                                       order by v.cerrada_en, v.ticket
                                       rows between unbounded preceding and current row)) as pico
  from curva v
),
por_bot as (
  select
    cuenta_id,
    magic,
    count(*)::int              as operaciones,
    sum(resultado)             as ganancia_cerrada,
    count(*) filter (where resultado > 0)::int as ganadoras,
    min(cerrada_en)            as primera,
    max(cerrada_en)            as ultima,
    min(acumulado - pico)      as drawdown_max,
    -- El símbolo que más opera, para reconocerlo de un vistazo.
    (array_agg(simbolo order by cerrada_en desc))[1] as simbolo
  from con_pico
  group by cuenta_id, magic
),
abiertas as (
  select
    p.cuenta_id,
    p.magic,
    count(*)::int as posiciones_abiertas,
    sum(coalesce(p.beneficio, 0) + coalesce(p.swap, 0)) as flotante
  from posiciones p
  where p.magic is not null and p.magic <> 0
  group by p.cuenta_id, p.magic
)
select
  coalesce(b.cuenta_id, a.cuenta_id) as cuenta_id,
  coalesce(b.magic, a.magic)         as magic,
  -- El nombre del EA sale de la plantilla del gráfico donde está puesto.
  bo.nombre                          as nombre,
  coalesce(b.simbolo, bo.simbolo)    as simbolo,
  coalesce(b.operaciones, 0)         as operaciones,
  coalesce(b.ganadoras, 0)           as ganadoras,
  coalesce(a.posiciones_abiertas, 0) as abiertas,
  coalesce(b.ganancia_cerrada, 0)    as ganancia_cerrada,
  coalesce(a.flotante, 0)            as flotante,
  coalesce(b.ganancia_cerrada, 0) + coalesce(a.flotante, 0) as ganancia,
  b.drawdown_max,
  b.primera,
  b.ultima,
  -- Ganancia sobre drawdown. Sin caídas todavía no hay cociente posible:
  -- queda vacío en vez de inventar un infinito.
  case
    when b.drawdown_max is null or b.drawdown_max = 0 then null
    else (coalesce(b.ganancia_cerrada, 0) + coalesce(a.flotante, 0)) / abs(b.drawdown_max)
  end as recuperacion
from por_bot b
full join abiertas a
       on a.cuenta_id = b.cuenta_id and a.magic = b.magic
left join bots bo
       on bo.cuenta_id = coalesce(b.cuenta_id, a.cuenta_id)
      and bo.magic = coalesce(b.magic, a.magic);
