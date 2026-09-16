-- Cuentas que trabajan en pares (copiadora): una master y una o más
-- slave agrupadas bajo el mismo nombre de grupo. Lo que no se pueda
-- detectar automático (ej. si la firma de la slave permite copiar) se
-- carga a mano desde el panel por ahora.
-- Correr en el SQL Editor de Supabase.

alter table cuentas add column if not exists rol text check (rol in ('master', 'slave'));
alter table cuentas add column if not exists grupo text;
alter table cuentas add column if not exists grupo_subtitulo text;
alter table cuentas add column if not exists simbolo_principal text;
alter table cuentas add column if not exists slave_allowed boolean;

-- No hace falta ninguna política nueva: "panel_update_cuentas" ya cubre
-- toda la fila de cuentas, columnas nuevas incluidas.
