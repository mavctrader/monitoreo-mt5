-- Los permisos del esquema público. Correr AL FINAL, después de todos los
-- schema_*.sql y policies_*.sql.
--
-- Por qué hace falta este archivo
-- -------------------------------
-- Hasta el 30/10/2026 Supabase repartía permisos solo: cualquier tabla o
-- vista nueva en "public" nacía con acceso para anon, authenticated y
-- service_role, y nadie tenía que escribir un grant. Desde esa fecha ya no:
-- un objeto nuevo nace cerrado. Una vista recreada con "create or replace"
-- conserva los suyos, pero una que se borra y se vuelve a crear los pierde.
--
-- Y son dos cosas distintas, que se confunden fácil:
--   - el GRANT es la puerta: si no está, el cliente ni siquiera ve la tabla
--     (error "permission denied"), por muchas políticas que tenga;
--   - la POLÍTICA RLS es el filtro de filas: decide cuáles de esas filas
--     puede ver o tocar cada usuario.
-- Lo que protege los datos de este proyecto son las políticas: todas las
-- tablas tienen RLS activa y sus políticas están atadas a dos UID concretos
-- (el panel y el agente), así que un visitante sin sesión no saca ni una
-- fila aunque la puerta esté abierta. Las vistas son security_invoker, o sea
-- que respetan la RLS de las tablas de abajo.
--
-- Esto reproduce lo que había en la base el 19/11/2026, que es lo mismo que
-- Supabase repartía solo: los 25 objetos de public con permiso para los tres
-- roles. Nadie entra como anon; el panel y el agente inician sesión, así que
-- los dos llegan como authenticated.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

grant usage on schema public to anon, authenticated, service_role;

grant all on all tables in schema public to anon, authenticated, service_role;

-- OJO: esto alcanza solo a lo que existe cuando se corre. Una tabla o una
-- vista que se agregue después nace sin permisos y hay que dárselos en su
-- propio archivo, como hacen schema_spreads.sql, schema_ajustes.sql,
-- schema_gastos.sql y la línea de resumen_pares en schema_grupo_desde.sql.
-- Si algo del panel deja de verse de un día para otro y el error dice
-- "permission denied", el grant que falta es lo primero que hay que mirar.

-- Comprobación: cuántos objetos de public tienen select para authenticated.
-- Tienen que ser los mismos que hay en el esquema.
select count(distinct table_name) as objetos_con_select
  from information_schema.role_table_grants
 where table_schema = 'public'
   and grantee = 'authenticated'
   and privilege_type = 'SELECT';
