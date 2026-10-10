-- Solicitudes de retiro a las prop firms.
--
-- Hasta ahora lo retirado era un solo número acumulado por cuenta, sacado del
-- historial de MT5. Eso no alcanza: las prop firms pagan por fuera de la
-- cuenta, se quedan con su parte del reparto, y algunas solicitudes salen
-- rechazadas. Cada una de esas cosas es un dato distinto.
--
--   bruto   lo que pediste
--   neto    lo que te pagaron (bruto x reparto)
--   bruto - neto  lo que se queda la prop firm
--
-- Una solicitud rechazada no suma a ninguno de los dos: se cuenta aparte,
-- porque es plata que creías tener y no llegó.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

create table if not exists retiros (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references cuentas(id) on delete cascade,
  bruto numeric not null,
  reparto_pct numeric,
  neto numeric,
  estado text not null default 'aprobado' check (estado in ('aprobado', 'rechazado', 'pendiente')),
  solicitado_en date,
  comentario text,
  creado_en timestamptz not null default now()
);

create index if not exists retiros_cuenta on retiros (cuenta_id);

alter table retiros enable row level security;

-- Solo el panel. El agente no tiene nada que ver con los retiros: no los lee
-- ni los escribe.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'retiros' and policyname = 'panel_select_retiros') then
    create policy "panel_select_retiros" on retiros
      for select to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'retiros' and policyname = 'panel_insert_retiros') then
    create policy "panel_insert_retiros" on retiros
      for insert to authenticated
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'retiros' and policyname = 'panel_update_retiros') then
    create policy "panel_update_retiros" on retiros
      for update to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf')
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'retiros' and policyname = 'panel_delete_retiros') then
    create policy "panel_delete_retiros" on retiros
      for delete to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;
end $$;


-- Resumen por cuenta, que es lo que mira el panel.
drop view if exists resumen_retiros;

create view resumen_retiros
with (security_invoker = true) as
select
  cuenta_id,
  sum(neto)  filter (where estado = 'aprobado')  as cobrado,
  sum(bruto) filter (where estado = 'aprobado')  as bruto_aprobado,
  sum(bruto - coalesce(neto, bruto)) filter (where estado = 'aprobado') as se_queda_la_firma,
  sum(bruto) filter (where estado = 'rechazado') as rechazado,
  count(*)   filter (where estado = 'rechazado')::int as solicitudes_rechazadas,
  count(*)   filter (where estado = 'aprobado')::int  as solicitudes_cobradas
from retiros
group by cuenta_id;
