-- El costo de un par solo cuenta desde que la cuenta entró a ese par.
--
-- Problema que arregla (29 oct 2026): `resumen_pares` sumaba TODA la historia
-- del login. La demo FTMO 1515046192 entró al "B Par 2" el 29/10 y le metió
-- 3.631,06 de spread y 207,73 de swap de 213 operaciones del 22, 23 y 26/10,
-- de cuando estaba en otro par en la otra VPS. Ninguna de esas operaciones
-- pertenece a este par.
--
-- Pasa cada vez que se reutiliza una cuenta, así que no se arregla a mano:
-- se guarda en la cuenta la fecha en que entró al grupo y la vista corta por
-- ahí. El agente pone esa fecha cuando detecta que el par cambió.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

-- Cuándo entró la cuenta al grupo que tiene puesto ahora. Vacío = contar
-- todo, que es como se venía comportando: así una cuenta que nunca cambió
-- de par no pierde su histórico al aplicar esto.
alter table cuentas add column if not exists grupo_desde timestamptz;

comment on column cuentas.grupo_desde is
  'Desde cuándo la cuenta está en el grupo actual. Las operaciones y spreads '
  'anteriores son de su par anterior y no cuentan para el costo de este. '
  'Vacío = contar toda la historia.';

drop view if exists resumen_pares;

-- En un par inverso el movimiento del precio se cancela entre las dos puntas,
-- así que lo que queda del resultado combinado es el costo de operar. Esta
-- vista lo reparte en sus tres partes, una fila por cuenta del par.
--
-- Los dos laterales van por separado a propósito: el spread vive en su propia
-- tabla (lo mide el recolector al abrir cada posición) y cruzarlo con las
-- operaciones en un solo join multiplicaría las filas de ambos lados.
create view resumen_pares
with (security_invoker = true) as
select
  c.grupo,
  c.id as cuenta_id,
  c.login,
  c.prop_firm,
  c.rol,
  coalesce(o.comisiones, 0) as comisiones,
  coalesce(o.swaps, 0)      as swaps,
  coalesce(s.spread, 0)     as spread
from cuentas c
left join lateral (
  select
    sum(coalesce(op.comision, 0)) as comisiones,
    sum(coalesce(op.swap, 0))     as swaps
  from operaciones op
  where op.cuenta_id = c.id
    and (c.grupo_desde is null or op.cerrada_en >= c.grupo_desde)
) o on true
left join lateral (
  select sum(coalesce(sp.costo, 0)) as spread
  from spreads sp
  where sp.cuenta_id = c.id
    and (c.grupo_desde is null or sp.medido_en >= c.grupo_desde)
) s on true
where c.grupo is not null;

-- Desde el 30/10/2026 Supabase ya no da permiso de lectura automático a lo
-- nuevo que se crea en "public": una vista recreada hoy nace sin él y el panel
-- respondería "permission denied". El panel y el agente entran con usuario y
-- contraseña, o sea el rol "authenticated"; nadie lee como "anon".
grant select on public.resumen_pares to authenticated;

-- Arreglo puntual de la cuenta que motivó esto. El 30/10 pasó del "B Par 2"
-- al "B Par 3", así que su par actual arranca ese día. Medido: de sus
-- spreads, 3.631,06 son del 23/10 y antes (de cuando estaba en otro par en
-- la otra VPS) y 70,20 son de hoy, del par que tiene ahora.
update cuentas
   set grupo_desde = '2026-10-30T00:00:00Z'
 where login = 1515046192
   and grupo_desde is null;
