-- El agente necesita leer las plantillas: es quien convierte los porcentajes
-- de cada prop firm en los límites en dinero de cada cuenta. Cuando se
-- crearon las políticas de reglas_plantillas todavía no hacía eso, así que
-- quedó sin permiso y las consultas le volvían vacías (RLS filtra en
-- silencio, sin error).
--
-- Sigue sin poder escribirlas: las plantillas solo se editan desde el panel.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

create policy "agente_select_plantillas" on reglas_plantillas
  for select to authenticated
  using (auth.uid() = '915a8e29-26b1-4354-be41-bca373f7470d');
