# Centro de Monitoreo MT5

Ver el estado de todas las cuentas de la VPS desde una web, sin abrir un solo terminal. Y encender o apagar cualquier bot desde ahí.

Diseño completo en [`docs/Centro de Monitoreo MT5 - Arquitectura.pdf`](docs/Centro%20de%20Monitoreo%20MT5%20-%20Arquitectura.pdf).

## Estructura

```
mql5/
  EA_Recolector_A/          Fondeo, versión cerrada el 19/09/2026: la que opera en la VPS
  EA_Recolector_B/          Fondeo, versión viva: acá van los cambios
  EA_Recolector_Inversor_A/ Cuentas de capital inversor (Darwinex Zero)
  Include/           Interruptor.mqh - lo que cada bot propio incluye para obedecer parar/arrancar
agente/              Programa que corre en la VPS: junta Common, sube a Supabase, vigila límites
supabase/            Esquema SQL y políticas RLS de las 7 tablas
panel/               Web estática (GitHub Pages) - consulta Supabase, pinta estado, enciende/apaga bots
docs/                PDFs de arquitectura y diagramas
```

## Versiones del recolector

Cada versión se cierra en una fecha y no se vuelve a tocar. La siguiente arranca
donde quedó la anterior, con su propio nombre. **Nunca se copia una sobre otra ni
se sobrescribe una versión cerrada.**

| Versión | Estado | Dónde va |
|---|---|---|
| `EA_Recolector_A` | Cerrada el 19/09/2026 | Las cuentas de fondeo que operan cross. Queda como registro. |
| `EA_Recolector_B` | Abierta el 19/09/2026 | Línea de fondeo, versión viva: acá van los cambios. |
| `EA_Recolector_Inversor_A` | Abierta el 19/09/2026 | Cuentas de capital inversor (Darwinex Zero). Línea propia. |

Las cuentas de capital inversor llevan su propio recolector, no el de fondeo:
separa comisión de swap y además reporta el swap acumulado de las posiciones
abiertas, que en un portafolio sostenido en el tiempo es parte de lo que cada
activo está costando.

**Las dos corren a la vez en la VPS**, en cuentas distintas. Eso es seguro
porque cada archivo que escribe el EA lleva el número de cuenta en el nombre
(`estado_<login>.json`, `spreads_<login>.jsonl`, …): dos versiones en cuentas
distintas nunca tocan el mismo archivo. Lo único prohibido es poner **dos
versiones sobre la misma cuenta**, ahí sí se pisan.

Consecuencia a tener presente: el Agente lee lo que escriben todas las
versiones vivas. Si una versión nueva cambia el formato de un archivo, el
Agente tiene que seguir entendiendo el formato de las versiones anteriores que
sigan en producción, o esas cuentas dejan de reportar.

## Orden de construcción

1. `mql5/EA_Recolector_*` — sin dato no hay nada que mirar
2. `agente/`
3. `supabase/` (tablas)
4. `mql5/Include/Interruptor.mqh`
5. `panel/`

## Pendiente de decidir

- Hora de reset diario de cada prop firm (varía entre firms)
- Si se quieren avisos al móvil cerca de un límite
