-- Roles primario / secundario.
--
-- El copiador nuevo (EA_SX_Primario / EA_SX_Secundario) reemplaza al anterior
-- y cambia la nomenclatura: donde antes había master y slave, ahora hay
-- primario y secundario. La jerarquía es la misma -uno manda, el otro copia-
-- así que se suman a los valores que ya existían en vez de reemplazarlos: la
-- migración de las cuentas viejas va a ser de a poco y los dos sistemas van a
-- convivir un tiempo.
--
-- Lo que enlaza las dos puntas es el "Código de correspondencia", el mismo
-- número en los dos EAs, igual que antes lo hacía el archivo master.jsonN.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

alter table cuentas drop constraint if exists cuentas_rol_check;
alter table cuentas add constraint cuentas_rol_check
  check (rol is null or rol in ('master', 'slave', 'primario', 'secundario'));

-- Par cargado a mano: el agente no le toca rol ni grupo.
--
-- Hace falta porque el agente deshace el par cuando no detecta el enlace, y
-- del copiador nuevo todavía no sabe leerlo. Sin esta marca, un par puesto a
-- mano se borraría en el ciclo siguiente.
alter table cuentas add column if not exists par_manual boolean not null default false;
