-- Planes de 5.000 que entraron en octubre de 2026.
--
-- Las dos son de 5.000 y las dos piden un 8% de objetivo, pero no son
-- iguales: The5ers deja perder 5% en el día y pide 3 días, FundedNext deja
-- 4% y pide 2. Operando en par manda siempre la más estricta.
--
-- Ojo con The5ers: su "0 / 3" son días RENTABLES, no días operados. El panel
-- cuenta los días en que se abrió alguna operación, gane o pierda, así que
-- para esa cuenta la columna de días va a mostrarse más adelantada de lo que
-- la firma considera cumplido.
--
-- Las dos con drawdown estático y reparto 80/20.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

insert into reglas_plantillas
  (prop_firm, plan, fase, perdida_diaria_max_pct, drawdown_max_pct,
   objetivo_fase_pct, min_dias_trading, reparto_pct, drawdown_trailing)
values
  ('The5ers',    '$5K de Alto Riesgo',  'Challenge F1', 5, 10, 8, 3, 80, false),
  ('FundedNext', 'Stellar Lite 2-Step', 'Challenge F1', 4, 10, 8, 2, 80, false),
  ('FundedNext', 'Stellar Lite 2-Step', 'Challenge F2', 4, 10, 4, 2, 80, false)
on conflict (prop_firm, plan, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct       = excluded.drawdown_max_pct,
  objetivo_fase_pct      = excluded.objetivo_fase_pct,
  min_dias_trading       = excluded.min_dias_trading,
  reparto_pct            = excluded.reparto_pct,
  drawdown_trailing      = excluded.drawdown_trailing;
