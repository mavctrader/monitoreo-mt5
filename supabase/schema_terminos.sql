-- Términos de contrato de cada prop firm, en texto libre.
--
-- Van por FIRMA y no por cuenta ni por plan: las reglas de qué se puede y
-- qué no (copiar entre cuentas, HFT, noticias, fin de semana) son casi
-- siempre las mismas para la de 5k, la de 50k y la de 100k. Lo que cambia
-- con el tamaño son los montos, y eso ya está en reglas_plantillas.
--
-- Es texto libre a propósito: cada firma redacta sus restricciones distinto
-- y forzarlas a casillas fijas haría perder el matiz, que es justo lo que
-- importa para no incumplir.
--
-- Se consulta desde panel/terminos.html, antes de configurar un robot.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

create table if not exists terminos_firma (
  prop_firm text primary key,
  notas text,
  fuente_url text,
  actualizado_en timestamptz not null default now()
);

alter table terminos_firma enable row level security;

-- Solo el panel (el usuario humano). El agente no tiene nada que hacer acá:
-- no lee ni escribe términos de contrato.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'terminos_firma' and policyname = 'panel_select_terminos') then
    create policy "panel_select_terminos" on terminos_firma
      for select to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'terminos_firma' and policyname = 'panel_insert_terminos') then
    create policy "panel_insert_terminos" on terminos_firma
      for insert to authenticated
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'terminos_firma' and policyname = 'panel_update_terminos') then
    create policy "panel_update_terminos" on terminos_firma
      for update to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf')
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'terminos_firma' and policyname = 'panel_delete_terminos') then
    create policy "panel_delete_terminos" on terminos_firma
      for delete to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;
end $$;

-- Una fila vacía por cada firma que ya tengas, para que aparezcan todas en
-- la lista y solo haya que escribirles el contenido.
insert into terminos_firma (prop_firm)
select distinct prop_firm from cuentas where prop_firm is not null
union
select distinct prop_firm from reglas_plantillas where prop_firm is not null
on conflict (prop_firm) do nothing;
