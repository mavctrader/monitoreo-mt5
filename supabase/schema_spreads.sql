-- Lo que cuesta entrar: el spread de cada operación, medido por el agente.
--
-- Una fila por operación (cuenta + ticket, de ahí el UNIQUE). El agente la
-- inserta cuando ve la operación en MT5 y el panel solo la lee; nadie la
-- edita después. Si se borra una cuenta se van sus medidas con ella, para
-- eso está el ON DELETE CASCADE.
--
-- Faltaba en el repositorio: la tabla existía solo en la base. Si hubiera que
-- levantar el proyecto de cero, este archivo es el que la vuelve a crear.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

create table if not exists spreads (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references cuentas(id) on delete cascade,
  ticket bigint not null,
  simbolo text,
  volumen numeric,
  costo numeric,
  medido_en timestamptz,
  magic bigint,
  unique (cuenta_id, ticket)
);

alter table spreads enable row level security;

-- Envuelto para que el archivo se pueda correr más de una vez: crear una
-- política que ya existe aborta todo el script.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'spreads' and policyname = 'agente_insert_spreads') then
    create policy "agente_insert_spreads" on spreads
      for insert to authenticated
      with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'spreads' and policyname = 'agente_select_spreads') then
    create policy "agente_select_spreads" on spreads
      for select to authenticated
      using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'spreads' and policyname = 'panel_select_spreads') then
    create policy "panel_select_spreads" on spreads
      for select to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;
end $$;

-- Desde el 30/10/2026 Supabase ya no reparte permisos solo al crear algo en
-- public: sin esta línea la tabla existe pero nadie la puede tocar, ni con
-- política. Ver grants.sql.
grant select, insert on public.spreads to authenticated;
