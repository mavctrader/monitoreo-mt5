-- MT5 no sabe a qué prop firm pertenece una cuenta, pero sí reporta el nombre
-- del broker, que en la práctica la identifica. Esta tabla hace la traducción
-- y el agente la usa para completar cuentas.prop_firm al dar de alta.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

create table if not exists brokers_prop_firm (
  broker text primary key,
  prop_firm text not null
);

alter table brokers_prop_firm enable row level security;

-- Envuelto para que el archivo se pueda correr más de una vez: crear una
-- política que ya existe aborta todo el script.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'brokers_prop_firm' and policyname = 'agente_select_brokers') then
    create policy "agente_select_brokers" on brokers_prop_firm
      for select to authenticated
      using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'brokers_prop_firm' and policyname = 'panel_select_brokers') then
    create policy "panel_select_brokers" on brokers_prop_firm
      for select to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'brokers_prop_firm' and policyname = 'panel_insert_brokers') then
    create policy "panel_insert_brokers" on brokers_prop_firm
      for insert to authenticated
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;

  if not exists (select 1 from pg_policies where tablename = 'brokers_prop_firm' and policyname = 'panel_update_brokers') then
    create policy "panel_update_brokers" on brokers_prop_firm
      for update to authenticated
      using (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf')
      with check (auth.uid() = 'a7987a2f-5238-421c-bd9e-482490e864bf');
  end if;
end $$;

insert into brokers_prop_firm (broker, prop_firm) values
  ('FundedNext Ltd', 'FundedNext'),
  ('Goat Funded Ltd.', 'Goat Funded Trader'),
  ('Five Percent Online Ltd', 'The5ers')
on conflict (broker) do update set prop_firm = excluded.prop_firm;
