-- Depósitos y retiros de cada cuenta, tal como los registra MT5 en su
-- historial (montos negativos = retiros). De ahí sale el retiro acumulado,
-- sin tener que deducirlo comparando saldos entre días.
--
-- Correr en el SQL Editor de Supabase (rol postgres), antes de recrear la
-- vista resumen_cuentas.

create table if not exists movimientos (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references cuentas(id) on delete cascade,
  ticket bigint not null,
  monto numeric,
  comentario text,
  ocurrido_en timestamptz,
  unique (cuenta_id, ticket)
);

alter table movimientos enable row level security;

-- Mismo criterio que operaciones: el agente solo puede leer e insertar
-- (histórico que solo crece), el panel solo lee.
create policy "agente_select_movimientos" on movimientos
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "agente_insert_movimientos" on movimientos
  for insert to authenticated
  with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');

create policy "panel_select_movimientos" on movimientos
  for select to authenticated
  using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
