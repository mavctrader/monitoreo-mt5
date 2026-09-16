-- Políticas de reglas_plantillas: solo el panel (usted) las administra.
-- El Agente no las necesita para nada.
-- UID de mavctrader@gmail.com: a7987a2f-5238-421c-bd9e-482490e864bf
--
-- Correr en el SQL Editor de Supabase (con el selector "Role" en postgres).

create policy "panel_select_plantillas" on reglas_plantillas
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_insert_plantillas" on reglas_plantillas
  for insert to authenticated
  with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_update_plantillas" on reglas_plantillas
  for update to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf')
  with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_delete_plantillas" on reglas_plantillas
  for delete to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
