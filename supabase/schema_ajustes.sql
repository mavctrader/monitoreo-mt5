-- Los ajustes del panel: pares clave/valor que hay que recordar entre
-- visitas (un número que el usuario fija a mano y el panel relee al cargar).
--
-- La clave es el identificador, el valor es un número. Solo el panel entra
-- aquí: lee, crea y corrige; no borra.
--
-- Faltaba en el repositorio: la tabla existía solo en la base.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

create table if not exists ajustes (
  clave text primary key,
  valor numeric
);

alter table ajustes enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'ajustes' and policyname = 'panel_select_ajustes') then
    create policy "panel_select_ajustes" on ajustes
      for select to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'ajustes' and policyname = 'panel_insert_ajustes') then
    create policy "panel_insert_ajustes" on ajustes
      for insert to authenticated
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'ajustes' and policyname = 'panel_update_ajustes') then
    create policy "panel_update_ajustes" on ajustes
      for update to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf')
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;
end $$;

grant select, insert, update on public.ajustes to authenticated;
