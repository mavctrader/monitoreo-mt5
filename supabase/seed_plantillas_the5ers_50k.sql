-- The5ers, plan de alto riesgo de 50K ("50k High Stakes"), primera fase.
--
-- Los limites son los que muestra su tablero (hub.the5ers.com, 19/11/2026),
-- con saldo 50 000:
--   maxima perdida diaria  4%  (2 000, nivel 48 000)
--   perdida maxima         8%  (4 000, nivel 46 000, nivel fijo = estatico)
--   objetivo de beneficio  8%  (4 000)
--   3 dias rentables minimos
--
-- No son los mismos numeros que el "$5K de Alto Riesgo" ya cargado (5% y 10%):
-- en The5ers el plan de alto riesgo cambia de reglas segun el tamano, por eso
-- va en una fila aparte con el tamano en el nombre.
--
-- El reparto va en 80, como las otras cuatro filas de The5ers: el tablero de
-- esta cuenta no lo muestra, asi que se toma el de la firma. Si el plan de
-- alto riesgo de 50K reparte otra cosa, se corrige aqui.
--
-- Queda fuera a proposito:
--   - la idea de trade: la mitad de la diaria es regla de WSFunded, no de esta.
--   - la hora de reset: el tablero no la dice y la fila hermana de alto riesgo
--     tambien la tiene vacia.
--   - los 30 dias de inactividad: esta tabla no tiene esa columna (vive en
--     reglas, por cuenta).
--
-- Corrido el 19/11/2026.

insert into reglas_plantillas
  (prop_firm, plan, fase, perdida_diaria_max_pct, drawdown_max_pct,
   objetivo_fase_pct, min_dias_trading, trade_idea_pct, reparto_pct,
   hora_reset, zona_horaria, drawdown_trailing, fuente_url)
values
  ('The5ers', '$50K de Alto Riesgo', 'Challenge F1', 4, 8, 8, 3,
   null, 80, null, null, false, 'https://hub.the5ers.com/')
on conflict (prop_firm, plan, fase) do update set
  perdida_diaria_max_pct = excluded.perdida_diaria_max_pct,
  drawdown_max_pct       = excluded.drawdown_max_pct,
  objetivo_fase_pct      = excluded.objetivo_fase_pct,
  min_dias_trading       = excluded.min_dias_trading,
  reparto_pct            = excluded.reparto_pct,
  drawdown_trailing      = excluded.drawdown_trailing,
  fuente_url             = excluded.fuente_url;

select prop_firm, plan, fase, perdida_diaria_max_pct, drawdown_max_pct,
       objetivo_fase_pct, min_dias_trading, trade_idea_pct, reparto_pct,
       drawdown_trailing
  from reglas_plantillas
 where prop_firm = 'The5ers'
 order by plan, fase;
