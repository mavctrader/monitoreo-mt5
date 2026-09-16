-- Reglas de FundedNext y Goat Funded Trader, tomadas de sus paneles de reglas.
--
-- Nota de nomenclatura: se usan las mismas etiquetas de fase que el usuario
-- carga en cuentas.fase ("Challenge F1"), para poder enlazar plantilla y
-- cuenta por prop_firm + fase más adelante. Las filas viejas de FundingPips
-- se renombran abajo para quedar iguales.
--
-- FundedNext declara drawdown "Static" (contra saldo inicial fijo), que es
-- justo como ya lo calcula el panel.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

insert into reglas_plantillas
  (prop_firm, fase, perdida_diaria_max_pct, drawdown_max_pct, objetivo_fase_pct, min_dias_trading, hora_reset, zona_horaria, fuente_url)
values
  ('FundedNext', 'Challenge F1', 5, 10, 8,    5,    null, null, 'https://fundednext.com/'),
  ('FundedNext', 'Challenge F2', 5, 10, 5,    5,    null, null, 'https://fundednext.com/'),
  ('FundedNext', 'Fondeada',     5, 10, null, null, null, null, 'https://fundednext.com/'),
  ('Goat Funded Trader', 'Challenge F1', 5, 10, 10,   null, null, null, 'https://goatfundedtrader.com/'),
  ('Goat Funded Trader', 'Challenge F2', 5, 10, 5,    null, null, null, 'https://goatfundedtrader.com/')
on conflict (prop_firm, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct = excluded.drawdown_max_pct,
  objetivo_fase_pct = excluded.objetivo_fase_pct,
  min_dias_trading = excluded.min_dias_trading,
  fuente_url = excluded.fuente_url,
  actualizado_en = now();

-- Unifica la nomenclatura de las filas de FundingPips cargadas antes.
update reglas_plantillas set fase = 'Challenge F1' where prop_firm = 'FundingPips' and fase = 'fase_1';
update reglas_plantillas set fase = 'Challenge F2' where prop_firm = 'FundingPips' and fase = 'fase_2';
update reglas_plantillas set fase = 'Fondeada'     where prop_firm = 'FundingPips' and fase = 'fondeada';
