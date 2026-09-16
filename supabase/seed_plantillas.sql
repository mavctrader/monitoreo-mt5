-- Datos de FundingPips, variante "2 Step Standard" (confirmado contra una
-- cuenta Master real: Max Loss 10% / Daily Loss 5% coinciden).
-- Reset diario: 16:00 hora de Lima (UTC-5) = 21:00 UTC, calculado a partir
-- de la cuenta regresiva "se reinicia en" de una cuenta real, no de
-- documentación oficial — conviene confirmarlo si aparece publicado.

insert into reglas_plantillas
  (prop_firm, fase, perdida_diaria_max_pct, drawdown_max_pct, objetivo_fase_pct, min_dias_trading, hora_reset, zona_horaria, fuente_url)
values
  ('FundingPips', 'fase_1',  5, 10, 8,    3,    '21:00', 'UTC', 'https://fundingpips.com/'),
  ('FundingPips', 'fase_2',  5, 10, 5,    3,    '21:00', 'UTC', 'https://fundingpips.com/'),
  ('FundingPips', 'fondeada', 5, 10, null, null, '21:00', 'UTC', 'https://fundingpips.com/')
on conflict (prop_firm, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct = excluded.drawdown_max_pct,
  objetivo_fase_pct = excluded.objetivo_fase_pct,
  min_dias_trading = excluded.min_dias_trading,
  hora_reset = excluded.hora_reset,
  zona_horaria = excluded.zona_horaria,
  fuente_url = excluded.fuente_url,
  actualizado_en = now();
