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

-- El spread se mide por posición, y sin el número mágico no se puede
-- atribuir a una estrategia una vez que la posición se cerró.
alter table spreads add column if not exists magic bigint;


-- Resultado de cada estrategia, por número mágico.
--
-- Agrupar por símbolo no sirve: dos estrategias distintas pueden operar el
-- mismo activo y al juntarlas se pierden las dos. El número mágico es lo
-- único que las separa.
--
-- El ranking es ganancia sobre drawdown: cuánto ganó dividido por su peor
-- caída. Una estrategia que gana 1.000 habiendo llegado a estar 100 abajo
-- vale más que otra que gana los mismos 1.000 después de estar 900 abajo —
-- la segunda te hace pasar un mal momento que la primera no.
drop view if exists resumen_bots;

create view resumen_bots
with (security_invoker = true) as
with cerradas as (
  select
    o.cuenta_id, o.magic, o.ticket, o.simbolo, o.cerrada_en,
    coalesce(o.beneficio, 0) as beneficio,
    coalesce(o.comision, 0)  as comision,
    coalesce(o.swap, 0)      as swap,
    coalesce(o.beneficio, 0) + coalesce(o.comision, 0) + coalesce(o.swap, 0) as resultado,
    case
      when (o.cerrada_en at time zone 'UTC')::date = (now() at time zone 'UTC')::date
      then coalesce(o.beneficio, 0) + coalesce(o.comision, 0) + coalesce(o.swap, 0)
      else 0
    end as hoy
  from operaciones o
  where o.magic is not null and o.magic <> 0 and o.cerrada_en is not null
),
curva as (
  select c.*,
    sum(c.resultado) over (partition by c.cuenta_id, c.magic
                           order by c.cerrada_en, c.ticket
                           rows between unbounded preceding and current row) as acumulado
  from cerradas c
),
con_pico as (
  select v.*,
    greatest(0, max(v.acumulado) over (partition by v.cuenta_id, v.magic
                                       order by v.cerrada_en, v.ticket
                                       rows between unbounded preceding and current row)) as pico
  from curva v
),
por_bot as (
  select
    cuenta_id, magic,
    count(*)::int                              as operaciones,
    count(*) filter (where resultado > 0)::int as ganadoras,
    sum(resultado)                             as ganancia_cerrada,
    sum(comision)                              as comision,
    sum(swap)                                  as swap,
    sum(hoy)                                   as hoy,
    min(cerrada_en)                            as primera,
    max(cerrada_en)                            as ultima,
    min(acumulado - pico)                      as drawdown_max,
    (array_agg(simbolo order by cerrada_en desc))[1] as simbolo
  from con_pico
  group by cuenta_id, magic
),
abiertas as (
  select p.cuenta_id, p.magic,
         count(*)::int as posiciones_abiertas,
         sum(coalesce(p.beneficio, 0)) as flotante,
         sum(coalesce(p.swap, 0))      as swap_abierto
  from posiciones p
  where p.magic is not null and p.magic <> 0
  group by p.cuenta_id, p.magic
),
horquilla as (
  select s.cuenta_id, s.magic, sum(coalesce(s.costo, 0)) as spread
  from spreads s
  where s.magic is not null and s.magic <> 0
  group by s.cuenta_id, s.magic
),
claves as (
  select cuenta_id, magic from por_bot
  union select cuenta_id, magic from abiertas
  union select cuenta_id, magic from horquilla
)
select
  k.cuenta_id,
  k.magic,
  bo.nombre                           as nombre,
  coalesce(b.simbolo, bo.simbolo)     as simbolo,
  coalesce(b.operaciones, 0)          as operaciones,
  coalesce(b.ganadoras, 0)            as ganadoras,
  coalesce(a.posiciones_abiertas, 0)  as abiertas,
  coalesce(b.ganancia_cerrada, 0)     as ganancia_cerrada,
  coalesce(a.flotante, 0)             as flotante,
  coalesce(b.ganancia_cerrada, 0) + coalesce(a.flotante, 0) as ganancia,
  coalesce(b.hoy, 0)                  as hoy,
  coalesce(b.comision, 0)             as comision,
  coalesce(b.swap, 0) + coalesce(a.swap_abierto, 0) as swap,
  coalesce(h.spread, 0)               as spread,
  b.drawdown_max,
  b.primera,
  b.ultima,
  -- Ganancia sobre drawdown. Sin caídas todavía no hay cociente posible:
  -- queda vacío en vez de inventar un infinito.
  case
    when b.drawdown_max is null or b.drawdown_max = 0 then null
    else (coalesce(b.ganancia_cerrada, 0) + coalesce(a.flotante, 0)) / abs(b.drawdown_max)
  end as recuperacion
from claves k
left join por_bot   b on b.cuenta_id = k.cuenta_id and b.magic = k.magic
left join abiertas  a on a.cuenta_id = k.cuenta_id and a.magic = k.magic
left join horquilla h on h.cuenta_id = k.cuenta_id and h.magic = k.magic
left join bots     bo on bo.cuenta_id = k.cuenta_id and bo.magic = k.magic;
