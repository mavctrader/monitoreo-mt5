-- Agrega el seguimiento del equity al inicio del día de cada cuenta, para
-- calcular "Hoy" (P&L del día) y el colchón de pérdida diaria en el panel.
-- Correr en el SQL Editor de Supabase.

alter table estado add column if not exists equity_inicio_dia numeric;
alter table estado add column if not exists equity_inicio_dia_en timestamptz;

-- Las políticas ya existentes de "agente_update_estado" e
-- "agente_insert_estado" cubren estas columnas nuevas (son las mismas
-- filas de la tabla estado, no hace falta nada más).
