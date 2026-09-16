# Hypr Herdr

## Resumen

Hypr Herdr integra los spaces y panes de Herdr con el escritorio de Omarchy sin modificar Herdr, Hyprland ni la barra estándar. Cada space de Herdr conserva un workspace normal de Hyprland con un ID interno positivo. Al entrar a Herdr, el space visible arrienda temporalmente el número del workspace actual mediante **Workspace Slot Leasing**.

Para Hyprland y Omarchy, el space Herdr activo es el workspace numérico arrendado. Por eso los bindings `SUPER+1..9`, la barra de workspaces y la navegación normal siguen funcionando sin redirecciones ni widgets sustitutos. Cada pane se presenta como una terminal conectada a su PTY real mediante `herdr terminal attach`.

Un sidebar nativo de Omarchy permite cambiar de space y ver los agentes globales. Hyprland conserva el layout, tamaño y posición de las ventanas; Herdr conserva procesos, sesiones y agentes.

## Estado de la arquitectura

El spike de septiembre de 2026 produjo **GO con workspaces vacíos desechables**. Los workspaces con ventanas se conservan completos; si un original vacío desaparece al perder foco, el lease guarda su identidad y `release()` lo recrea. No se usan reglas `persistent`. La navegación relativa hacia IDs internos se acepta en v0.1. Evidencia: [SLOT_LEASING_SPIKE.md](SLOT_LEASING_SPIKE.md).

## Objetivo

Convertir Herdr en una capa de sesión y navegación integrada con Omarchy:

- Herdr administra spaces, tabs, panes, PTY, agentes y persistencia.
- Hyprland administra workspaces, ventanas, foco, geometría e identidad numérica visible.
- Omarchy presenta el sidebar y coordina el arriendo de slots entre ambos sistemas.

El cambio entre spaces debe sentirse como cambiar el contenido de una misma superficie. No debe crear procesos, mover ventanas ni reconstruir layouts durante la interacción.

## Modelo mental

```text
El número es un slot.
El workspace es el contenido.
Hypr Herdr presta el slot al space activo.
```

Si el usuario invoca Hypr Herdr desde el workspace `2`:

1. El workspace original `2` se aparca en un ID interno alto.
2. El último space Herdr visitado recibe el ID `2`.
3. Hyprland enfoca ese workspace.
4. La barra estándar marca `2` como activo.
5. `SUPER+3` abre el workspace `3` normalmente.
6. `SUPER+2` vuelve directamente al space Herdr, sin intervención del plugin.

Al liberar el arriendo, el space Herdr recupera su ID interno y el workspace original recupera el ID `2`.

## Principios

1. **Usar APIs públicas.** La integración usa el socket de Herdr, `Quickshell.Hyprland`, los dispatchers Lua de Hyprland y el contrato de plugins de Omarchy.
2. **Mantener una sola fuente de verdad por dominio.** Herdr controla sesiones; Hyprland controla geometría e identidad de workspaces; el plugin solo coordina la relación.
3. **Preservar la navegación nativa.** No se reemplazan los bindings numéricos ni el widget estándar de workspaces.
4. **Cambiar identidad, no contenido.** El plugin intercambia IDs de workspaces completos; no transporta sus ventanas.
5. **Preparar antes de mostrar.** Las terminales permanecen abiertas en los workspaces internos para evitar lanzamientos durante la navegación.
6. **Hacer el estado recuperable.** Los nombres de workspace permiten reconstruir y revertir un arriendo tras recargar el shell.
7. **Evitar infraestructura innecesaria.** No habrá plugin binario de Hyprland, plugin de Herdr ni daemon independiente.
8. **Respetar Omarchy.** El plugin usa su tema, componentes, IPC, hot reload e instalación estándar.

## Arquitectura

```text
Herdr server
  ├── space w1 ───────── Hyprland workspace
  │   │                    home ID: 1000000001
  │   │                    name: herdr:v1:1000000001:dzE
  │   ├── pane w1:p1 ─── terminal window + direct attach
  │   └── pane w1:p2 ─── terminal window + direct attach
  └── space wB ───────── Hyprland workspace
      │                    home ID: 1000000002
      │                    name: herdr:v1:1000000002:d0I
      ├── pane wB:p1 ─── terminal window + direct attach
      └── pane wB:p2 ─── terminal window + direct attach

Omarchy shell
  └── Hypr Herdr panel
      ├── sidebar layer-shell
      ├── event coordinator
      └── slot lease coordinator

Example while w1 leases slot 2
  ├── original workspace 2 ── parked at an internal positive ID
  └── space w1 ───────────── ID: 2, name: herdr:v1:1000000001:dzE:leased:...
```

Los IDs anteriores son ilustrativos. La implementación reservará un rango positivo alto y comprobará colisiones antes de asignarlo.

### Mapeo

| Herdr | Omarchy/Hyprland |
|---|---|
| Space | Workspace normal con nombre `herdr:v1:<home_id>:<base64url(space_id)>` |
| Space inactivo | Su ID interno positivo estable dentro del rango reservado |
| Space activo | El ID numérico arrendado, conservando su nombre `herdr:*` |
| Workspace original | Workspace aparcado con nombre de recuperación durante el arriendo |
| Tab | Agrupación visual dentro del sidebar |
| Pane | Ventana terminal con un `app-id` estable |
| Terminal ID | Destino de `herdr terminal attach` |
| Agent status | Estado y color del pane en el sidebar |
| Layout de panes | Layout nativo del workspace en Hyprland |

Los IDs de Herdr son opacos. Una función reversible y segura para nombres de Hyprland y `app-id` codifica los IDs; el código no extrae significado de prefijos como `w` o `p`.

## Workspace Slot Leasing

### Workspaces internos

Los spaces de Herdr son workspaces normales con IDs positivos altos, no `special` workspaces. Cada uno tiene:

- Un `home ID` estable dentro del rango reservado.
- Un nombre estable `herdr:v1:<home_id>:<base64url(space_id)>`.
- Sus propias ventanas, layout y estado de Hyprland.

El nombre estable permite reconocer un workspace Herdr aunque su ID cambie durante un arriendo. Los workspaces internos altos no deben aparecer en la barra numérica estándar, que muestra el rango de slots configurado por Omarchy.

### Workspace original aparcado

Antes de retirar el ID visible al workspace original, el plugin guarda en los nombres de recuperación:

- El slot arrendado.
- Su nombre anterior.
- Un token de versión o transacción.

Formato conceptual:

```text
hypr-herdr:v1:parked:<slot>:<encoded-original-name>:<parking-id>
herdr:v1:<home-id>:<encoded-space-id>:leased:<slot>:<encoded-original-name>:<parking-id>
```

El workspace se mueve después a un ID interno positivo libre. El workspace Herdr cambia temporalmente a un nombre leased que también incluye home ID, slot y nombre original. Si el original aparcado desaparece por quedar vacío, esa metadata permite recrearlo. No se usan reglas `persistent` ni archivos privados.

### Operación central

La arquitectura requiere Hyprland 0.56 o una versión compatible con:

```lua
hl.dsp.workspace.change_id({
  workspace = workspace,
  id = newId
})
```

`change_id` debe conservar el workspace completo, incluyendo sus ventanas y layout. Solo se usarán IDs positivos. El plugin renombra los workspaces antes de cambiar su ID para conservar nombres estables y marcas de recuperación.

### Adquirir un slot

Al ejecutar `openLast()` u `openSpace(id)` desde un workspace numérico sin arriendo activo:

1. Validar que el slot, el workspace original y el space objetivo existen.
2. Validar que el home ID del space objetivo está libre de colisiones y reservar un parking ID para el original.
3. Renombrar el workspace original con la marca de recuperación.
4. Cambiar el ID del workspace original al parking ID.
5. Cambiar el ID del space Herdr desde su home ID al slot numérico.
6. Enfocar el slot numérico.
7. Confirmar el resultado desde los eventos de Hyprland antes de declarar el arriendo activo.

El usuario solo debe ver la transición final del workspace original al space Herdr.

### Cambiar de space

Si el space `w1` ocupa el slot `2` y el usuario selecciona `wB`:

1. Cambiar el ID de `w1` desde `2` a su home ID.
2. Cambiar el ID de `wB` desde su home ID a `2`.
3. Enfocar `2`.
4. Confirmar que `wB` posee el slot y actualizar la selección del sidebar.

Los dispatchers se emiten consecutivamente en una transacción lógica. No se crean terminales ni se mueven ventanas. La atomicidad visual de esta secuencia debe validarse antes de considerar estable la arquitectura.

### Navegación nativa

Mientras `wB` posee el slot `2`:

- `SUPER+2` enfoca directamente `wB` porque su ID real es `2`.
- `SUPER+3` enfoca el workspace `3` sin que Hypr Herdr intercepte el binding.
- La barra estándar marca `2` cuando `wB` está enfocado.
- Reglas e integraciones de Hyprland observan a `wB` como workspace `2` durante el arriendo.
- `SUPER+TAB` puede visitar home y parking IDs; este comportamiento se acepta en v0.1.

Esta última propiedad es intencional, pero las reglas configuradas por número son un riesgo de compatibilidad que debe probarse y documentarse.

### Trasladar el portal

Un arriendo permanece asociado a su slot aunque el usuario navegue a otro workspace. Si Herdr ocupa `2`, salir con `SUPER+3` no libera `2`; `SUPER+2` sigue regresando a Herdr.

Si el usuario invoca explícitamente Hypr Herdr desde otro workspace numérico, el coordinador puede trasladar el portal:

1. Liberar de forma segura el slot anterior.
2. Aparcar el workspace numérico actual.
3. Arrendar su número al último space Herdr visitado.

La primera versión admite un solo arriendo global. El soporte de un arriendo por monitor queda fuera de alcance hasta validar el comportamiento multimonitor.

### Liberar un slot

`release()` ejecuta la transacción inversa:

1. Resolver el space Herdr que posee el slot y el workspace original aparcado.
2. Devolver el space Herdr a su home ID.
3. Devolver el workspace original al slot cuando todavía existe.
4. Si desapareció vacío, recrear el slot y restaurar su nombre desde la metadata leased.
5. Enfocar el workspace restaurado cuando la liberación sea solicitada por el usuario.
6. Confirmar que no quedan marcas de recuperación huérfanas.

Deshabilitar o retirar el plugin requiere liberar primero cualquier arriendo. La documentación debe incluir un procedimiento de recuperación que no dependa de que el panel pueda cargar.

### Recuperación y consistencia

Al iniciar o recargar, el coordinador inspecciona workspaces y nombres antes de reconciliar terminales:

- Adopta workspaces `herdr:*` existentes por nombre, no por su ID actual.
- Detecta workspaces `hypr-herdr:v1:parked:*` y reconstruye la transacción.
- Si encuentra un arriendo completo y coherente, lo adopta.
- Si encuentra una transacción parcial, evita nuevos cambios y presenta una acción de recuperación.
- Nunca sobrescribe un ID ocupado ni adivina qué workspace debe destruirse.
- `status()` expone slot, space propietario, home IDs, parking ID y estado de recuperación.
- `release()` y el procedimiento de emergencia restauran el workspace original de forma idempotente.

## Sidebar

El sidebar es una superficie `PanelWindow` de Quickshell con layer-shell:

- Se muestra cuando el workspace enfocado tiene un nombre `herdr:*`, sin depender de que su ID sea interno o arrendado.
- Se oculta en workspaces numéricos originales, especiales o ajenos al plugin.
- Reserva mediante su zona exclusiva un ancho ajustable desde el borde derecho.
- Persiste el ancho como proporción del monitor, con límites mínimos y máximos en unidades lógicas.
- No forma parte del árbol de ventanas de Hyprland.
- Conserva posición y apariencia durante el cambio de space.
- Usa `Color`, `Style` y componentes compartidos de Omarchy.
- Deriva los textos secundarios de `Color.popups.text` con `Util.alpha` (α = 0.65) para garantizar contraste ≥ 4.5:1 sobre el fondo del sidebar en cualquier tema; nunca usa `Color.muted` para texto.

La primera versión crea un sidebar nuevo con la misma jerarquía conceptual del original: spaces arriba y agentes globales abajo. El sidebar original de Herdr forma parte de su TUI y no tiene una interfaz pública para incrustarlo en Quickshell.

## Experiencia de usuario

### Entrada

`SUPER+CTRL+RETURN`, hoy asignado a abrir la TUI completa de Herdr, invoca `openLast()`:

1. Si el workspace actual no es Herdr, el plugin identifica su slot numérico y el último space Herdr visitado.
2. Adquiere un arriendo nuevo o traslada el existente al slot actual.
3. Enfoca el space Herdr ya preparado.
4. El sidebar aparece con la selección confirmada por Hyprland.
5. Si el workspace actual ya es el propietario Herdr del slot, la misma acción ejecuta `release()` y restaura el workspace original.

Si Herdr no tiene spaces, el plugin no aparca el workspace actual. Muestra un estado vacío y una acción para abrir Herdr o crear el primer space, según la API pública instalada.

### Cambio de space

Al seleccionar un space, el coordinador intercambia qué workspace Herdr posee el slot arrendado. El resaltado solo cambia cuando los eventos de Hyprland confirman al nuevo propietario.

El camino interactivo no consulta disco, no lanza terminales y no mueve ventanas.

### Salida

- Cerrar/detach es `release()`: el space vuelve a su home ID, el workspace original se restaura y la sidebar se oculta. El plugin permanece cargado y conectado, así que reabrir es inmediato.
- `close()` o `omarchy-shell shell hide` solo ocultan la vista; no liberan el arriendo. La sidebar reaparece al enfocar el workspace arrendado.
- Navegar con bindings normales abandona visualmente Herdr, pero conserva el portal para volver al slot.
- Invocar la acción de Herdr desde el workspace Herdr que posee el slot ejecuta `release()` y restaura el workspace original.
- `SUPER+W` conserva su comportamiento nativo de cerrar ventana: la sidebar es una layer-shell sin foco de teclado y los bindings del compositor no llegan a ella. El gesto de detach es el binding de entrada de Herdr, que actúa como toggle desde el slot arrendado.
- Habilitar y deshabilitar el plugin es instalación, no uso diario. `disable` requiere una liberación explícita o el procedimiento de recuperación documentado.

### Agentes y panes

Cada fila de agente muestra estado, space, tab cuando sea relevante y nombre del agente. La lista es global y prioriza estados accionables como `blocked`; seleccionar un agente enfoca la ventana de su pane.

Seleccionar un pane enfoca su ventana dentro del workspace Herdr activo. Si la ventana se cerró, el plugin la recrea y ejecuta:

```sh
herdr terminal attach <terminal_id> --takeover
```

Cerrar la ventana desmonta la vista, pero no cierra el pane ni el proceso administrado por Herdr. Una ventana recreada vuelve al layout como una ventana nueva; la primera versión no restaura su antigua posición después de un cierre manual.

`herdr terminal attach --takeover` puede activar mouse reporting dentro de la aplicación terminal. En ese caso la selección de texto usa el modificador de bypass del emulador, normalmente `Shift` más arrastre. El plugin no instala mappings específicos de Kitty, Alacritty, Foot o Ghostty.

### Aplicaciones GUI

El usuario puede abrir aplicaciones GUI en un workspace Herdr. Hyprland las conserva con ese workspace cuando cambia entre su home ID y el slot arrendado. Hypr Herdr no intenta registrar esas aplicaciones dentro de Herdr.

## Sincronización

### Conexión con Herdr

El panel usa `Quickshell.Io.Socket` para conectarse al socket Unix publicado por Herdr. Al conectar:

1. Abre `events.subscribe` y comienza a almacenar invalidaciones.
2. Solicita `session.snapshot` mediante una segunda conexión.
3. Construye el modelo de spaces, tabs, panes y agentes.
4. Aplica las invalidaciones recibidas solicitando un snapshot autoritativo.
5. Reconcilia las terminales esperadas con las ventanas existentes.

La suscripción incluye eventos de creación, cierre, movimiento, cambio de nombre, foco y estado de agente. No ejecuta polling mientras el socket funcione.

Si el socket se desconecta, el sidebar conserva el último estado, muestra que Herdr está desconectado e intenta reconectar con espera progresiva limitada. Tras reconectar solicita un snapshot completo.

### Conexión con Hyprland

El panel usa `Quickshell.Hyprland` para observar:

- Workspace enfocado.
- IDs, nombres y monitores de workspaces existentes.
- Ventanas de cada workspace.
- Clase o `app-id` de las terminales adjuntas.
- Confirmaciones necesarias para cada transición de leasing.

Usa dispatchers de Hyprland para cambiar IDs, renombrar y enfocar workspaces y ventanas. El modelo de `Quickshell.Hyprland` puede conservar objetos obsoletos tras `change_id`, así que el lease consulta `hyprctl -j workspaces` y `hyprctl -j activeworkspace` como fuente autoritativa para sus decisiones; el resto del plugin no usa `hyprctl` para polling.

### Reconciliación de terminales

Cada pane vivo debe tener como máximo una ventana `direct attach`:

- Al iniciar, el plugin crea en segundo plano las ventanas faltantes en el home workspace de su space.
- Al recibir `pane.created`, crea la ventana en el workspace de su space, tenga home ID o slot arrendado.
- Al recibir `pane.closed`, cierra únicamente la ventana que representa ese pane.
- Al recibir `pane.moved`, mueve o recrea la ventana en el workspace del space de destino.
- Antes de crear una ventana, comprueba su `app-id` para evitar duplicados.
- Durante hot reload conserva en memoria la relación entre `app-id` y `terminal_id`; no adopta silenciosamente una vista conocida para otra generación del terminal.

El plugin lanza la terminal configurada por el usuario mediante `xdg-terminal-exec --app-id`, dentro de la sesión gráfica con `uwsm-app`. No asume Kitty, Alacritty, Foot ni Ghostty.

## Rendimiento

### Metas

- Entrada a Herdr: una sola transición visual después de adquirir el slot.
- Cambio entre spaces: una sola transición visual después del intercambio de IDs.
- Respuesta visual del sidebar: menos de 16 ms desde el evento confirmado.
- Ningún proceso nuevo durante cambios entre spaces preparados.
- Ningún temporizador de polling en estado conectado.
- Sin escrituras a disco durante la navegación.

### Estrategia

El plugin mantiene una terminal adjunta por pane. Hyprland conserva las ventanas de workspaces no visibles sin renderizarlas como contenido activo. Las operaciones de leasing son secuencias cortas de dispatchers y no recorren ni transportan ventanas.

El arranque puede abrir varias terminales. El reconciliador limita la concurrencia para no bloquear `omarchy-shell`, pero completa la preparación antes de considerar cada space listo. El sidebar distingue entre `preparing` y `ready`.

## Plugin de Omarchy

El repositorio sigue el contrato oficial para plugins de terceros:

```text
hypr-herdr/
├── manifest.json
├── Panel.qml
├── HerdrClient.qml
├── WorkspaceLease.qml
├── WorkspaceManager.qml
├── IdCodec.js
├── LeaseCodec.js
├── README.md
├── PRD.md
├── LICENSE
└── tests/
```

El plugin permanece cargado para conservar la conexión de eventos, el layer-shell y el coordinador de leasing dentro de `omarchy-shell`. Registra estos métodos IPC:

| Método | Resultado |
|---|---|
| `openLast()` | Desde un workspace normal adquiere el slot; desde Herdr libera el arriendo |
| `openSpace(id)` | Abre el space indicado dentro del slot arrendado |
| `focusPane(id)` | Enfoca o recrea la ventana del pane |
| `release()` | Libera el slot y restaura el workspace original |
| `status()` | Devuelve conexión, preparación y estado del arriendo |
| `reconcile()` | Fuerza snapshot y reconciliación para diagnóstico |

El repositorio no incluye scripts de instalación con privilegios. Omarchy lo instala dentro de su directorio de plugins mediante sus comandos estándar.

## Configuración de Hyprland

La instalación documentará un único override en la configuración personal:

```lua
hl.unbind("SUPER + CTRL + RETURN")
o.bind(
  "SUPER + CTRL + RETURN",
  "Hypr Herdr",
  "omarchy-shell guillermodsm.hypr-herdr openLast"
)
```

No se modificarán `SUPER+1..9`, el widget estándar ni archivos bajo `/usr/share/omarchy/`. El plugin tampoco añadirá reglas globales si puede aplicar el destino al lanzar cada terminal.

## Dependencias

- Omarchy con plugins schema version 1.
- Quickshell con `Quickshell.Io.Socket` y `Quickshell.Hyprland`.
- Hyprland 0.56 o compatible con dispatchers Lua y `hl.dsp.workspace.change_id`.
- Herdr 0.8.2 o una versión compatible con protocolo 20.
- `xdg-terminal-exec` y `uwsm-app`.

El plugin debe detectar capacidades antes de iniciar un arriendo. Si `change_id` o el protocolo de Herdr no son compatibles, muestra el error y no modifica workspaces ni ventanas.

## Alcance de la primera versión

### Incluido

- Un arriendo global asociado a un slot numérico.
- Home IDs internos positivos para spaces Herdr.
- Aparcado y restauración del workspace original.
- Recuperación después de recargar `omarchy-shell`.
- Sidebar persistente en el space Herdr activo.
- Spaces, tabs, panes y estados de agentes desde el socket de Herdr.
- Una terminal `direct attach` por pane.
- Cambio inmediato entre spaces sin mover ventanas.
- Foco y recreación de panes.
- Integración con tema, barra, bindings y shell IPC nativos de Omarchy.
- Soporte para el terminal elegido mediante `xdg-terminal-exec`.

### Fuera de alcance

- Reutilizar o modificar el sidebar TUI de Herdr.
- Modificar el código de Herdr, Hyprland u Omarchy.
- Reemplazar la barra de workspaces o los bindings numéricos.
- Plugin binario de Hyprland.
- Plugin o workflow de Herdr.
- Replicar el layout interno de Herdr.
- Mover todas las ventanas de un space a otro workspace.
- Registrar aplicaciones GUI como panes de Herdr.
- Restaurar geometría después de cerrar manualmente una ventana.
- Un arriendo simultáneo por monitor.
- Administrar recursos, hibernar agentes o limitar memoria.
- Sincronizar sesiones remotas en la primera versión.

## Casos de error

- **Hyprland sin `change_id`:** bloquear leasing antes de cualquier mutación y mostrar la versión requerida.
- **Slot ocupado durante la transacción:** abortar sin sobrescribir el workspace existente y reconciliar.
- **ID interno en colisión:** elegir otro ID libre antes de iniciar la transacción.
- **Transacción parcial:** bloquear nuevos arriendos y ofrecer `release()` o recuperación de emergencia.
- **Recarga de Omarchy:** reconstruir el arriendo desde nombres e IDs y adoptar las ventanas existentes.
- **Plugin deshabilitado con un arriendo activo:** requerir liberación previa y documentar recuperación externa.
- **Herdr no está ejecutándose:** conservar el arriendo existente, mostrar estado desconectado y permitir liberarlo.
- **Pane sin `terminal_id`:** mostrarlo deshabilitado hasta recibir una actualización válida.
- **Propietario directo existente:** usar `--takeover` solo para la ventana única administrada por Hypr Herdr.
- **Terminal termina al iniciar:** conservar el pane en el sidebar y ofrecer reintento.
- **Space o pane cambia de ID:** reconciliar por IDs opacos devueltos por el snapshot.
- **Evento perdido:** `reconcile()` solicita un snapshot completo y corrige diferencias.

## Criterios de aceptación

1. `omarchy plugin add <repo> --enable --yes` instala y habilita el plugin sin copiar archivos manualmente.
2. `SUPER+CTRL+RETURN` arrienda el workspace numérico actual al último space Herdr preparado.
3. La barra estándar marca ese mismo número mientras Herdr está activo.
4. `SUPER+N` vuelve directamente a Herdr cuando Herdr posee el slot `N`.
5. Los bindings numéricos y el widget estándar no son reemplazados ni interceptados.
6. El sidebar aparece solo cuando el workspace enfocado tiene identidad `herdr:*`.
7. Cambiar de space no crea procesos ni mueve ventanas.
8. Cada space recupera el mismo layout, proporciones y ventanas al volver.
9. `release()` restaura el ID y nombre del workspace original.
10. Reiniciar `omarchy-shell` adopta o recupera un arriendo sin duplicar ventanas.
11. Una transacción parcial produce un estado diagnosticable y recuperable, no pérdida de workspaces.
12. Cada pane tiene como máximo una terminal adjunta.
13. Cerrar una terminal no cierra el pane ni el agente en Herdr.
14. Crear, cerrar, mover o renombrar elementos en Herdr actualiza el sidebar sin polling.
15. El plugin funciona con el terminal configurado por `xdg-terminal-exec`.
16. La configuración y el código no modifican `/usr/share/omarchy/`.

## Spike obligatorio

Workspace Slot Leasing no se considera validado hasta completar un spike aislado que demuestre:

**Resultado:** completado con GO para vacíos desechables. Ver [SLOT_LEASING_SPIKE.md](SLOT_LEASING_SPIKE.md).

1. `change_id` conserva ventanas, layout, grupos, fullscreen y nombres renombrados.
2. Aparcar, arrendar y enfocar produce una sola transición visible.
3. Cambiar el space propietario del slot no muestra estados intermedios.
4. `SUPER+1..9` y la barra estándar funcionan sin personalización adicional.
5. La navegación relativa como `e+1` o `SUPER+TAB` no expone de forma perjudicial los IDs internos altos.
6. Las reglas de Hyprland dirigidas a números tienen un comportamiento aceptable y documentado.
7. Reiniciar `omarchy-shell` durante un arriendo permite adopción o recuperación.
8. Interrumpir cada paso de la transacción deja un estado recuperable.
9. El procedimiento de emergencia restaura el workspace original sin cargar el panel.
10. El comportamiento en uno y varios monitores es conocido.
11. Un workspace original vacío no desaparece de forma que impida liberar el arriendo correctamente.

Si falla la atomicidad visual o la recuperación segura, la alternativa será un router explícito de navegación y un widget de workspaces propio. No se implementará redirección posterior al foco por su riesgo de flicker y carreras.

## Validación funcional

Además del spike, la implementación se probará con:

- Un space con un pane.
- Varios spaces con múltiples panes y tabs.
- Agentes en estados `working`, `blocked`, `idle`, `done` y `unknown`.
- Ventanas tiled, flotantes, agrupadas y fullscreen.
- Cierre y recreación de una terminal adjunta.
- Creación y cierre de panes mientras su workspace no está visible.
- Cambio rápido y repetido entre spaces.
- Liberación desde el slot y desde otro workspace.
- Migración del portal a otro slot numérico.
- Reinicio de Herdr y de `omarchy-shell`.
- Kitty, Alacritty, Foot o Ghostty cuando estén disponibles.
- Uno y varios monitores.

## Decisiones cerradas

- Cada space, no cada pane, corresponde a un workspace completo de Hyprland.
- Los panes son ventanas dentro del workspace del space.
- Hyprland define y conserva la geometría.
- El sidebar se implementa en Omarchy y usa el estado real de Herdr.
- La sincronización usa sockets y eventos, no polling.
- La integración usa un plugin oficial de Omarchy sin extensiones nativas adicionales.
- Los workspaces vacíos son desechables y se recrean desde metadata leased.
- El plugin permanece habilitado durante el uso normal: `openLast`/`release` son los gestos de abrir y cerrar, y `enable`/`disable` quedan reservados a la instalación.
- Workspace Slot Leasing queda habilitado por el spike.
