-- The5ers, plan "2 Steps" del Funding Program (el de $100k 8/5).
--
-- "Min. Trades: 1" de su tabla es un mínimo de operaciones, no de días; se
-- guarda como 1 día porque a efectos prácticos es el mismo requisito (no
-- tienen período máximo ni mínimo de días).
--
-- En la cuenta fondeada el 10% no es un objetivo para pasar, es el umbral de
-- escalado. Se carga igual porque sirve como meta.
--
-- Reglas que esta plantilla todavía no modela: consistencia del 50% por día
-- y tope de retiro de $2.000, ambas solo de la cuenta fondeada.
--
-- Hora de reset: sin confirmar, se asume la misma que las otras (medianoche
-- del servidor, Europa del Este).
--
-- Correr en el SQL Editor de Supabase (rol postgres).

insert into reglas_plantillas
  (prop_firm, fase, perdida_diaria_max_pct, drawdown_max_pct, objetivo_fase_pct, min_dias_trading, hora_reset, zona_horaria, fuente_url)
values
  ('The5ers', 'Challenge F1', 3, 10, 8,  1,    '00:00', 'Europe/Athens', 'https://www.the5ers.com/'),
  ('The5ers', 'Challenge F2', 3, 10, 5,  1,    '00:00', 'Europe/Athens', 'https://www.the5ers.com/'),
  ('The5ers', 'Fondeada',     3, 10, 10, null, '00:00', 'Europe/Athens', 'https://www.the5ers.com/')
on conflict (prop_firm, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct = excluded.drawdown_max_pct,
  objetivo_fase_pct = excluded.objetivo_fase_pct,
  min_dias_trading = excluded.min_dias_trading,
  hora_reset = excluded.hora_reset,
  zona_horaria = excluded.zona_horaria,
  fuente_url = excluded.fuente_url,
  actualizado_en = now();
