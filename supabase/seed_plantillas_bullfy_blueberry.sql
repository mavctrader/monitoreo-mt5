-- Reglas de las dos prop firms de la segunda VPS, el par primario/secundario.
--
-- Las dos cuentas son de 5.000 pero NO tienen las mismas reglas: operando en
-- par, la que manda es siempre la más estricta de las dos.
--
--   Blueberry Funded  objetivo 8%  diaria 4%  total 10%  3 días mínimos
--   Bullfy            objetivo 8%  diaria 4%  total 11%  5 días mínimos
--   Bullfy F2         objetivo 5%, el resto igual que su F1
--
-- Las dos con drawdown estático, reset 00:00 UTC y reparto 80/20.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

insert into reglas_plantillas
  (prop_firm, plan, fase, perdida_diaria_max_pct, drawdown_max_pct,
   objetivo_fase_pct, min_dias_trading, hora_reset, zona_horaria,
   reparto_pct, drawdown_trailing)
values
  ('Blueberry Funded', '2 Step PRIME',     'Challenge F1', 4, 10, 8, 3, '00:00', 'UTC', 80, false),
  ('Bullfy',           'BULL PRIME 50/50', 'Challenge F1', 4, 11, 8, 5, '00:00', 'UTC', 80, false),
  ('Bullfy',           'BULL PRIME 50/50', 'Challenge F2', 4, 11, 5, 5, '00:00', 'UTC', 80, false)
on conflict (prop_firm, plan, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct       = excluded.drawdown_max_pct,
  objetivo_fase_pct      = excluded.objetivo_fase_pct,
  min_dias_trading       = excluded.min_dias_trading,
  hora_reset             = excluded.hora_reset,
  zona_horaria           = excluded.zona_horaria,
  reparto_pct            = excluded.reparto_pct,
  drawdown_trailing      = excluded.drawdown_trailing;
