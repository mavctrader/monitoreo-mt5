-- Orion Funded, plan "Orion Standard Swing", fase 1 (cuenta 308158, 50K MT5).
--
-- Firma nueva: no estaba en la tabla, así que no aparecía en el desplegable.
-- Los límites son los de su tablero para esa cuenta:
--   pérdida diaria 5%  (2.500, nivel 47.500)
--   drawdown total 8%  (4.000, nivel fijo 46.000, o sea estático)
--   objetivo       8%  (4.000)
--   4 días mínimos de trading
--   el día cierra a las 00:06 UTC, que es lo que dice su contador
--
-- La idea de trade queda vacía a propósito: Orion no publica un tope por
-- operación y la regla de la mitad de la diaria es de WSFunded, no del resto.
-- El reparto y las fases 2 y fondeada también quedan fuera: esa pantalla es
-- solo de la fase 1.
--
-- Corrido el 16/11/2026.

insert into reglas_plantillas
  (prop_firm, plan, fase, perdida_diaria_max_pct, drawdown_max_pct,
   objetivo_fase_pct, min_dias_trading, trade_idea_pct, reparto_pct,
   hora_reset, zona_horaria, drawdown_trailing)
values
  ('Orion Funded', 'Orion Standard Swing', 'Challenge F1', 5, 8, 8, 4,
   null, null, '00:06', 'UTC', false)
on conflict (prop_firm, plan, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct       = excluded.drawdown_max_pct,
  objetivo_fase_pct      = excluded.objetivo_fase_pct,
  min_dias_trading       = excluded.min_dias_trading,
  hora_reset             = excluded.hora_reset,
  zona_horaria           = excluded.zona_horaria,
  drawdown_trailing      = excluded.drawdown_trailing;

select prop_firm, plan, fase, perdida_diaria_max_pct, drawdown_max_pct,
       objetivo_fase_pct, min_dias_trading, trade_idea_pct, hora_reset,
       zona_horaria
  from reglas_plantillas
 where prop_firm = 'Orion Funded';
