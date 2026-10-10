# Renderizado custom bajo demanda (R0–R2)

El renderer custom reconstruye la ventana sólo cuando hay una invalidación o
trabajo visual temporal. Conserva el build declarativo completo y el árbol
retenido; no hay una política de renderizado configurable. En Metal también
omite el dibujo en reposo. En los caminos
GL/EGL/D3D vuelve a pintar el árbol conservado por el contrato de presentación
de Sokol, explicado abajo. No agrega signals, reconciliación incremental, IME
ni otra unidad de tipografía.

```v
ui2.run_window('Mi app', 800, 600, build)
```

El renderizado bajo demanda pertenece al renderer custom. Los backends nativos
conservan sus contratos de actualización. Para usar el custom en macOS/Windows, compilar con
`-d ui2_custom_rendering`; Linux y Android ya lo usan por defecto.

## Migración y propiedad del estado

Las acciones y bindings de los runners VML solicitan refresh después de
actualizar el modelo. Código que modifica el modelo por otra vía debe llamar a `refresh()` o `request_refresh()`. Leer el reloj, archivos
o variables externas dentro de `build` no suscribe la vista a sus cambios.
Usar deadlines o timers para cambios periódicos y solicitar actualización
cuando vence cada plazo. Una lectura dentro de `build` por sí sola no despierta
la ventana.

En el custom, ambas funciones invalidan una próxima presentación; no ejecutan
un build recursivo. Se agrupan las solicitudes anteriores al mismo flush. Una
solicitud emitida desde `build`, desde una animación o durante el flush conserva
su generación y provoca un flush posterior. `refresh_element` es una
invalidación amplia en este backend, no una API de actualización incremental.

El hilo de UI posee el modelo y los controles. Un worker recibe un dispatcher
capturado **en el hilo de UI, después de iniciar la ventana**, por ejemplo en el
primer build. El worker sólo encola el trabajo:

```v
fn load(dispatcher ui2.UiDispatcher) {
    result := read_data()
    accepted := dispatcher.post(fn [result] () {
        // Aplicar result al modelo aquí: este callback corre en el hilo UI.
        apply_result(result)
    })
    if !accepted {
        // La ventana ya se cerró; liberar recursos propios si corresponde.
        return
    }
}
```

`post` es seguro entre hilos y solicita actualización. No ejecutar mutadores de
controles, modificar el modelo compartido ni tocar `gg.Context` desde el worker.
Las tareas pendientes pertenecen al lifetime de la ventana; el dispatcher de
una ventana cerrada rechaza trabajo. No consultar de nuevo `ui_dispatcher()`
desde un worker para buscar una ventana que podría haber sido reemplazada.

## Inventario de invalidaciones

| Origen | Trabajo requerido | Verificación |
| --- | --- | --- |
| Primer montaje | Build y pintura completa | Primer frame visible |
| Resize, escala/DPI, restauración de superficie | Build y pintura completa con tamaño actual | Resize y restauración sin zonas vacías |
| `refresh`, `request_refresh`, `refresh_element` | Invalidación amplia, agrupada por generación | Ráfaga y solicitud dentro de build |
| Binding/acción VML | Efectos por propiedad y reconciliación por key, conservando nodos y scopes | Counter doble, contratos, listas anidadas y lifecycle |
| Worker | Encolar callback, aplicarlo en UI e invalidar | Cambio visible sin mover el mouse |
| Hover, press, drag, scroll, dropdown y menú | Conservar interacción y actualizar imagen | Ejemplos y tests de captura/scroll |
| Texto, selección, foco y mutadores de controles | Mantener estado local y actualizar imagen | Edición conservada tras refresh ajeno |
| Tooltip | Deadline de 500 ms ligado al target actual | Aparece con el mouse quieto; se cancela al salir |
| Long press | Deadline mientras la pulsación siga siendo válida | Se dispara sin movimiento; cancelación libera captura |
| Animación | Frames durante actividad visible y un frame terminal | Completa, publica estado final y vuelve al reposo |
| Ventana iconificada/suspendida | Suspender trabajo visual; conservar invalidaciones | Sin builds/draws ocultos; restauración completa |
| Cierre | Invalidar dispatcher y cancelar tareas pendientes | Un callback tardío no usa la ventana anterior |

El renderer no tiene todavía composición IME ni cursor parpadeante temporal.
El control `Spinner` actual es un selector de opciones, no un indicador de carga
giratorio. Estas funciones no se anuncian como nuevas fuentes de frames.

## Contadores y alcance de la entrega

`render_stats()` devuelve los contadores del contexto actual. Un dispatcher
retenido permite consultarlos desde un worker mediante `dispatcher.stats()` sin
encolar un callback ni invalidar la escena. Las mediciones deben usar deltas
entre snapshots; leer contadores no equivale a medir consumo de CPU o energía.

| Contador | Qué cuenta |
| --- | --- |
| `callbacks` | Intentos de comenzar un frame del scheduler, después de la espera Linux |
| `loop_callbacks` | Entradas al callback UI2 antes de esperar |
| `waits`, `event_wakeups`, `worker_wakeups`, `deadline_wakeups` | Esperas Linux completadas y sus causas; ver la guía Linux |
| `builds` | Ejecuciones de la función declarativa de construcción |
| `draws` | Presentaciones completas emitidas por el renderer |
| `flushes` | Ciclos de presentación completados |
| `requests` | Solicitudes de invalidación |
| `coalesced` | Solicitudes agrupadas cuando ya había trabajo pendiente |
| `presentation_required` | La superficie exige volver a pintar en cada callback, aunque no haya build |

En GL/EGL/D3D el loop de Sokol intercambia o descarta buffers cuando retorna el
callback. Reutilizar el contenido anterior no es seguro: cada callback visible
que retorna pinta el árbol completo, con `presentation_required = true`. Metal
puede omitir el dibujo sin ese requisito. Linux bloquea dentro del callback
antes de dibujar hasta recibir un evento, una tarea o un deadline; durante la
espera tampoco hay intercambio de buffers. La medición distingue este reposo
de una omisión de trabajo que siga retornando a cada intervalo.

Linux completa la espera de eventos/deadlines con el host X11 existente:
[contrato, API y medición](linux-idle-wait.md). Un callback en reposo bloquea
antes de dibujar; cada callback visible que retorna sigue repintando GL completo.
Workers despiertan mediante `eventfd` y sus callbacks se entregan en UI. No se
consume entrada desde el worker ni se modifica `gg.refresh_ui`.

Los demás caminos gg/Sokol mantienen su cadencia de plataforma. Metal omite
trabajo, pero no demuestra suspensión del loop; el embedder macOS propio sí
implementa espera. `gg.ui_mode` sigue desactivado para conservar entrega de tareas,
deadlines e invalidaciones reentrantes.

## Reproducción de aceptación

Compilar y ejecutar la escena bajo demanda con el GC normal. Dejar la ventana
visible, el mouse quieto fuera de sus controles y no escribir durante el intervalo estático:

```sh
v -d ui2_custom_rendering -o /tmp/ui2-render-scheduler tests/render_scheduler
/usr/bin/time -l /tmp/ui2-render-scheduler --seconds 30
```

En macOS, agregar `--lifecycle` prueba también la ventana real: un helper
del fixture usa el handle público de Sokol para iconificarla desde el hilo UI
y restaurarla mediante un timer de la cola principal nativa. El worker sólo
observa contadores; no opera la ventana. Se exige suspensión, ausencia de
builds/draws mientras está iconificada, una construcción y pintura completas
al restaurar y el retorno al reposo. En otras plataformas se informa `SKIP`
para esta fase adicional.

```sh
/tmp/ui2-render-scheduler --seconds 2 --lifecycle
```

El fixture espera dos segundos de estabilización, mide treinta segundos sin
actividad, prueba un worker, una ráfaga de veinte refresh, una invalidación
dentro de build y una animación. Comprueba los deltas según la capacidad de la
superficie, la finalización, que un cambio del modelo dentro del callback de
finalización se construya sin refresh explícito, el retorno al reposo y el
rechazo de callbacks inmediatamente después de cerrar el coordinador.
`--seconds 2` sirve para iterar, pero no reemplaza la prueba
decisiva de treinta segundos. `/usr/bin/time` cubre también calentamiento y
actividad; no presentar su CPU total como CPU exclusiva del intervalo estático.

Para completar los escenarios que necesitan eventos de plataforma:

```sh
/tmp/ui2-render-scheduler --interactive
```

El modo interactivo imprime contadores y el estado `suspended` cada segundo
sin invalidar la ventana; esto permite distinguir captura de una superficie
retenida de una restauración efectiva.

1. Dejar el puntero sobre el estado: el tooltip aparece después de 500 ms sin
   movimientos adicionales y desaparece al salir o hacer clic.
2. Escribir y seleccionar texto; pulsar Refresh o Worker. El texto local se
   conserva. Desplazar la lista y verificar que un refresh conserve el offset.
3. Pulsar Animate; observar el último estado y luego el reposo. Repetir con la
   ventana iconificada y restaurarla; comprobar contenido completo y estado
   final coherente. Cambiar el tamaño y comprobar el nuevo viewport.
4. Cerrar durante la espera del worker; no debe ejecutarse trabajo sobre el
   contexto cerrado. La aceptación automatizada del coordinador cubre además
   callbacks rechazados y generaciones pendientes durante suspensión.

Para capturas de los ejemplos se conserva `make screenshot EXAMPLE=<nombre>`.
En macOS ese mecanismo usa GL por la limitación del recorder de gg; una captura
GL no verifica por sí sola la superficie Metal predeterminada.

Registrar versión de UI2/V, SO, SDK, backend GPU, flags, GC, duración y deltas.
Reportar por separado pruebas GPU reales, tests sin superficie y sólo compilación
de otras plataformas. El problema Boehm `Too many root sets` observado en macOS
27 se sigue en V-001; `-gc none` puede aislar el scheduler durante diagnóstico,
pero no es una solución de producción ni prueba de aceptación con GC normal.

## Medición histórica en macOS (2026-09-29)

MacBook Air Apple M4, macOS 27.0 (`26A428`), SDK 27.0, Apple clang 21.0.0;
V 0.5.2 `3005dc3`, Metal predeterminado, GC predeterminado. Mismo binario
compilado con `v -d ui2_custom_rendering`, ventana de 640 × 480, dos segundos
de calentamiento y treinta segundos estáticos. No hubo interacción durante
los intervalos. Esta comparación histórica se realizó cuando existían ambas
políticas. La política continua y su configuración fueron eliminadas; el fixture
actual sólo verifica el renderizado bajo demanda.

| Intervalo estático histórico, 30 s | `continuous` (eliminado) | `on_demand` |
| --- | ---: | ---: |
| Callbacks | 1.705 | 1.704 |
| Builds | 1.705 | 0 |
| Draws | 1.705 | 0 |
| Solicitudes | 0 | 0 |

En `on_demand`, la entrega del worker con veinte solicitudes acumuladas y otra
emitida dentro de build produjo exactamente dos builds/draws; veinte solicitudes
se agruparon. La animación y el cambio del modelo en su callback de finalización
produjeron 48 builds/draws. En el segundo posterior se midieron 57 callbacks y
cero builds/draws. El cierre rechazó correctamente un callback tardío del worker.

`/usr/bin/time -l` midió el proceso completo, incluida inicialización, el intervalo
estático y las pruebas de actividad: continuo 35,62 s reales, 3,34 s CPU usuario
y 0,99 s sistema; bajo demanda 35,26 s reales, 0,36 s usuario y 0,17 s sistema.
El RSS máximo fue 224.722.944 y 157.040.640 bytes respectivamente. Es una muestra
de aceptación en este host, con otras aplicaciones abiertas: no es un benchmark
estadístico, no aísla CPU en reposo y no mide energía ni despertares del SO.

Ambos procesos terminaron correctamente con GC normal. Esto verifica este
camino custom; no cierra V-001 ni demuestra que el problema del backend AppKit
esté resuelto.

La inspección visual de la ventana Metal comprobó texto inicial, tooltip con
puntero detenido, edición y selección conservadas tras Worker/Refresh, scroll
conservado, posición final de animación y resize. La inspección encontró un
problema que el modo continuo ocultaba: el atlas de glifos se enviaba a la GPU
en el siguiente frame y el texto nuevo podía quedar invisible indefinidamente.
El renderer ahora vacía el atlas después de emitir texto y antes de dibujar;
se volvió a comprobar la primera aparición del tooltip con texto visible.

La automatización por puntero no logró iconificar la ventana porque la
superposición de compartir ventana de macOS interceptaba el control. Se verificó
la iconificación/restauración real con el helper nativo de `--lifecycle`, con GC
normal: durante 500 ms iconificada, 28 callbacks y cero builds/draws; al restaurar,
una construcción y una pintura completas; tras estabilizarse, otros 500 ms con
29 callbacks y cero builds/draws. La suite determinista del coordinador cubre
además conservación del trabajo, cierre y rechazo del dispatcher anterior.
No se ejecutó esta prueba de lifecycle en otros sistemas operativos.

La misma aceptación en GL, compilada con `-d darwin_sokol_glcore33`, pasó con
GC normal y `presentation_required = true`: dos segundos estáticos dieron
115 callbacks, cero builds y 114 draws. Tras la animación, otro segundo dio
57 callbacks, cero builds y 57 draws. Confirma que el fallback conserva el
beneficio de construcción sin afirmar cero presentaciones en GL.

Verificación adicional:

- `make check-backends`: todos los chequeos de plataformas compilables pasan;
  esto no equivale a ejecución en cada plataforma.
- Núcleo del scheduler: once tests pasan; seis pruebas de integración se
  volvieron a ejecutar después de los últimos cambios de lifetime y pasan.
  Las pruebas de animaciones pasan en nativo y custom.
- Tests custom de controles, tooltip, scroll y captura de puntero, más los de
  modelo VML, VML compilado e imports: pasan.
- `make screenshot EXAMPLE=message`: captura GPU GL generada e inspeccionada.
- Ejemplos `users`, `message`, `dropdown`, `toggle_button` y `switch`: compilados
  en nativo y custom. `transitions`, `slider_textbox`, `scrollview` y
  `text_input`: compilados en custom.
- `make test`: tras repetir secuencialmente los tests afectados por ediciones
  concurrentes, 124 pasan, dos se omiten y diez fallos se reproducen también en
  la base `76d2f7c`. Corresponden a tests de AppKit, slider, text editor, guards
  nativo/custom, captura de puntero, scroll, tooltip, igualdad VML adaptativa y
  de menú, y el ejemplo de file dialog; no se atribuyen al scheduler.
- `make examples` y `make examples-custom`: el compilador V `3005dc3` rechaza
  la expresión existente `args#[1..].join` en `build_examples.vsh`. Por eso se
  hicieron las compilaciones directas indicadas arriba.
