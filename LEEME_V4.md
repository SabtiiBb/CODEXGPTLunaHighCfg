# Codex AutoRouter V4.1 para Windows

Actualizado el 1 de octubre de 2026. Prepara agentes y reglas para que Codex elija
especialistas según dificultad, incertidumbre y coste de delegar. Prioriza GPT-6 Luna,
GPT-6.1 Sol y GPT-6 Astra cuando están disponibles en la cuenta de destino.

## Instalación rápida

1. Instala Codex, inicia sesión y ábrelo una vez.
2. Extrae todo este ZIP en cualquier carpeta.
3. Ejecuta uno de estos archivos con tu usuario normal de Windows:
   - **INSTALAR_LUNA6_ALTO.cmd**: establece GPT-6 Luna / Alto como principal.
   - **INSTALAR_LUNA6_MAX.cmd**: establece GPT-6 Luna / Máx como principal.
   - **INSTALAR_V4.cmd**: conserva el modelo y esfuerzo existentes; en una
     configuración nueva utiliza la sugerencia disponible, normalmente Luna / Alto.
4. Cierra Codex completamente y vuelve a abrirlo. Las conversaciones existentes
   pueden conservar su selección: ajusta su selector si quieres cambiarla.

Los tres instaladores generan ambos agentes Luna Alto y Máx, más las demás
combinaciones disponibles. La diferencia es el modelo principal predeterminado.
Los instaladores Luna 6 fallan sin cambios si esa combinación no está disponible;
no sustituyen silenciosamente Luna 6 por Luna 5.6.

## Modelos y esfuerzos

El catálogo local de Codex determina los modelos accesibles y sus niveles. No se
copia el catálogo de esta máquina ni se presupone acceso a una cuenta o plan.

- Luna 6 / Alto: implementación clara y acotada (`efficient_worker`).
- Luna 6 / Máx: implementación precisa que necesita profundidad (`efficient_max_worker`).
- Sol 6.1 / Medio o Alto: integración y criterio más exigente (`advanced_medium/high`).
- Sol / Extra alto o Máx: arquitectura, concurrencia y causas ambiguas (`deep_architect`, `deep_max_architect`).
- Astra / Alto, Extra alto o Máx: incertidumbre excepcional que justifica su uso.
- Terra y versiones anteriores permanecen disponibles si el catálogo las ofrece.

Se genera un agente exacto por cada combinación visible y admitida, por ejemplo
`model_gpt_6_luna_max`, `model_gpt_6_1_sol_high` y `model_gpt_6_astra_ultra`.
También se mantienen los alias por familia: `efficient_*`, `advanced_*`,
`balanced_*` y `frontier_*`. Las familias seleccionan su versión más reciente.

Los niveles reconocidos son `none`, `minimal`, `low`, `medium`, `high`, `xhigh`,
`max` y `ultra`; solo se utiliza cada nivel si el catálogo local lo admite.
No se inventa Ultra para Luna ni se confunden niveles de la API con los de Codex.
Una futura etiqueta desconocida se omite hasta que sea compatible con el router.

La guía pide conservar trabajo trivial en el principal, usar normalmente un solo
especialista, como máximo dos trabajos independientes y evitar delegación recursiva.
Luna, Sol y Astra no son una secuencia de intentos obligatorios. La disponibilidad
de versiones antiguas no significa que sean más baratas. No se garantizan ahorros:
el contexto duplicado, reintentos y razonamiento también consumen tokens.

Para reducir instrucciones repetidas, la tabla completa queda en
`<CODEX_HOME>\autorouter\MODELOS.md`, fuera del bloque cargado de AGENTS.md.
Los perfiles disponibles también tienen un coste de contexto en Codex.

## Detección de la carpeta .codex

Orden de selección:

1. Parámetro explícito `-CodexHome`.
2. Variable `CODEX_HOME` del proceso, usuario o equipo, en ese orden.
3. Destino guardado cuando se ejecuta el actualizador ya instalado.
4. `.codex` del perfil actual, si tiene `config.toml`.
5. Candidatos con `config.toml` en Documentos conocido por Windows (incluida
   redirección), Documents/Documentos del perfil y OneDrive, o `.codex` en la raíz
   de unidades fijas, por ejemplo D. Si hay más de uno, exige una ruta explícita.
6. Si no encuentra instalación, `.codex` en el perfil actual.

No contiene nombres de usuario ni letras de unidad obligatorias. Las rutas con
espacios y caracteres Unicode se admiten. Para rutas distintas de las detectadas,
utiliza `-CodexHome`. La ruta estándar de Codex es `~/.codex`; Documentos es una
ubicación personalizada. Encontrar una carpeta no prueba que Codex la esté usando.
Para una ubicación personalizada, configura `CODEX_HOME` en el entorno desde el
que arranca Codex y reinicia la aplicación. El paquete no mueve cuentas ni cambia
por sí solo las variables de entorno de Windows.

## Comandos PowerShell

Desde la carpeta extraída:

```powershell
# Validar sin instalar
.\INSTALAR_GLOBAL_V4.ps1 -Preview

# Elegir ruta y GPT-6 Luna / Alto
.\INSTALAR_GLOBAL_V4.ps1 -CodexHome 'D:\.codex' -PrimaryMode LunaHigh

# GPT-6 Luna / Máx, sin registrar una tarea automática
.\INSTALAR_GLOBAL_V4.ps1 -PrimaryMode LunaMax -SinActualizacionAutomatica

# Actualizar y verificar una instalación existente
.\ACTUALIZAR_AHORA.ps1
.\VERIFICAR_GLOBAL_V4.ps1

# Desactivar actualizaciones automáticas
.\QUITAR_ACTUALIZACION_AUTOMATICA.ps1
```

Todos los accesos principales aceptan `-CodexHome`. Para políticas de ejecución
que bloqueen scripts, usa los CMD o `powershell.exe -NoProfile -ExecutionPolicy
Bypass -File .\INSTALAR_GLOBAL_V4.ps1`. Compatible con Windows PowerShell 5.1 y
PowerShell 7. Requiere Codex con agentes TOML, `debug models` y `features list`.
`-CodexExe` permite indicar el ejecutable `.exe`; no necesita Python ni Node.

## Actualización, conservación y restauración

Al instalar se intenta registrar una tarea del usuario actual, al iniciar sesión y
cada día a las 12:00, sin privilegios elevados. Si falla el registro, se informa y
puedes actualizar manualmente. La tarea conserva el destino y vuelve a descubrir
el ejecutable. `-SinActualizacionAutomatica` no elimina una tarea ya registrada.

Los refrescos **conservan el modelo principal y su esfuerzo**, incluso si cambiaste
el selector. Actualizan agentes y el bloque administrado de AGENTS.md. Conservan
preferencias ajenas, texto personal y límites de concurrencia existentes (también
`max_threads`); en configuraciones nuevas habilitan agentes y dos subagentes.
Un perfil de Codex o instrucciones de proyecto pueden prevalecer sobre estos defaults.

Si falta una familia, omiten sus agentes nuevos. Los antiguos agentes administrados
se convierten en alias disponibles, identificados como tales; consulta la tabla.
Sin ninguna familia fiable o con un catálogo vacío, aborta antes de escribir.
`-AllowCache` admite caché menor de 24 horas como alternativa advertida.
`-CatalogPath` es solo para pruebas; no transportes catálogos entre cuentas.

Hay respaldo antes de cada cambio y reversión ante errores de escritura. Las
colisiones con agentes personales se bloquean. Se conserva el formato de estado y
marcadores V4 para actualizar instalaciones V3/V4 con estos mismos archivos.

Para restaurar, primero desactiva la tarea automática y cierra Codex:

```powershell
.\RESTAURAR_BACKUP.ps1 -CodexHome 'D:\.codex' -BackupPath 'D:\.codex\autorouter\backups\V4_FECHA_IDENTIFICADOR'
```

La restauración exige que los archivos no hayan cambiado posteriormente. El backup
exacto aparece al instalar. Para actualizar desde un paquete anterior, ejecuta el
instalador de este ZIP: ACTUALIZAR_AHORA usa el actualizador ya instalado.

## Alcance y validación

Este paquete configura reglas y agentes; Codex decide cuándo delegar. No sustituye
el modelo principal durante una conversación ni implementa un servicio externo de
selección por mensaje. Respeta las restricciones de agentes del anfitrión.

Pruebas incluidas: selección por catálogo, variantes de modelos, migración,
preservación, vista previa, idempotencia, respaldo, reversión, restauración y
pérdida de familias. Test-Integration necesita el ejecutable local de Codex y crea
un destino temporal sin tareas programadas. No se ha probado en otra computadora
ni se ha registrado una tarea real como parte de la preparación del ZIP.

## Fuentes

- [Subagentes y configuración](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [CODEX_HOME y ubicación predeterminada](https://learn.chatgpt.com/docs/config-file/config-advanced)
- [Familias actuales de modelos](https://developers.openai.com/api/docs/models)

La disponibilidad y los niveles efectivos siempre proceden del catálogo local de
Codex, no de las fichas de la API.