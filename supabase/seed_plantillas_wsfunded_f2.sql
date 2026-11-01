-- WSFunded, segunda fase del Classic Two Phase (cuenta 192683, 5K MT5).
--
-- Faltaba la F2: la tabla solo tenía "Challenge F1" y "Fondeada", así que el
-- desplegable de fase no ofrecía nada que elegir para una cuenta en Step-2.
--
-- Mismos límites que la F1 salvo el objetivo, que baja de 8% a 5%:
--   diaria 5%  total 8%  objetivo 5%  4 días mínimos
--
-- La idea de trade es la mitad de la pérdida diaria, que es el criterio del
-- usuario: 5% / 2 = 2,5%, o sea 125 $ en una cuenta de 5.000.
--
-- Estático, reset 00:00 hora de Atenas (igual que la F1 de esta firma).
-- El reparto queda vacío porque en challenge no hay: aparece en la Fondeada.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

insert into reglas_plantillas
  (prop_firm, plan, fase, perdida_diaria_max_pct, drawdown_max_pct,
   objetivo_fase_pct, min_dias_trading, trade_idea_pct, hora_reset,
   zona_horaria, drawdown_trailing)
values
  ('WSFunded', 'Classic Two Phase', 'Challenge F2', 5, 8, 5, 4, 2.5, '00:00',
   'Europe/Athens', false)
on conflict (prop_firm, plan, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct       = excluded.drawdown_max_pct,
  objetivo_fase_pct      = excluded.objetivo_fase_pct,
  min_dias_trading       = excluded.min_dias_trading,
  trade_idea_pct         = excluded.trade_idea_pct,
  hora_reset             = excluded.hora_reset,
  zona_horaria           = excluded.zona_horaria,
  drawdown_trailing      = excluded.drawdown_trailing;
