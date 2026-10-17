# STL Manager

**Versión congelada: v0.5.8.8.1** · **macOS** · **Swift / SwiftUI**

STL Manager es una aplicación nativa para macOS que organiza la entrada de proyectos de impresión 3D, los incorpora a una biblioteca local con una estructura homogénea y permite normalizar proyectos antiguos. Vigila una carpeta configurable (`_Inbox`), muestra los elementos pendientes y simplifica la importación de modelos, fuentes e imágenes de referencia.

> **Origen del proyecto:** aplicación personal desarrollada mediante *vibe coding* (diseño e iteración asistidos por IA), con pruebas funcionales manuales en Xcode. El código merece las mismas revisiones, copias de seguridad y pruebas que cualquier otro software que modifica archivos.
>
> **Alcance:** STL Manager **no** es un slicer ni un visor 3D. La aplicación complementaria **STLViewer** se desarrolla por separado; no está implementada en este repositorio.

## Estado de la versión

- **v0.5.8.8.1 — versión congelada y validada en uso:** añade importación automática opcional a partir de `_Inbox` y corrige advertencias de aislamiento de Swift 6 detectadas durante la integración.
- **v0.5.8.4:** anterior base congelada; se mantiene como referencia en el historial del repositorio.
- **v0.5.8.5–v0.5.8.7:** monitorización en segundo plano, ventana principal única, contador de pendientes en barra de menús y acceso a Ajustes desde la ventana principal.
- **Sin garantía de integridad transaccional completa:** un apagado, cierre forzado o error del sistema de archivos puede interrumpir una operación.
- **Sin copias automáticas de la biblioteca ni suite automatizada completa:** hacer respaldos y probar primero con proyectos pequeños.

## Funcionalidades

### Bandeja `_Inbox`

- Biblioteca y carpeta `_Inbox` configurables desde **Preferencias**, con permisos persistidos mediante *security-scoped bookmarks* de macOS.
- Monitorización periódica configurable: **5, 10, 30 o 60 segundos**; puede pausarse.
- Detección de archivos individuales compatibles, ZIP y carpetas de proyecto.
- Espera de estabilidad del elemento para evitar procesar archivos mientras se están copiando (heurística basada en atributos, no garantía absoluta ante copias pausadas).
- Ventana principal con recuento de pendientes, acciones **Actualizar**, **Normalizar biblioteca**, **Abrir _Inbox en Finder** y acceso a **Ajustes**.
- Notificaciones de sistema para **nuevos** elementos estables, también mientras la aplicación permanece abierta en segundo plano. Al pulsarlas, STL Manager se activa e intenta abrir directamente el asistente de importación del elemento correspondiente.
- Las notificaciones requieren permiso del usuario en los ajustes de macOS. El sistema operativo puede demorar o agrupar su presentación. Los archivos ya presentes al comenzar la vigilancia no se notifican retroactivamente.

### Barra de menús y ventanas

- Icono de estado con **contador de elementos pendientes** en `_Inbox` (el contador desaparece si no hay pendientes).
- Comando para abrir STL Manager que **reutiliza la ventana principal existente**, en lugar de abrir copias de la misma ventana.
- Ajustes accesibles tanto desde el icono de la barra de menús como desde un botón en la ventana principal, compartiendo las mismas preferencias.
- La monitorización continúa con la aplicación abierta aunque la ventana pierda el foco o esté minimizada. **No es un servicio que siga ejecutándose con la app cerrada**.

### Importación de proyectos

- Importación asistida de un fichero, una carpeta completa o un ZIP.
- Nombre del proyecto editable y **URL de origen opcional**.
- Vista previa de la estructura final antes de confirmar, con los ficheros dentro de las carpetas correspondientes.
- Clasificación automática por tipo de fichero; conservación de subdirectorios internos cuando corresponde.
- Generación de `README.md` y `.stlmanager.json`.
- Validación mediante **SHA-256** con lectura por bloques: copia a zona de trabajo, verifica el destino y publica el proyecto; después intenta enviar el elemento original a la Papelera. Si falla el envío a la Papelera, se conserva el origen y se informa del problema.
- No sobrescribe un proyecto existente con el mismo nombre.

**Extensiones del inventario:**

| Destino | Formatos reconocidos |
|---|---|
| `models/` | STL, 3MF, STEP, STP, OBJ, AMF, PLY |
| `sources/` | F3D, SCAD, FCSTD, BLEND, IPT, SLDPRT, SLDASM |
| `images/` | PNG, JPG, JPEG, WEBP, GIF, HEIC |
| `others/` | Otros ficheros conservados por el proyecto |

El detector de la bandeja admite explícitamente `stl`, `step`, `stp`, `3mf`, `zip`, `scad`, `f3d` y `obj`, además de carpetas. **No todos los formatos clasificables se detectan necesariamente como archivos individuales sueltos** en `_Inbox`; pueden incluirse dentro de carpetas/ZIP.

### Importación automática opcional (desde v0.5.8.8)

En **Ajustes → Importación automática** se puede activar la importación sin abrir el asistente. Viene **desactivada por defecto**; existe una opción adicional para mostrar notificaciones de importación completada.

- Revisa los elementos detectados de `_Inbox` y espera a que estén aparentemente estables antes de importarlos. El flujo utiliza comprobaciones de estabilidad en escaneos separados, sin prometer una detección perfecta de descargas pausadas.
- Procesa los proyectos **uno a uno y en segundo plano**, reutilizando el planificador, el extractor ZIP y el importador del modo manual.
- Acepta los mismos elementos admitidos por el monitor: archivos sueltos compatibles, carpetas y ZIP, siempre sujetos a las validaciones existentes.
- Genera la estructura habitual, el `README.md`, el `.stlmanager.json` y los hashes SHA-256; solo tras verificar la copia intenta enviar el origen a la Papelera.
- El nombre del proyecto se deriva del nombre del archivo/carpeta. No inventa URL de origen ni categorías.
- **No sobrescribe proyectos existentes**. Las colisiones o los fallos dejan el elemento pendiente para resolución manual; durante la sesión evita reintentar indefinidamente un contenido fallido sin cambios.
- Puede notificar éxitos; las incidencias quedan reflejadas en el estado de la aplicación y pueden generar aviso si se permiten notificaciones.

**Advertencia:** activar la autoimportación puede provocar el traslado automático de archivos originales a la Papelera tras importar correctamente. Probar con una biblioteca de ensayo y mantener copias de seguridad. La aplicación debe permanecer en ejecución; macOS puede retrasar notificaciones.

### Normalización de proyectos existentes

- Análisis previo que propone reorganizaciones sin ejecutarlas inmediatamente.
- Selección individual o múltiple de proyectos sin conflictos.
- Reorganización hacia las carpetas canónicas inglesas `models/`, `sources/`, `images/` y opcional `others/`.
- Reconocimiento de carpetas históricas (`binarios`, `fuentes`, `imágenes`, `imagenes`, `files` y otras equivalencias), manteniendo los ficheros.
- Conservación de documentación anterior en el README cuando se requiere regenerarlo, con protecciones frente a crecimiento repetitivo.
- Actualización de metadatos e inventario SHA-256; los hashes se calculan **por bloques** para evitar cargar modelos grandes completos en RAM.
- Limpieza de **directorios vacíos solamente**; no se eliminan carpetas con contenido, incluidos ficheros ocultos.
- Cola secuencial de normalización con **ventana de progreso**, registro de operaciones, recuento de éxitos/incidencias y cancelación cooperativa **entre proyectos** (no interrumpe un movimiento individual a mitad de ejecución).
- Control preventivo para carpetas grandes o conflictivas que requieren revisión manual antes de normalizar.

**Precaución:** el normalizador modifica directamente las carpetas elegidas. Aunque intenta revertir movimientos ante algunos errores, el proceso no equivale a una transacción de sistema de archivos. Probar primero con proyectos pequeños respaldados.

### Reglas genéricas de carpetas y colecciones

Cada carpeta de la biblioteca puede configurarse como:

| Modo | Significado |
|---|---|
| **Proyecto gestionado** (`managed`) | Se puede seleccionar para normalización, previa revisión y confirmación |
| **Colección de solo lectura** (`readOnlyCollection`) | El normalizador no reorganiza ni modifica su contenido |
| **Excluida** (`excluded`) | Se omite de las operaciones del normalizador |

Las reglas se pueden establecer desde el asistente de normalización; se aplican por rutas relativas, **no por nombres programados a mano**, y pueden heredarse por subcarpetas. Se comprueban otra vez antes de ejecutar cambios.

Ejemplo de uso: una colección adquirida a un diseñador, con categorías, subcarpetas y ficheros ZIP, puede permanecer **intacta en su ubicación original**, aunque esté dentro de la biblioteca principal. No es obligatorio convertir toda la colección en un único proyecto.

## Estructura de carpetas

Ejemplo con `~/dev/Diseños` como biblioteca (ruta **ilustrativa y configurable**):

```text
~/dev/Diseños/
├── _Inbox/                         # Elementos pendientes de importar
├── .stlmanager/                    # Configuración compartida de la biblioteca
│   └── library.json
├── SoporteImpresora/                # Proyecto gestionado
│   ├── models/
│   │   └── soporte.3mf
│   ├── sources/
│   │   └── soporte.f3d
│   ├── images/
│   │   └── foto.jpg
│   ├── others/                      # Solo si hace falta
│   ├── README.md
│   └── .stlmanager.json             # Metadatos ocultos del proyecto
└── ColeccionComprada/              # Ejemplo: colección protegida
    ├── Coleccion A/
    │   └── Modelo 1/
    └── Coleccion B/
```

**Atención a los puntos iniciales:** `.stlmanager/` y `.stlmanager.json` son elementos ocultos en Finder. Para mostrarlos temporalmente, pulsa **⌘⇧.** (*Command + Shift + punto*).

- `README.md`: descripción legible, fuente de procedencia, inventario y zona de notas.
- `.stlmanager.json`: metadatos específicos del proyecto; se crea dentro de **proyectos gestionados**.
- `.stlmanager/library.json`: políticas compartidas de la biblioteca; se guarda **fuera** de los proyectos y de las colecciones protegidas, para que una protección no requiera escribir dentro de la carpeta protegida.
- Una colección `readOnlyCollection` **no necesita** `.stlmanager.json` en su interior.

### Ejemplo de `.stlmanager.json`

```json
{
  "schema_version": 1,
  "id": "identificador-unico-del-proyecto",
  "title": "SoporteImpresora",
  "source_url": "https://ejemplo.invalid/modelo",
  "categories": [],
  "import_date": "2026-10-17T12:00:00Z",
  "files": [
    {
      "path": "models/soporte.3mf",
      "sha256": "hash-sha256-del-archivo"
    }
  ]
}
```

El ejemplo muestra las claves habituales; algunos proyectos normalizados a partir de versiones antiguas pueden no incluir `import_date`, y `source_url` puede ser `null` o una cadena vacía si se desconoce. **No inventar URLs de procedencia**.

### Ejemplo de `.stlmanager/library.json`

```json
{
  "schema_version": 1,
  "folder_rules": [
    { "path": "ColeccionComprada", "mode": "readOnlyCollection" },
    { "path": "ProyectosAntiguos", "mode": "excluded" }
  ]
}
```

Las rutas son relativas a la raíz de la biblioteca. No editar este fichero mientras STL Manager esté procesando proyectos. Una configuración dañada o con versión no compatible debe corregirse antes de permitir una normalización.

## Requisitos y dependencias

- **macOS** con soporte para la versión de SwiftUI utilizada por el proyecto. La **versión mínima exacta de macOS** es la que figure en *Xcode → STLManager target → General → Minimum Deployments*; no está fijada de manera verificable en esta documentación.
- **Xcode**, probado durante el desarrollo con **Xcode 27** y Swift 6 / SwiftUI. El proyecto utiliza APIs de AppKit, Foundation, Observation, Combine, CryptoKit y UserNotifications disponibles en el SDK de Apple correspondiente.
- **Swift Package Manager:** [`ZIPFoundation`](https://github.com/weichsel/ZIPFoundation), empleado en el tratamiento de archivos ZIP. Restaurar la dependencia desde el proyecto si Xcode indica `Missing package product 'ZIPFoundation'`.
- **Herramientas de desarrollo de Apple:** Xcode Command Line Tools instaladas normalmente con Xcode; no requiere un Python instalado para ejecutar la app nativa.
- **Permisos de sistema:** selección explícita de carpetas para el sandbox mediante bookmarks; permiso de notificaciones si se desean avisos.
- **Firma y distribución:** un Apple ID/equipo de firma configurado en Xcode puede ser necesario dependiendo del método de exportación. Para distribución a otros Mac sin advertencias, consultar los requisitos actuales de **Developer ID y notarización**.

No se indican números exactos de versión de ZIPFoundation, *bundle identifier*, *deployment target* o firma porque deben leerse del `.xcodeproj` real antes de fijarlos en una release; no deben inventarse.

## Compilación y ejecución

1. Clonar o descargar este repositorio en un Mac.
2. Abrir `STLManager.xcodeproj` (o el workspace correspondiente, si existiera).
3. Seleccionar el esquema `STLManager`, destino **My Mac**.
4. Esperar a que Xcode resuelva los paquetes de Swift Package Manager. Si ZIPFoundation falla: **File → Packages → Resolve Package Versions** y comprobar su vinculación con el target.
5. Revisar **Signing & Capabilities**, *App Sandbox* y los permisos de carpetas necesarios.
6. Compilar con **⌘B** y ejecutar con **⌘R**.
7. En **Preferencias**, seleccionar la biblioteca y `_Inbox`; autorizar notificaciones cuando macOS lo solicite.

## Crear un `.app` para usar fuera de Xcode

### Para uso local o entrega controlada

1. Seleccionar **My Mac** y comprobar el esquema `STLManager`.
2. Elegir **Product → Archive** en Xcode.
3. En **Window → Organizer → Archives**, seleccionar el archivo generado.
4. Usar **Distribute App** y la opción disponible de **Direct Distribution** o **Custom / Copy App** según versión de Xcode y configuración de firma. Exportar la aplicación resultante.
5. Abrir el `.app` exportado desde Finder; seleccionar/autorizar otra vez biblioteca y `_Inbox` si es necesario, porque los bookmarks y preferencias de la app se guardan por usuario e identidad de aplicación.

Otra opción para una prueba estrictamente local es localizar el producto `STLManager.app` de una compilación **Release** en Xcode (**Products → Show in Finder**); no confundir con un paquete firmado y notarizado listo para distribuir.

**Antes de subir una release:** comprobar que el icono `AppIcon` está asignado en `Assets.xcassets`, que el `.app` arranca sin Xcode y que funciona después de cerrar Xcode. La aplicación debe mantener el mismo **Bundle Identifier** para conservar de forma consistente permisos y notificaciones.

### Distribución a otros Mac

La firma para desarrollo/local y la distribución pública no son equivalentes. Para evitar las advertencias de Gatekeeper en otros equipos suele ser necesario firmar con **Developer ID Application** y **notarizar** la aplicación según el flujo vigente de Apple. Este README **no afirma** que la build esté firmada o notarizada.

No subas un `.app` de compilación de depuración como si fuese una publicación verificada. Preferible comprimir el `.app` exportado como ZIP para mantener intacto el bundle al distribuirlo.

## GitHub: conservación del código y binario

Recomendación de estructura del repositorio:

```text
STLManager/
├── README.md
├── .gitignore
├── STLManager.xcodeproj/
├── STLManager/                  # Código fuente y Assets.xcassets
└── [otros archivos del proyecto]
```

1. Hacer un commit del estado funcional y etiquetarlo **`v0.5.8.8.1`**.
2. Crear una **GitHub Release** a partir de esa etiqueta y adjuntar el ZIP del `.app` exportado. Esto suele ser preferible a versionar un bundle binario dentro de Git.
3. Incluir una breve nota de la release (macOS objetivo, cambios y advertencia sobre normalización sin copias automáticas).
4. Conservar en Git el **`Package.resolved` del proyecto**, para que las dependencias se resuelvan a las mismas versiones en futuros builds.
5. **No subir** tu carpeta `~/dev/Diseños`, contenidos comprados, imágenes privadas, bibliotecas STL, contraseñas, certificados de firma ni claves privadas.
6. Revisar el contenido antes de hacer público el repositorio. Si un ZIP sobrepasa los límites de tamaño de GitHub, publicarlo como asset de Release o valorar almacenamiento alternativo; no forzarlo al historial Git.

Ejemplo, desde el directorio del repositorio (cuando esté inicializado y revisado):

```bash
git add .
git commit -m "Release STL Manager v0.5.8.8.1"
git tag v0.5.8.8.1
# Configurar el remoto de GitHub y subir rama y etiqueta:
git push origin main
git push origin v0.5.8.8.1
```

> Si tu rama principal no se llama `main`, sustituye el nombre en el ejemplo.

## Consejos de uso y seguridad

- **Configura primero los permisos de biblioteca e Inbox** desde Preferencias. Son dos bookmarks independientes.
- Para importar un proyecto, coloca un archivo/carpeta/ZIP en `_Inbox`, espera al análisis y selecciona la fila o pulsa su notificación.
- En modo **manual**, revisa siempre **nombre, URL de origen y destino** en la vista previa antes de confirmar; en modo automático no aparece este paso.
- Para normalizar, empieza por **uno o dos proyectos pequeños** y revisa el reporte final.
- Si una carpeta contiene una colección de un diseñador con muchos modelos, márcala **Colección de solo lectura** antes de normalizar el resto; la regla queda en `.stlmanager/library.json`.
- No uses el normalizador para dividir automáticamente una colección comprada en cientos de proyectos. La indexación por modelo es trabajo futuro del catálogo/STLViewer.
- La cancelación de normalización es **entre proyectos**, no instantánea durante el hashing o movimiento de un archivo grande.
- Los cálculos de SHA-256 verifican integridad y pueden requerir I/O significativo en archivos grandes aunque la memoria esté controlada.
- Si aparece un fallo de permisos, vuelve a seleccionar la carpeta adecuada desde Preferencias antes de intentar alterar permisos manualmente.
- Tras una interrupción de importación o normalización, **inspecciona la biblioteca antes de repetir la operación**. No borres carpetas de trabajo ni duplicados sin comprobar su contenido.

## Arquitectura (orientativa)

| Componente | Responsabilidad |
|---|---|
| `STLManagerApp.swift` | Entrada SwiftUI, ventana principal, menú de barra de menús y Preferencias |
| `ContentView.swift` | Bandeja, navegación hacia importación, acciones principales y botón Finder |
| `AppState.swift` | Vigilancia de `_Inbox`, temporizador de Dispatch, detección, estabilidad y coordinación de importación automática |
| `InboxNotifications.swift` | Notificaciones de nuevos pendientes, importaciones completadas o incidencias, y apertura del asistente |
| `ImportView.swift` | Asistente y vista previa de importación |
| `ImportPlanner.swift`, `ImportPlan.swift` | Validación y planificación de rutas de destino |
| `ProjectImporter.swift` | Copia, verificación, creación de README/JSON y envío del original a Papelera |
| `AutomaticInboxImporter.swift` | Flujo de importación automática secuencial que reutiliza el planificador e importador |
| `SettingsView.swift` | Biblioteca, Inbox, monitorización y controles de autoimportación |
| `ZipExtractor.swift` | Extracción ZIP mediante ZIPFoundation |
| `FolderAccess.swift` | Bookmarks y acceso a carpetas bajo App Sandbox |
| `NormalizationView.swift` | Análisis, selección de proyectos y reglas de carpetas |
| `NormalizationEngine.swift` | Planificación y ejecución de normalizaciones |
| `NormalizationProgress.swift` | Estado de progreso, registro y cancelación cooperativa |
| `FolderRules.swift` | Persistencia y consulta de `.stlmanager/library.json` |

## Relación con STLViewer y posibles mejoras futuras

**STLViewer** es una **aplicación independiente** que puede explorar la misma biblioteca de proyectos; no forma parte del código de STL Manager.

Quedan como posibles mejoras futuras las pruebas automatizadas de importación, reversión ante errores, colisiones, reglas heredadas y notificaciones, así como herramientas de diagnóstico y un tratamiento más completo de carpetas que otros procesos sigan escribiendo.

---

**Licencia:** pendiente de decisión. No se incluye una licencia de código abierto automáticamente; si vas a publicar el repositorio para reutilización de terceros, añade un archivo `LICENSE` explícito.

**Nota sobre modelos de terceros:** los archivos STL/3MF/ZIP comprados o descargados conservan sus condiciones de uso y **no forman parte de este repositorio**. La licencia del código de la aplicación no concede permiso para redistribuirlos.
