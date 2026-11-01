-- WSFunded, plan "Stellar Two Phase", fase fondeada (cuenta 175567, 5K MT5).
--
-- La firma tiene dos planes y en la tabla solo estaba el Classic, así que la
-- cuenta fondeada quedaba colgada del plan equivocado. Los límites son los
-- que muestra el tablero de WSFunded para esa cuenta: pérdida diaria 4%,
-- drawdown total 12%, reparto 80%. Fondeada, así que no hay objetivo de fase
-- ni mínimo de días.
--
-- Idea de trade 2%, que es la mitad de la pérdida diaria: el criterio del
-- usuario. En una cuenta de 5.000 son 100 $.
--
-- Va junto el arreglo de la fase 1 del Classic, que había quedado en 2%
-- cuando su pérdida diaria es 5%: le corresponde 2,5%, igual que la F2.
--
-- Corrido el 1/11/2026.

insert into reglas_plantillas
  (prop_firm, plan, fase, perdida_diaria_max_pct, drawdown_max_pct,
   objetivo_fase_pct, min_dias_trading, trade_idea_pct, reparto_pct,
   drawdown_trailing)
values
  ('WSFunded', 'Stellar Two Phase', 'Fondeada', 4, 12, null, null, 2, 80, false)
on conflict (prop_firm, plan, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct       = excluded.drawdown_max_pct,
  trade_idea_pct         = excluded.trade_idea_pct,
  reparto_pct            = excluded.reparto_pct,
  drawdown_trailing      = excluded.drawdown_trailing;

update reglas_plantillas
   set trade_idea_pct = 2.5
 where prop_firm = 'WSFunded'
   and plan      = 'Classic Two Phase'
   and fase      = 'Challenge F1';
