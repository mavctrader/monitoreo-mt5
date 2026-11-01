-- El agente pasa a administrar las plantillas de reglas, no solo leerlas.
--
-- Hasta ahora `policies_plantillas_agente.sql` le daba select y nada más, con
-- el criterio de que "las plantillas solo se editan desde el panel". Eso
-- obligaba a pegar a mano en el editor SQL cada plantilla nueva (una prop
-- firm, un plan o una fase que aparece), que es trabajo de rutina.
--
-- Autorizado por el usuario el 30/10/2026.
--
-- NO lleva delete a propósito: agregar y corregir una plantilla es rutina,
-- pero borrarla le cambia las reglas a una cuenta que puede estar en curso.
-- Eso sigue pasando por el panel.
--
-- UID del agente: 915a8e29-26b1-4354-be41-bca373f7470d
-- Correr en el SQL Editor de Supabase (rol postgres).

do $$
begin
  if not exists (select 1 from pg_policies
                  where tablename = 'reglas_plantillas'
                    and policyname = 'agente_insert_plantillas') then
    create policy "agente_insert_plantillas" on reglas_plantillas
      for insert to authenticated
      with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');
  end if;

  if not exists (select 1 from pg_policies
                  where tablename = 'reglas_plantillas'
                    and policyname = 'agente_update_plantillas') then
    create policy "agente_update_plantillas" on reglas_plantillas
      for update to authenticated
      using      (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d')
      with check (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');
  end if;
end $$;
