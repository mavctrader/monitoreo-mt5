-- Políticas RLS para el usuario humano del panel (mavctrader@gmail.com).
-- UID: a7987a2f-5238-421c-bd9e-482490e864bf
--
-- Correr DESPUÉS de policies_migrar_agente.sql, en el SQL Editor.
--
-- Acceso amplio ("Usted: todo, con usuario y contraseña"): ve todo,
-- puede dar de alta/baja cuentas, mandar órdenes y editar reglas.
-- Sigue sin poder borrar histórico (operaciones) ni editar estado/
-- posiciones directamente - eso lo escribe únicamente el Agente.

create policy "panel_select_cuentas" on cuentas
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_update_cuentas" on cuentas
  for update to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf')
  with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_select_estado" on estado
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_select_posiciones" on posiciones
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_select_operaciones" on operaciones
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_select_bots" on bots
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

-- Órdenes: usted las crea (parar/arrancar/descargar), el Agente las lee
-- y las marca entregada/hecha. Usted no las edita después de creadas.
create policy "panel_select_ordenes" on ordenes
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_insert_ordenes" on ordenes
  for insert to authenticated
  with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

-- Reglas: solo usted las define.
create policy "panel_select_reglas" on reglas
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_insert_reglas" on reglas
  for insert to authenticated
  with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');

create policy "panel_update_reglas" on reglas
  for update to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf')
  with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
