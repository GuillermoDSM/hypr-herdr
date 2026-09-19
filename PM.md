# Project Management

Estados: `[x]` hecho, `[ ]` pendiente.

## Estado actual

- Estado: **vertical slice operativa, todavía no release v0.1**.
- Runtime validado con Herdr 0.9.1/protocolo 22: 6 spaces, 6 tabs, 11 panes, 6 agentes y 11 terminales adjuntas.
- `openLast`/`release` y el lease global están operativos; la última comprobación dejó el plugin en `ready`, con preparación `11/11` y un lease activo.
- Layout BSP de Hyprland y ratios de Herdr sincronizados; el caso `wW` conserva PIDs, PTY y proporciones.
- Sidebar validado con contraste WCAG, mínimo de 160 unidades lógicas y solape anti-franja para escalas fraccionarias.
- Attach aislado implementado mediante `HERDR_CONFIG_PATH`; la configuración global de Herdr no se modifica.
- La implementación funcional está publicada en la rama principal; esta revisión actualiza su documentación.
- Validaciones actuales: manifiesto, qmllint, smoke de Herdr, panel, leases, workspaces y `AttachConfigSmoke`.

## Próximos pasos priorizados

- [ ] Recrear explícitamente los sockets de `HerdrClient` después de reiniciar `herdr server` y eliminar la necesidad de reiniciar `omarchy-shell`.
- [ ] Completar y probar recuperación de transacciones parciales, leases existentes y panes después de reinicios.
- [ ] Validar manualmente selección, arrastre y click derecho en una terminal normal con el attach aislado.
- [ ] Documentar el comportamiento de OpenCode y otras aplicaciones que solicitan mouse reporting propio.
- [ ] Ejecutar la matriz final de aceptación con varios estados de agentes, terminales, monitores y ventanas especiales antes de declarar v0.1.

## Backlog

- US-B01: Un arriendo independiente por monitor.
- US-B02: Aplicar eventos incrementales sin pedir un snapshot completo.
- US-B03: Restaurar geometría de una terminal cerrada manualmente.
- US-B04: Sincronizar sesiones Herdr remotas.
- US-B05: Hibernación y límites de recursos para agentes.
- US-B06: Reconectar sockets automáticamente después de reiniciar el servidor Herdr.
- US-B07: Validar y documentar mouse nativo frente a mouse reporting de cada aplicación.

## Sprint 0 - Base actual

### US-001 - Plugin instalable

- [x] Crear `manifest.json` schema v1 con panel `keepLoaded`.
- [x] Añadir codec base64url para nombres y `app-id`.
- [x] Documentar instalación, validación y binding de entrada.

### US-002 - Cliente Herdr

- [x] Resolver socket por `HERDR_SOCKET_PATH`, `HERDR_SESSION` y XDG.
- [x] Consumir `session.snapshot` de los protocolos 20 y 22.
- [x] Suscribirse a eventos de spaces, tabs, panes y agentes.
- [x] Refrescar por snapshot autoritativo con debounce.
- [x] Reconectar con backoff y mostrar incompatibilidad o desconexión.

### US-003 - Sidebar

- [x] Mostrar spaces y agentes globales con su estado y ubicación.
- [x] Integrar colores, tipografía y componentes de Omarchy.
- [x] Mostrar el panel solo en workspaces con nombre `herdr:*`.
- [x] Enfocar una ventana de pane ya adjunta por `app-id`.
- [x] Redimensionar desde el borde y persistir el ancho como proporción del monitor.

### US-004 - IPC y navegación base

- [x] Exponer `openLast`, `openSpace`, `focusPane`, `status` y `reconcile`.
- [x] Activar workspaces `herdr:*` mediante navegación nombrada provisional.
- [x] Sincronizar la selección con el workspace enfocado.

### US-005 - Validación base

- [x] Validar el manifiesto con Omarchy.
- [x] Pasar `qmllint`.
- [x] Pasar smoke test del cliente contra Herdr.
- [x] Pasar smoke test del panel.
- [x] Pasar smoke tests de lease coordinator, repetición del lease y workspace manager.
- [x] Pasar smoke test de generación de configuración aislada para attach.

## Sprint 1 - Spike de Slot Leasing

Estado: **completado, GO con vacíos desechables**. Ver `SLOT_LEASING_SPIKE.md`.

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
- [x] Recrear un original vacío sin reglas `persistent`.
- [x] Validar navegación relativa aceptada en v0.1.
- [x] Documentar resultado y decisión go/no-go.

**Technical notes:** los workspaces vacíos son desechables. El nombre leased conserva home ID, slot y nombre original; si no existe parked al liberar, se recrea vacío.

## Sprint 2 - Lease Coordinator

Estado: **completado**.

### US-201 - Identidad interna

- [x] Asignar un home ID positivo y estable por space Herdr.
- [x] Detectar colisiones antes de asignar home o parking IDs.
- [x] Codificar home ID y space ID en nombres estables.
- [x] Codificar slot y nombre original en el nombre leased.
- [x] Reconocer un parked workspace como opcional.

**Technical notes:** resolver workspaces Herdr por nombre, no por ID actual. El rango alto es reservado lógicamente, pero cada ID debe comprobarse contra el estado real de Hyprland.

### US-202 - Transacciones de leasing

- [x] Implementar acquire desde el workspace numérico actual.
- [x] Implementar switch del space que posee el slot.
- [x] Implementar migración del portal a otro slot.
- [x] Implementar `release()` idempotente.
- [x] Serializar operaciones y confirmar cada estado desde Hyprland.

**Technical notes:** permitir una sola transacción activa. Acquire aparca el original y entrega el slot a Herdr. Release restaura parked cuando existe; si desapareció vacío, recrea el slot desde la metadata leased. Nunca asignar un ID ocupado.

### US-203 - IPC de leasing

- [x] Convertir `openLast` en toggle acquire/release.
- [x] Hacer que `openSpace` use el slot arrendado.
- [x] Añadir `release` al `IpcHandler`.
- [x] Extender `status` con slot, propietario, home, parking y fase.
- [x] Eliminar navegación nombrada provisional.

### US-204 - Pruebas del coordinador

- [x] Probar acquire, switch, migrate y release.
- [x] Probar colisiones y solicitudes concurrentes.
- [x] Probar que `recoveryRequired` bloquea nuevas mutaciones.

## Sprint 3 - Workspaces y terminales

Estado: **completado**.

### US-301 - Reconciliar workspaces Herdr

- [x] Asignar un home ID por cada space vivo y materializarlo con su primera terminal.
- [x] Adoptar workspaces `herdr:*` existentes sin duplicarlos.
- [x] Gestionar creación, cierre, renombre y movimiento de spaces.
- [x] No destruir un workspace con ventanas GUI ajenas.

### US-302 - Adjuntar panes

- [x] Crear una terminal por pane con `xdg-terminal-exec` y `uwsm-app`.
- [x] Usar un `app-id` estable y comprobar duplicados.
- [x] Ejecutar `herdr terminal attach <id> --takeover` solo para la ventana propia.
- [x] Reconciliar panes creados, cerrados y movidos.
- [x] Recrear una terminal cerrada al seleccionar su pane.

**Technical notes:** antes de `--takeover`, verificar que el `app-id` pertenece al pane esperado y que no existe otra ventana administrada. Cerrar la vista no debe cerrar el pane ni su proceso Herdr.

### US-303 - Preparación y rendimiento

- [x] Preparar terminales faltantes con concurrencia limitada.
- [x] Exponer estados `preparing` y `ready`.
- [x] Evitar procesos, polling y escrituras durante un switch.

### US-304 - Sincronización de layout

- [x] Leer la geometría BSP de las ventanas gestionadas desde Hyprland.
- [x] Traducir splits a rutas y ratios de `layout.set_split_ratio`.
- [x] Persistir la firma inicial de panes para no reescribir layouts sin cambios.
- [x] Verificar sincronización inicial e inversa en un workspace con tres panes.

### US-305 - Attach y mouse aislado

- [x] Generar `hypr-herdr-attach.toml` en el estado de Quickshell.
- [x] Lanzar cada attach con `HERDR_CONFIG_PATH` sin tocar la configuración global.
- [x] Mantener compatibilidad explícita con protocolos Herdr 20 y 22.
- [x] Cubrir la generación TOML con `AttachConfigSmoke`.
- [ ] Validar manualmente selección, arrastre y click derecho en una terminal normal.
- [ ] Documentar el comportamiento de aplicaciones con mouse reporting propio.

## Sprint 4 - Recuperación

Estado: **parcialmente completado**. La reconstrucción básica por nombres/IDs y el bloqueo de mutaciones ante recovery existen; la recuperación completa tras fallos externos sigue pendiente.

### US-401 - Adopción al arrancar

- [x] Reconstruir el arriendo desde nombres e IDs de Hyprland.
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

- [x] Mostrar desconexión y conservar el último estado conocido cuando falla el socket.
- [ ] Permitir release cuando Herdr está desconectado.
- [ ] Recuperar tras reiniciar Herdr.
- [ ] Manejar pane sin `terminal_id` y terminal que falla al iniciar.

### US-404 - Ciclo de vida de sockets

- [ ] Recrear explícitamente los sockets de `HerdrClient` después de un error de conexión.
- [ ] Evitar que un `herdr server stop`/start deje el plugin en `connecting` o `incompatible` hasta reiniciar el shell.
- [ ] Añadir una prueba de reinicio del servidor con snapshot, eventos y reconciliación posterior.

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

### US-503 - Ciclo de vida y flujo de desarrollo

- [x] Alinear `open`, `close` y `show` con el contrato de paneles de Omarchy.
- [x] Hacer que `openSpace` abra la sidebar.
- [x] Exponer el estado de la vista en `status` (`panel.opened`, `panel.visible`, `panel.onHerdrWorkspace`).
- [x] Añadir `tests/dev.sh` con `sync`, `watch`, `open`, `release`, `hide`, `show`, `status`, `reload`, `enable` y `disable`.
- [x] Documentar detach como `release` y el plugin como siempre cargado.
- [x] Conservar el inventario `app-id`/`terminal_id` durante hot reload y cancelar operaciones transitorias al desactivar el manager.

### US-504 - Sidebar compacto y creación de spaces

- [x] Eliminar del sidebar el título `HERDR` y el resumen visual de spaces/panes, conservando esos datos en `status` para diagnóstico.
- [x] Reducir la altura, padding y separación de los botones de spaces.
- [x] Reservar la mitad inferior del sidebar para la lista global de agents y compactar sus filas.
- [x] Mostrar el nombre del proyecto (`workspace.label`) con mayor contraste que el nombre del agent.
- [x] Añadir el botón `New` debajo de spaces, fuera del `Flickable`, para que permanezca visible.
- [x] Crear el nuevo space mediante `workspace.create` de la API de Herdr, usando el `cwd` actual y `HOME` como fallback.
- [x] Esperar el snapshot y la reconciliación del pane antes de seleccionar, enfocar y abrir el nuevo space.
- [x] Evitar doble creación, mostrar errores y mantener el flujo disponible cuando todavía no existen spaces.
- [x] Añadir pruebas de layout, compactación, contraste y creación en una sesión Herdr desechable.

**Technical notes:** `Panel.qml` concentra el layout del sidebar y mantiene la operación `New` pendiente hasta que `HerdrClient` confirma el workspace y `WorkspaceManager` reconcilia su pane. `HerdrClient` usa un socket de comando separado para `workspace.create`; la terminal se abre mediante el pane creado por Herdr y la reconciliación existente, sin lanzar una terminal independiente.

**Technical notes:** un symlink en `~/.config/omarchy/plugins/` no recibe hot reload porque el watcher del shell usa `inotifywait -r`, que no atraviesa symlinks. El checkout se sincroniza con `rsync` a un directorio real y `watch` repite la sincronización en cada guardado. `disable` se rechaza si hay un arriendo activo.

**Technical notes:** el modelo de `Hyprland.workspaces` conserva objetos obsoletos tras `change_id` (Quickshell ignora `changeworkspaceid` y `Hyprland.refreshWorkspaces()` no crea ni elimina objetos), así que el lease decide sobre `hyprctl -j workspaces` y `hyprctl -j activeworkspace` con una caché refrescada por eventos. `tests/lease-repeat-smoke.sh` cubre adquirir, liberar y volver a adquirir reutilizando el mismo parked.

**Technical notes:** `Color.muted` es un tono de superficie en varios temas (1.59:1 sobre el fondo actual), así que el sidebar no lo usa para texto: el secundario es `Util.alpha(Color.popups.text, 0.65)` (7.62:1 con el tema hackerman) y los estados `idle`/`unknown` usan 0.65/0.5. `tests/PanelSmoke.qml` verifica contraste WCAG ≥ 4.5:1 para texto y ≥ 3:1 para glifos de estado.

**Technical notes:** el mínimo del sidebar es `Style.space(160)` y los límites se aplican en píxeles; ya no hay piso de ratio fijo, así que arrastrar hasta el mínimo funciona en cualquier monitor. A escala 1.25 el borde bar/sidebar cae en 32.5 px físicos y el redondeo deja una franja de 1 px; el sidebar solapa una unidad lógica con `margins.top/bottom: -1` (verificado en `hyprctl -j layers`: `y` pasa de 26 a 25 y la reserva no cambia).

**Technical notes:** Herdr 0.9.1 usa protocolo 22 y la suite lo valida; el cliente también conserva compatibilidad explícita con protocolo 20. La versión actual de `AttachConfig.js` genera una copia por ventana y respeta una configuración `mouse_capture` explícita del usuario; la validación manual de mouse sigue pendiente.

**Technical notes:** el estado operativo validado en local es `ready`, con 6 workspaces, 11 panes y 11 terminales adjuntas. El estado no constituye todavía la aceptación completa de v0.1: falta validar reconexión tras reiniciar Herdr y la matriz completa de terminales, agentes, monitores y recuperación.
