-- El reset diario de estas prop firms es a medianoche del servidor, que va
-- GMT+3 en verano y GMT+2 el resto del año (documentado por FundedNext, y
-- coincide con lo calculado desde los contadores de FundingPips y GFT).
--
-- Eso es la hora de Europa del Este, así que en vez de fijar "21:00 UTC" -que
-- se rompería en el cambio de horario de octubre- se guarda medianoche con la
-- zona horaria, y el ajuste lo hace solo el agente.
--
-- Correr en el SQL Editor de Supabase (rol postgres).

update reglas_plantillas
set hora_reset = '00:00', zona_horaria = 'Europe/Athens', actualizado_en = now();

update reglas
set hora_reset = '00:00', zona_horaria = 'Europe/Athens'
where cuenta_id in (select id from cuentas where prop_firm is not null);
