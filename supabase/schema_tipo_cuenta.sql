-- Tipo de cuenta: no todas se monitorean igual.
--
--   fondeo            cuenta de prop firm: tiene reglas (pérdida diaria,
--                     drawdown, objetivo) y se da por perdida al cruzarlas
--   capital_inversor  capital propio o de un inversor: no hay prop firm
--                     detrás, así que no corresponde marcarla "failed"
--
-- El agente solo aplica la vigilancia de límites a las de tipo 'fondeo'.
-- Sin dato se asume 'fondeo', que es lo que eran todas antes de esta columna.

alter table cuentas add column if not exists tipo text not null default 'fondeo';

-- Darwinex (broker Tradeslide) es capital inversor, no cuenta de fondeo.
update cuentas
   set tipo = 'capital_inversor'
 where broker ilike '%tradeslide%';
