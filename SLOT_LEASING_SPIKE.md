# Workspace Slot Leasing Spike

## Resultado

**NO-GO para la arquitectura descrita en el PRD.** `change_id` funciona, pero hay dos bloqueos para usar home IDs altos en el monitor normal:

1. `e+1` y `SUPER+TAB` incluyen los workspaces internos del mismo monitor.
2. Un workspace vacío aparcado desaparece al perder foco, eliminando su metadata de recuperación.

Un monitor virtual aísla los IDs internos de la navegación relativa, pero añade infraestructura permanente y obliga a mover workspaces entre monitores. Esa variante puede cambiar geometría y no cumple la arquitectura mínima aprobada.

## Entorno

- Hyprland `0.56.2`.
- Omarchy `4.0.1`.
- Un monitor físico y un output headless temporal.
- API confirmada: `hl.dsp.workspace.change_id({ workspace, id })`.

## Evidencia

| Prueba | Resultado |
|---|---|
| IDs positivos y nombres renombrados | PASS |
| Ventanas tiled y geometría | PASS |
| Ventana floating y geometría | PASS |
| Grupo y fullscreen | PASS |
| Cambio de propietario en un dispatcher compuesto | PASS |
| Barra estándar y foco por número | PASS |
| Reconstrucción desde un proceso Quickshell nuevo | PASS |
| Rollback tras rename, parking, switch y release parciales | PASS |
| Aislamiento en monitor virtual | PASS |
| `e+1` con IDs internos en monitor virtual | PASS |
| `e+1` con IDs internos en monitor activo | FAIL: enfoca el ID interno |
| Regla numérica durante el arriendo | WARN: se aplica al space Herdr |
| Workspace original vacío | FAIL: Hyprland lo destruye al perder foco |

El dispatcher compuesto aceptado por Hyprland ejecuta varios `hl.dispatch(...)` dentro de una sola llamada y termina con un único cambio de foco. No se realizó una medición frame a frame, porque el no-go ya queda determinado por navegación y recuperación.

La recarga se validó arrancando un segundo proceso Quickshell que reconstruyó propietario y workspace aparcado desde Hyprland. No se reinició el shell real para no interrumpir la sesión del usuario.

## Seguridad

El harness `tests/slot-leasing-spike.sh`:

- Aborta si cualquiera de sus IDs o clases ya existe.
- Crea todas sus ventanas en un output headless temporal.
- Usa exclusivamente IDs mayores que `10`.
- Instala un `trap` para cerrar solo clientes `hypr-herdr-spike-*`.
- Desactiva su regla temporal, restaura el foco y elimina el output virtual.
- Verifica que no queden clientes de prueba.

Después de cada ejecución se comprobó que solo quedaban el monitor, workspaces y ventanas originales.

## Decisión

No implementar el Sprint 2 de Lease Coordinator hasta elegir una alternativa:

1. Router de navegación y widget de workspaces propio.
2. Variante con monitor virtual permanente, sujeta a un spike específico de geometría y lifecycle.
3. Leasing con una regla `persistent` temporal para workspaces vacíos y reemplazo de navegación relativa.

La opción 1 es la única que evita depender de workspaces ocultos y de un output artificial, aunque deja de conservar intactos el widget y todos los bindings nativos.
