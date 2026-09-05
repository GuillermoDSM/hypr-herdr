# Project Management

Estados: `[x]` hecho, `[ ]` pendiente.

## Backlog

- US-B01: Un arriendo independiente por monitor.
- US-B02: Aplicar eventos incrementales sin pedir un snapshot completo.
- US-B03: Restaurar geometría de una terminal cerrada manualmente.
- US-B04: Sincronizar sesiones Herdr remotas.
- US-B05: Hibernación y límites de recursos para agentes.

## Sprint 0 - Base actual

### US-001 - Plugin instalable

- [x] Crear `manifest.json` schema v1 con panel `keepLoaded`.
- [x] Añadir codec base64url para nombres y `app-id`.
- [x] Documentar instalación, validación y binding de entrada.

### US-002 - Cliente Herdr

- [x] Resolver socket por `HERDR_SOCKET_PATH`, `HERDR_SESSION` y XDG.
- [x] Consumir `session.snapshot` del protocolo 20.
- [x] Suscribirse a eventos de spaces, tabs, panes y agentes.
- [x] Refrescar por snapshot autoritativo con debounce.
- [x] Reconectar con backoff y mostrar incompatibilidad o desconexión.

### US-003 - Sidebar

- [x] Mostrar spaces, tabs, panes y estado de agentes.
- [x] Integrar colores, tipografía y componentes de Omarchy.
- [x] Mostrar el panel solo en workspaces con nombre `herdr:*`.
- [x] Enfocar una ventana de pane ya adjunta por `app-id`.

### US-004 - IPC y navegación base

- [x] Exponer `openLast`, `openSpace`, `focusPane`, `status` y `reconcile`.
- [x] Activar workspaces `herdr:*` mediante navegación nombrada provisional.
- [x] Sincronizar la selección con el workspace enfocado.

### US-005 - Validación base

- [x] Validar el manifiesto con Omarchy.
- [x] Pasar `qmllint`.
- [x] Pasar smoke test del cliente contra Herdr.
- [x] Pasar smoke test del panel.

## Sprint 1 - Spike de Slot Leasing

Estado: **completado, NO-GO**. Ver `SLOT_LEASING_SPIKE.md`.

### US-101 - Validar `change_id`

- [x] Verificar disponibilidad de `hl.dsp.workspace.change_id`.
- [x] Cambiar IDs entre workspaces positivos de prueba.
- [x] Confirmar que nombre, ventanas y layout sobreviven.
- [x] Probar tiled, floating, grouped, fullscreen y workspace vacío.
- [x] Evaluar transición al adquirir y cambiar space.

**Technical notes:** usar únicamente slots de prueba fuera de `1..10`. No ejecutar el spike sobre workspaces de trabajo. Registrar cada ID original antes de mutarlo y restaurarlo al finalizar.

### US-102 - Validar integración nativa

- [x] Confirmar barra estándar y foco numérico sin cambios.
- [x] Probar navegación relativa `e+1` y `SUPER+TAB` con IDs altos.
- [x] Probar reglas de Hyprland dirigidas a un número.
- [x] Probar monitor físico más monitor virtual.

### US-103 - Validar fallos

- [x] Interrumpir pasos de rename, parking, switch y release.
- [x] Reconstruir el arriendo desde un proceso Quickshell nuevo.
- [x] Demostrar recuperación sin cargar el plugin.
- [x] Documentar resultado y decisión go/no-go.

**Technical notes:** el spike es un gate. Si hay flicker inevitable, pérdida de estado o recuperación insegura, detener Slot Leasing y diseñar el fallback de router más widget propio descrito en `PRD.md`.

## Sprint 2 - Lease Coordinator

Estado: **bloqueado por el no-go del Sprint 1**. No iniciar hasta actualizar la arquitectura.

### US-201 - Identidad interna

- [ ] Asignar un home ID positivo y estable por space Herdr.
- [ ] Detectar colisiones antes de asignar home o parking IDs.
- [ ] Mantener nombres estables `herdr:<encoded-space-id>`.
- [ ] Codificar nombre, slot y token del workspace aparcado.

**Technical notes:** resolver workspaces Herdr por nombre, no por ID actual. El rango alto es reservado lógicamente, pero cada ID debe comprobarse contra el estado real de Hyprland.

### US-202 - Transacciones de leasing

- [ ] Implementar acquire desde el workspace numérico actual.
- [ ] Implementar switch del space que posee el slot.
- [ ] Implementar migración del portal a otro slot.
- [ ] Implementar `release()` idempotente.
- [ ] Serializar operaciones y confirmar cada estado desde Hyprland.

**Technical notes:** permitir una sola transacción activa. Secuencia acquire: renombrar original, mover original a parking, mover Herdr al slot y enfocar. Release ejecuta el orden inverso. Nunca asignar un ID ocupado ni actualizar la selección antes de confirmación.

### US-203 - IPC de leasing

- [ ] Convertir `openLast` en toggle acquire/release.
- [ ] Hacer que `openSpace` use el slot arrendado.
- [ ] Añadir `release` al `IpcHandler`.
- [ ] Extender `status` con slot, propietario, home, parking y fase.
- [ ] Eliminar navegación nombrada provisional.

### US-204 - Pruebas del coordinador

- [ ] Probar acquire, switch, migrate y release.
- [ ] Probar colisiones y solicitudes concurrentes.
- [ ] Probar que una confirmación fallida bloquea nuevas mutaciones.

## Sprint 3 - Workspaces y terminales

### US-301 - Reconciliar workspaces Herdr

- [ ] Crear un home workspace por cada space vivo.
- [ ] Adoptar workspaces `herdr:*` existentes sin duplicarlos.
- [ ] Gestionar creación, cierre, renombre y movimiento de spaces.
- [ ] No destruir un workspace con ventanas GUI ajenas.

### US-302 - Adjuntar panes

- [ ] Crear una terminal por pane con `xdg-terminal-exec` y `uwsm-app`.
- [ ] Usar un `app-id` estable y comprobar duplicados.
- [ ] Ejecutar `herdr terminal attach <id> --takeover` solo para la ventana propia.
- [ ] Reconciliar panes creados, cerrados y movidos.
- [ ] Recrear una terminal cerrada al seleccionar su pane.

**Technical notes:** antes de `--takeover`, verificar que el `app-id` pertenece al pane esperado y que no existe otra ventana administrada. Cerrar la vista no debe cerrar el pane ni su proceso Herdr.

### US-303 - Preparación y rendimiento

- [ ] Preparar terminales faltantes con concurrencia limitada.
- [ ] Exponer estados `preparing` y `ready`.
- [ ] Evitar procesos, polling y escrituras durante un switch.

## Sprint 4 - Recuperación

### US-401 - Adopción al arrancar

- [ ] Reconstruir el arriendo desde nombres e IDs de Hyprland.
- [ ] Adoptar transacciones completas después de hot reload.
- [ ] Detectar transacciones parciales y bloquear mutaciones.
- [ ] Adoptar terminales existentes por `app-id`.

### US-402 - Recuperación segura

- [ ] Recuperar cada fallo parcial sin sobrescribir workspaces.
- [ ] Mantener `release()` idempotente después de reinicios.
- [ ] Añadir diagnóstico accionable al sidebar y `status`.
- [ ] Documentar comando de emergencia verificado.
- [ ] Documentar liberación previa a deshabilitar o desinstalar.

### US-403 - Fallos externos

- [ ] Permitir release cuando Herdr está desconectado.
- [ ] Recuperar tras reiniciar Herdr.
- [ ] Manejar pane sin `terminal_id` y terminal que falla al iniciar.

## Sprint 5 - Release v0.1

### US-501 - UX final

- [ ] Mostrar estados vacío, preparando, desconectado y recuperación.
- [ ] Confirmar selección y foco únicamente desde eventos reales.
- [ ] Verificar que el sidebar conserva posición durante switches.
- [ ] Revisar accesibilidad, overflow y escalado.

### US-502 - Aceptación

- [ ] Ejecutar todos los criterios de aceptación de `PRD.md`.
- [ ] Probar cambios rápidos con múltiples spaces, tabs y panes.
- [ ] Probar Kitty, Alacritty, Foot y Ghostty disponibles.
- [ ] Medir transición visual y respuesta del sidebar.
- [ ] Pasar validación, lint y suite completa.
- [ ] Actualizar README con límites y recuperación confirmados.
