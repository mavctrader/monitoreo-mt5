-- Plantillas de reglas por prop firm + fase (challenge fase 1, fase 2,
-- fondeada, etc.). Cada cuenta hereda estos porcentajes según en qué
-- prop firm/fase esté, en vez de cargar los números a mano por cuenta.
-- Correr en el SQL Editor de Supabase, después de schema.sql.

create table if not exists reglas_plantillas (
  id uuid primary key default gen_random_uuid(),
  prop_firm text not null,
  fase text not null,
  perdida_diaria_max_pct numeric,
  drawdown_max_pct numeric,
  objetivo_fase_pct numeric,
  min_dias_trading integer,
  hora_reset time,
  zona_horaria text,
  fuente_url text,
  actualizado_en timestamptz not null default now(),
  unique (prop_firm, fase)
);

alter table reglas_plantillas enable row level security;
