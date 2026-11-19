-- Los gastos de la operación: lo que sale del bolsillo y no pasa por MT5.
--
-- Una fila por gasto (la comisión de un cobro en cripto, la compra de una
-- cuenta, lo que sea). La vista balance_financiero los resta de lo cobrado,
-- así que lo que falte aquí infla el balance.
--
-- La fecha es la del día en que se registra si no se dice otra. El panel es
-- el único que entra: crea, corrige y borra.
--
-- Faltaba en el repositorio: la tabla existía solo en la base.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

create table if not exists gastos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null default current_date,
  concepto text,
  monto numeric not null,
  metodo text
);

alter table gastos enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'gastos' and policyname = 'panel_select_gastos') then
    create policy "panel_select_gastos" on gastos
      for select to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'gastos' and policyname = 'panel_insert_gastos') then
    create policy "panel_insert_gastos" on gastos
      for insert to authenticated
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'gastos' and policyname = 'panel_update_gastos') then
    create policy "panel_update_gastos" on gastos
      for update to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf')
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'gastos' and policyname = 'panel_delete_gastos') then
    create policy "panel_delete_gastos" on gastos
      for delete to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;
end $$;

grant select, insert, update, delete on public.gastos to authenticated;
