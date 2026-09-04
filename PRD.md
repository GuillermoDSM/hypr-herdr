# Hypr Herdr

## Resumen

Hypr Herdr integra los spaces y panes de Herdr con el escritorio de Omarchy sin modificar Herdr ni Hyprland. Cada space de Herdr corresponde a un workspace nombrado de Hyprland. Cada pane se presenta como una terminal conectada a su PTY real mediante `herdr terminal attach`.

Un sidebar nativo de Omarchy permite cambiar de space, inspeccionar panes y ver el estado de los agentes. El sidebar permanece en la misma posición al cambiar entre workspaces de Herdr. Hyprland conserva el layout, tamaño y posición de las ventanas; Herdr conserva procesos, sesiones y agentes.

## Objetivo

Convertir Herdr en una capa de sesión y navegación integrada con Omarchy:

- Herdr administra spaces, tabs, panes, PTY, agentes y persistencia.
- Hyprland administra workspaces, ventanas, foco y geometría.
- Omarchy presenta el sidebar y coordina ambos sistemas.

El cambio entre spaces debe sentirse como cambiar el contenido de una misma superficie. No debe crear procesos, mover ventanas ni reconstruir layouts durante la interacción.

## Principios

1. **Usar APIs públicas.** La integración usa el socket de Herdr, los dispatchers de Hyprland y el contrato de plugins de Omarchy.
2. **Mantener una sola fuente de verdad por dominio.** Herdr controla sesiones; Hyprland controla geometría; el plugin no duplica ninguno de esos estados.
3. **Evitar infraestructura innecesaria.** No habrá plugin binario de Hyprland, plugin de Herdr ni daemon independiente.
4. **Preparar antes de mostrar.** Las terminales permanecen abiertas en sus workspaces para que cambiar de space requiera un solo dispatcher.
5. **Respetar Omarchy.** El plugin usa el tema, componentes, IPC, hot reload e instalación estándar de Omarchy.

## Arquitectura

```text
Herdr server
  ├── space w1 ───────── Hyprland workspace name:herdr:dzE
  │   ├── pane w1:p1 ─── terminal window + direct attach
  │   └── pane w1:p2 ─── terminal window + direct attach
  └── space wB ───────── Hyprland workspace name:herdr:d0I
      ├── pane wB:p1 ─── terminal window + direct attach
      └── pane wB:p2 ─── terminal window + direct attach

Omarchy shell
  └── Hypr Herdr panel ── sidebar layer-shell + event coordinator
```

### Mapeo

| Herdr | Omarchy/Hyprland |
|---|---|
| Workspace o space | Workspace nombrado `herdr:<base64url(workspace_id)>` |
| Tab | Agrupación visual dentro del sidebar |
| Pane | Ventana terminal con un `app-id` estable |
| Terminal ID | Destino de `herdr terminal attach` |
| Agent status | Estado y color del pane en el sidebar |
| Layout de panes | Layout nativo del workspace en Hyprland |

Los IDs de Herdr se tratarán como valores opacos. Una función reversible y segura para nombres de Hyprland y `app-id` codificará los IDs; el código no extraerá significado de prefijos como `w` o `p`.

### Workspaces

Los workspaces de Herdr serán workspaces nombrados normales, no special workspaces. El widget estándar de Omarchy muestra workspaces numéricos positivos, por lo que los workspaces nombrados de Herdr no aparecerán en esa lista.

El workspace numérico desde el cual el usuario entra a Herdr permanece intacto. Hyprland cambia al último workspace Herdr visitado y permite regresar mediante su navegación normal.

Hypr Herdr nunca trasladará el conjunto de ventanas de un space hacia un workspace numérico. Mover ventanas obligaría a Hyprland a reinsertarlas en el layout y podría alterar orden, proporciones y geometría.

### Sidebar

El sidebar será una superficie `PanelWindow` de Quickshell con layer-shell:

- Se muestra en workspaces cuyo nombre pertenece a Hypr Herdr.
- Se oculta en workspaces numéricos, especiales o ajenos al plugin.
- Reserva un ancho constante mediante su zona exclusiva.
- No forma parte del árbol de ventanas de Hyprland.
- Conserva posición y apariencia durante el cambio de space.
- Usa `Color`, `Style` y componentes compartidos de Omarchy.

La primera versión crea un sidebar nuevo. El sidebar original de Herdr forma parte de su TUI y no tiene una interfaz pública para incrustarlo en Quickshell.

## Experiencia de usuario

### Entrada

`SUPER+CTRL+RETURN`, hoy asignado a abrir la TUI completa de Herdr, invoca el método IPC `openLast` del plugin.

1. El plugin identifica el último space Herdr visitado.
2. Hyprland enfoca su workspace nombrado.
3. El sidebar aparece en el siguiente frame.
4. Las ventanas del space ya están abiertas y conservan su layout.

Si Herdr no tiene spaces, el sidebar muestra un estado vacío y una acción para abrir Herdr o crear el primer space, según lo que permita la API pública instalada.

### Cambio de space

Al seleccionar un space:

1. El plugin actualiza la selección local.
2. Activa el workspace `name:herdr:<base64url(workspace_id)>` mediante la API de Quickshell.
3. Hyprland muestra el workspace existente.
4. El sidebar actualiza el resaltado desde el evento de foco de Hyprland.

El camino interactivo no consulta disco, no lanza terminales y no mueve ventanas.

### Panes

Cada fila de pane muestra:

- Título del agente o terminal.
- Directorio, cuando aporte contexto.
- Estado `working`, `blocked`, `idle`, `done` o `unknown`.
- Indicador de ventana conectada.
- Tab de origen cuando el space tenga más de un tab.

Seleccionar un pane enfoca su ventana dentro del workspace actual. Si la ventana se cerró, el plugin la recrea y ejecuta:

```sh
herdr terminal attach <terminal_id> --takeover
```

Cerrar la ventana desmonta la vista, pero no cierra el pane ni el proceso administrado por Herdr. Una ventana recreada vuelve al layout como una ventana nueva; la primera versión no intenta restaurar su antigua posición después de un cierre manual.

### Aplicaciones GUI

El usuario puede abrir aplicaciones GUI en un workspace Herdr. Hyprland las administra como cualquier otra ventana y conserva su relación con ese workspace. Hypr Herdr no intenta registrar esas aplicaciones dentro de Herdr.

## Sincronización

### Conexión con Herdr

El panel usa `Quickshell.Io.Socket` para conectarse al socket Unix publicado por Herdr. Al conectar:

1. Abre `events.subscribe` y comienza a almacenar invalidaciones.
2. Solicita `session.snapshot` mediante una segunda conexión.
3. Construye el modelo de spaces, tabs, panes y agentes.
4. Aplica las invalidaciones recibidas solicitando un snapshot autoritativo.
5. Reconcilia las terminales esperadas con las ventanas existentes.

La suscripción incluye los eventos necesarios para creación, cierre, movimiento, cambio de nombre, foco y estado de agente. El plugin actualiza el modelo con cada evento. No ejecuta polling mientras el socket funcione.

Si el socket se desconecta, el sidebar conserva el último estado, muestra que Herdr está desconectado e intenta reconectar con espera progresiva limitada. Tras reconectar solicita un snapshot completo antes de procesar eventos nuevos.

### Conexión con Hyprland

El panel usa `Quickshell.Hyprland` para observar:

- Workspace enfocado.
- Workspaces existentes.
- Ventanas de cada workspace.
- Clase o `app-id` de las terminales adjuntas.

Usa dispatchers de Hyprland para enfocar workspaces y ventanas. El plugin no usa `hyprctl` para polling.

### Reconciliación de terminales

Cada pane vivo debe tener como máximo una ventana `direct attach`.

- Al iniciar, el plugin crea en segundo plano las ventanas faltantes.
- Al recibir `pane.created`, crea la ventana en el workspace de su space.
- Al recibir `pane.closed`, cierra únicamente la ventana que representa ese pane.
- Al recibir `pane.moved`, mueve o recrea la ventana en el workspace de destino.
- Antes de crear una ventana, comprueba su `app-id` para evitar duplicados.

El plugin lanza la terminal configurada por el usuario mediante `xdg-terminal-exec --app-id`, dentro de la sesión gráfica con `uwsm-app`. No asume Kitty, Alacritty, Foot ni Ghostty.

## Rendimiento

### Metas

- Cambio entre spaces: una operación IPC de Hyprland y presentación en el siguiente frame.
- Respuesta visual del sidebar: menos de 16 ms desde el evento recibido.
- Ningún proceso nuevo durante un cambio entre spaces ya preparados.
- Ningún temporizador de polling en estado conectado.
- Sin escrituras a disco durante la navegación.

### Estrategia

El plugin mantiene una terminal adjunta por pane para eliminar el coste de lanzamiento al cambiar de space. Hyprland conserva las ventanas de workspaces no visibles sin renderizarlas como contenido activo.

El arranque puede abrir varias terminales. El reconciliador limita la concurrencia para no bloquear `omarchy-shell`, pero completa la preparación antes de considerar cada space listo. El sidebar distingue entre `preparing` y `ready`.

## Plugin de Omarchy

El repositorio seguirá el contrato oficial para plugins de terceros:

```text
hypr-herdr/
├── manifest.json
├── Panel.qml
├── HerdrClient.qml
├── IdCodec.js
├── README.md
├── PRD.md
├── LICENSE
└── tests/
```

El manifiesto previsto:

```json
{
  "schemaVersion": 1,
  "id": "guillermodsm.hypr-herdr",
  "name": "Hypr Herdr",
  "version": "0.1.0",
  "author": "guillermodsm",
  "description": "Herdr spaces as native Omarchy workspaces.",
  "kinds": ["panel"],
  "keepLoaded": true,
  "entryPoints": {
    "panel": "Panel.qml"
  }
}
```

`keepLoaded` mantiene la conexión de eventos y el layer-shell disponibles dentro del proceso existente de `omarchy-shell`. El plugin registra un `IpcHandler` propio con estos métodos:

| Método | Resultado |
|---|---|
| `openLast()` | Entra al último space visitado |
| `openSpace(id)` | Entra al space indicado |
| `focusPane(id)` | Enfoca o recrea la ventana del pane |
| `status()` | Devuelve estado de conexión y preparación |
| `reconcile()` | Fuerza snapshot y reconciliación para diagnóstico |

El repositorio no incluye scripts de instalación con privilegios. Omarchy clonará el repositorio dentro de `~/.config/omarchy/plugins/<plugin-id>/`, validará `manifest.json` y habilitará el plugin mediante sus comandos estándar.

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

No se modificarán archivos bajo `/usr/share/omarchy/`. El plugin tampoco añadirá reglas globales de workspace o ventana si puede aplicar el destino al lanzar cada terminal.

## Dependencias

- Omarchy con plugins schema version 1.
- Quickshell con `Quickshell.Io.Socket` y `Quickshell.Hyprland`.
- Hyprland 0.56 o compatible con workspaces nombrados y dispatchers Lua.
- Herdr 0.8.2 o una versión compatible con protocolo 20.
- `xdg-terminal-exec` y `uwsm-app`.

El plugin debe detectar versiones y capacidades al conectar. Si el protocolo de Herdr no es compatible, muestra el error y no modifica workspaces ni ventanas.

## Alcance de la primera versión

### Incluido

- Sidebar persistente en workspaces Herdr.
- Spaces, tabs y panes desde el socket de Herdr.
- Estados de agentes en vivo.
- Un workspace nombrado por space.
- Una terminal `direct attach` por pane.
- Cambio inmediato entre spaces.
- Foco y recreación de panes.
- Reconexión después de reiniciar Herdr.
- Integración con el tema y shell IPC de Omarchy.
- Soporte para el terminal elegido mediante `xdg-terminal-exec`.

### Fuera de alcance

- Reutilizar o modificar el sidebar TUI de Herdr.
- Modificar el código de Herdr, Hyprland u Omarchy.
- Plugin binario de Hyprland.
- Plugin o workflow de Herdr.
- Replicar el layout interno de Herdr.
- Mover todas las ventanas hacia un workspace numérico.
- Registrar aplicaciones GUI como panes de Herdr.
- Restaurar geometría después de cerrar manualmente una ventana.
- Administrar recursos, hibernar agentes o limitar memoria.
- Sincronizar sesiones remotas en la primera versión.

## Casos de error

- **Herdr no está ejecutándose:** mostrar estado desconectado y una acción explícita para iniciarlo.
- **Pane sin `terminal_id`:** mostrarlo deshabilitado hasta recibir una actualización válida.
- **Propietario directo existente:** usar `--takeover` solo para la ventana única administrada por Hypr Herdr.
- **Terminal termina al iniciar:** conservar el pane en el sidebar y ofrecer reintento.
- **Workspace o pane cambia de ID:** reconciliar por los IDs devueltos por el snapshot, sin inferir relaciones por el nombre.
- **Omarchy recarga el plugin:** recuperar el modelo desde snapshot y adoptar ventanas existentes por `app-id`.
- **Evento perdido:** `reconcile()` solicita un snapshot completo y corrige diferencias.

## Criterios de aceptación

1. `omarchy plugin add <repo> --enable --yes` instala y habilita el plugin sin copiar archivos manualmente.
2. `SUPER+CTRL+RETURN` entra al último space Herdr preparado.
3. Los workspaces Herdr no aparecen entre los workspaces numéricos de la barra estándar.
4. El sidebar aparece solo en workspaces administrados por Hypr Herdr.
5. Cambiar de space no crea procesos ni mueve ventanas.
6. Cada space recupera el mismo layout, proporciones y ventanas al volver.
7. Cada pane tiene como máximo una terminal adjunta.
8. Cerrar una terminal no cierra el pane ni el agente en Herdr.
9. Volver a seleccionar un pane cerrado recrea su terminal.
10. Crear, cerrar, mover o renombrar elementos en Herdr actualiza el sidebar sin polling.
11. Los cambios de estado de un agente aparecen sin refresco manual.
12. Reiniciar `omarchy-shell` adopta las ventanas existentes sin duplicarlas.
13. Desconectar y reiniciar Herdr produce un estado comprensible y una recuperación automática.
14. El plugin funciona con el terminal configurado por `xdg-terminal-exec`.
15. La configuración y el código del plugin no modifican `/usr/share/omarchy/`.

## Validación

La implementación se probará con:

- Un space con un pane.
- Varios spaces con múltiples panes.
- Más de un tab por space.
- Agentes en estados `working`, `blocked`, `idle`, `done` y `unknown`.
- Ventanas tiled, flotantes, agrupadas y fullscreen.
- Cierre y recreación de una terminal adjunta.
- Creación y cierre de panes mientras su workspace no está visible.
- Reinicio de Herdr y de `omarchy-shell`.
- Cambio rápido y repetido entre spaces.
- Terminales Kitty, Alacritty, Foot o Ghostty cuando estén disponibles.
- Uno y varios monitores.

## Decisiones cerradas

- Cada space, no cada pane, corresponde a un workspace de Hyprland.
- Los panes son ventanas dentro del workspace del space.
- El usuario cambia de workspace; el plugin no transporta ventanas hacia el workspace de entrada.
- Hyprland define y conserva la geometría.
- El sidebar se implementa en Omarchy y usa el estado real de Herdr.
- La sincronización usa sockets y eventos, no polling.
- La integración usa un plugin oficial de Omarchy sin extensiones nativas adicionales.
