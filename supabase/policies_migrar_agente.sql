-- Migra las políticas del Agente del UID viejo (compartido por error con
-- mavctrader@gmail.com) al UID del nuevo usuario dedicado
-- agente@monitoreo.local: 915a8e29-26b1-4354-be41-bca373f7470d
--
-- Usa ALTER POLICY (modifica en el lugar) en vez de DROP + CREATE, porque
-- Supabase Studio reenruta las consultas con DROP por un camino con menos
-- privilegios y falla con "must be owner of relation".
--
-- Correr UNA VEZ en el SQL Editor de Supabase (rol postgres).

alter policy "agente_select_cuentas" on cuentas
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_insert_cuentas" on cuentas
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_update_cuentas" on cuentas
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_select_estado" on estado
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_insert_estado" on estado
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_update_estado" on estado
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_select_posiciones" on posiciones
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_insert_posiciones" on posiciones
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_update_posiciones" on posiciones
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_delete_posiciones" on posiciones
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_select_operaciones" on operaciones
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_insert_operaciones" on operaciones
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_select_bots" on bots
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_insert_bots" on bots
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_update_bots" on bots
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_select_ordenes" on ordenes
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_update_ordenes" on ordenes
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

alter policy "agente_select_reglas" on reglas
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');
