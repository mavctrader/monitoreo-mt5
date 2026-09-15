# Centro de Monitoreo MT5

Ver el estado de todas las cuentas de la VPS desde una web, sin abrir un solo terminal. Y encender o apagar cualquier bot desde ahí.

Diseño completo en [`docs/Centro de Monitoreo MT5 - Arquitectura.pdf`](docs/Centro%20de%20Monitoreo%20MT5%20-%20Arquitectura.pdf).

## Estructura

```
mql5/
  EA_Recolector/     EA que lee cada cuenta y escribe en la carpeta Common (un gráfico por terminal)
  Include/           Interruptor.mqh - lo que cada bot propio incluye para obedecer parar/arrancar
agente/              Programa que corre en la VPS: junta Common, sube a Supabase, vigila límites
supabase/            Esquema SQL y políticas RLS de las 7 tablas
panel/               Web estática (GitHub Pages) - consulta Supabase, pinta estado, enciende/apaga bots
docs/                PDFs de arquitectura y diagramas
```

## Orden de construcción

1. `mql5/EA_Recolector` — sin dato no hay nada que mirar
2. `agente/`
3. `supabase/` (tablas)
4. `mql5/Include/Interruptor.mqh`
5. `panel/`

## Pendiente de decidir

- Hora de reset diario de cada prop firm (varía entre firms)
- Si se quieren avisos al móvil cerca de un límite
