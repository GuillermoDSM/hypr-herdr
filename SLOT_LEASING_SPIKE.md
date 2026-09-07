# Workspace Slot Leasing Spike

## Resultado

**GO con workspaces vacíos desechables.** `change_id` conserva workspaces con contenido. Si el original está vacío, Hyprland puede destruirlo: el lease conserva su identidad y `release` lo recrea.

No se necesitan reglas `persistent`, ventanas sentinel ni un monitor virtual permanente. La navegación relativa puede visitar los IDs internos en v0.1; se acepta y documenta como comportamiento nativo.

## Entorno

- Hyprland `0.56.2`.
- Omarchy `4.0.1`.
- Output headless temporal para aislamiento.
- APIs confirmadas: `change_id`, `rename`, `focus` y dispatchers Lua compuestos.

## Evidencia

| Prueba | Resultado |
|---|---|
| IDs positivos y nombres renombrados | PASS |
| Tiled, floating, grupos, fullscreen y geometría | PASS |
| Cambio de propietario en un dispatcher compuesto | PASS |
| Barra estándar y foco por número | PASS |
| Reconstrucción desde un proceso Quickshell nuevo | PASS |
| Rollback de rename, parking, switch y release | PASS |
| Original vacío desaparece sin `persistent` | PASS, esperado |
| Lease reconstruible sin workspace aparcado | PASS |
| Release recrea ID y nombre del original vacío | PASS |
| Space Herdr vacío reutiliza el workspace actual | PASS |
| `e+1` alcanza un home Herdr y `previous` regresa | PASS, aceptado |
| Regla numérica durante el arriendo | WARN: se aplica al space Herdr |

El segundo spike reproducible está en `tests/disposable-empty-spike.sh`. El primer harness permanece en `tests/slot-leasing-spike.sh` para validar conservación de layouts y rollback.

## Estrategia validada

- Un space Herdr con ventanas sobrevive naturalmente en su home ID alto.
- El workspace original aparcado sobrevive mientras tenga ventanas.
- Si el original desaparece por quedar vacío, no hay contenido que preservar.
- El nombre leased del workspace Herdr guarda home ID, slot y nombre original.
- Si `release` no encuentra el original aparcado, crea un workspace vacío con la identidad guardada.
- Un space Herdr vacío puede reutilizar el workspace vacío actual y volver a crearse cuando sea necesario.

## Seguridad

Ambos harnesses:

- Abortan ante colisiones de IDs o clases.
- Ejecutan ventanas solo en un output headless temporal.
- Usan exclusivamente IDs mayores que `10`.
- Instalan rollback para éxito, error, señal y timeout.
- Cierran solo clientes con prefijos de spike.
- Eliminan el output temporal y verifican que no queden residuos.

No se reinició el shell real ni se modificó configuración persistente.

## Decisión

Continuar con Workspace Slot Leasing bajo estas reglas:

1. Los workspaces vacíos son desechables y recreables.
2. El lease guarda toda la identidad necesaria en nombres de Hyprland.
3. No usar `persistent` ni estado privado en disco.
4. Aceptar navegación relativa hacia home y parking IDs en v0.1.
5. Mantener la barra y bindings numéricos sin cambios.
