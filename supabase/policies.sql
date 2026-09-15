-- Políticas RLS para el usuario dedicado del Agente.
--
-- ESTADO ACTUAL DEL PROYECTO (referencia, no volver a correr tal cual):
-- este archivo documenta las políticas vigentes. En la base real se
-- aplicaron primero con el UID viejo y después se migraron con
-- policies_migrar_agente.sql - si hay que recrear todo desde cero, correr
-- este archivo después de schema.sql sirve igual.
--
-- UID del usuario "agente@monitoreo.local" (Authentication -> Users):
--   915a8e29-26b1-4354-be41-bca373f7470d
--
-- Reglas del diseño (sección "Quién tiene qué llave"):
--  - El agente escribe estado y lee órdenes.
--  - El agente NO puede borrar histórico (operaciones) ni tocar reglas.
--
-- Las políticas del panel (usuario humano, permisos más amplios) están
-- en policies_panel.sql.

-- cuentas: leer, dar de alta cuentas nuevas al detectarlas, actualizar sus
-- propios campos (ej. alias, activa). Nunca borrar.
create policy "agente_select_cuentas" on cuentas
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_insert_cuentas" on cuentas
  for insert to authenticated
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_update_cuentas" on cuentas
  for update to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

-- estado: la foto de ahora mismo, se sobrescribe (upsert). Nunca borrar.
create policy "agente_select_estado" on estado
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_insert_estado" on estado
  for insert to authenticated
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_update_estado" on estado
  for update to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

-- posiciones: lo abierto ahora mismo. Se reemplaza cada minuto, por eso
-- el agente también puede borrar (las que ya se cerraron).
create policy "agente_select_posiciones" on posiciones
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_insert_posiciones" on posiciones
  for insert to authenticated
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_update_posiciones" on posiciones
  for update to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_delete_posiciones" on posiciones
  for delete to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

-- operaciones: histórico cerrado, SOLO crece. El agente puede leer e
-- insertar, pero nunca actualizar ni borrar (no hay política de
-- update/delete a propósito -> RLS las bloquea por defecto).
create policy "agente_select_operaciones" on operaciones
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_insert_operaciones" on operaciones
  for insert to authenticated
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

-- bots: qué hay en cada gráfico y su interruptor. Leer, insertar, actualizar.
create policy "agente_select_bots" on bots
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_insert_bots" on bots
  for insert to authenticated
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_update_bots" on bots
  for update to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

-- ordenes: el agente LEE las pendientes (las crea el panel, aparte) y
-- ACTUALIZA su estado (entregada/hecha). Nunca inserta ni borra.
create policy "agente_select_ordenes" on ordenes
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_update_ordenes" on ordenes
  for update to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

-- reglas: el agente SOLO lee los límites para vigilar. Nunca escribe.
create policy "agente_select_reglas" on reglas
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

