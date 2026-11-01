# Plan de trabajo — Asistente FMC130 (AppImage Linux basada en OpenPets)

Estado: **decisiones confirmadas; fases 1–2 ejecutadas y verificadas (2026-11-01); fork de OpenPets creado como `fmc130-assistant` (sin branding aún)**. Sin AppImage. Sin commits en Fase 1–2. No se ha enviado ningún SMS.

## 0. Decisiones confirmadas

1. Fork de OpenPets con branding FMC130.
2. La lógica de parámetros queda en el RAG (`Claude_workshop_AnthropicAPI`).
3. `setparam` permitido, con confirmación humana.
4. Confirmación humana para cada envío.
5. MCP en modo `live` y `SMS_LIVE_ENABLED=true` (intencional).
6. Sin atribución de IA en commits (sin `Co-Authored-By`). Pendiente: los commits no se han hecho.
7. Envío limitado al destino de pruebas: solo el ICCID de `ONEGLOBAL_TEST_ICCID` (variable de entorno). No se aceptan otros IMEI/ICCID.

## 0.1 Estado de ejecución

- MCP (`Claude_workshop_skill/mcp-server`): `setparam` en allowlist (riesgo Medio), sintaxis validada, token siempre requerido. 92 pruebas unitarias/integración en verde (verificado). Contenedor `mcp-server-mcp-http-1` UP y accesible en `0.0.0.0:8443`, sigue en `live`.
- Cambios de Fase 1–2 **commiteados**: `d48ef65` en `Claude_workshop_skill` y `95a2357` en `Claude_workshop_AnthropicAPI` (árboles limpios).
- **Fork creado**: `Claude_hackaton/fmc130-assistant` es un clon de `openpets` (origin `/cubo_ai/openpets`, mismo historial, árbol limpio). Sin cambios FMC130 todavía. `node_modules` instalado (pnpm 11.0.8, Node 24), listo para `pnpm dev:desktop` / empaquetado.
- Skill y README: documentan `setparam`, los dos espacios iniciales y el contrato del RAG.
- RAG (`Claude_workshop_AnthropicAPI`): contrato `get`/`set` con `sms_text`, `needs_value`, caché solo de respuestas encontradas. 33 pruebas unitarias y 30 de aceptación en verde contra el backend reconstruido.
- RAG: 33 pruebas unitarias/de seguridad en verde (verificado; la de aceptación sigue sin ejecutarse por consumir la API real).
- **`ctx.net` verificado** (`apps/desktop/src/plugin-sdk-network.ts`): soporta POST, cabeceras y cuerpo. HTTP hacia `127.0.0.1:<puerto>` funciona con `network:local`; **HTTPS autofirmado fallará la validación TLS estándar de undici** (no hay excepción de CA). Implicación: servicios locales deben hablar HTTP plano en loopback (el MCP ya es accesible en claro; el backend RAG solo expone HTTPS), o la integración debe vivir en el proceso principal con la CA registrada.
- **Fase 3 (2026-11-01) — integración en `fmc130-assistant`**: asistente FMC130 como módulo del proceso principal: `fmc130-config/core/mcp-protocol/http/service` + IPC `openpets:fmc130-*` + pestaña «Asistente FMC130» en Ajustes (URLs RAG/MCP, toggle TLS autofirmado limitado a loopback, pruebas de conexión, consulta RAG con tarjeta de acción get/set y flujo dry-run/envío real con token del operador). i18n `settings.fmc130.*` en inglés y es-419 ( resto por fallback). Pruebas: 30 en las suites fmc130/desktop (en verde); typecheck main+renderer+tests en verde; `pnpm build` OK. Documentación: `docs/fmc130.md` + codemaps actualizados. Commit de Fase 3: `30fe766` (24 archivos, árbol limpio). Batería completa del fork: 347/349 (2 fallos preexistentes ajenos: `catalog-fallback` y `team-core`; `packaging-contract.test.js` requiere `rpmbuild`, no instalado — corren los 5 checks de dist).
- **Fase 4 (2026-11-01) — AppImage**: `electron-builder.yml` rebrandeado (appId `dev.fmc130.assistant`, productName «Asistente FMC130», ejecutable `fmc130-assistant`, artefactos `FMC130-Assistant-*`, icono nuevo `app-icon-fmc130.png`) y commit `4bab5a8`. Script `build-appimage.sh` en `Claude_hackaton`. Build OK: `dist/FMC130-Assistant-4.1.0-linux-x86_64.AppImage` (221 MB). Smoke de arranque verificado con `--appimage-extract-and-run` + `HOME` aislado: log «Host ready», ventana de mascota creada y procesos con nombre `fmc130-assistan*`.

## 1. Evaluación de las fuentes

### 1.1 `Claude_workshop_skill` (skill + servidor MCP 1GLOBAL)

- **Skill** `skill/teltonika-commands/`: catálogo de 16 comandos (`references/commands.json`) con `getparam <id>[;id…]` (riesgo bajo) y `setparam <id>:<valor>[;…]` (riesgo alto). El SMS tiene límite de 160 caracteres para parámetros (`compatibility.json`). La skill **prohíbe** `setparam` en este laboratorio.
- **Servidor MCP** (`mcp-server/`, Python, 88 pruebas unitarias/integración en verde, sin red):
  - Herramientas: `send_sms(target, text, request_id, dry_run, approval_token)`, `get_sms_status`, `get_sms_response(wait_seconds)`.
  - `target="test"` se resuelve en el servidor con `ONEGLOBAL_TEST_ICCID`; el cliente nunca ve el ICCID completo.
  - Allowlist de comandos (`src/security/command_policy.py`): permite `getparam`, `getinfo`, `getstatus`, `web_connect`… y **bloquea `setparam`**, `cpureset`, `deleterecords`, `flush`, `setdigout`.
  - Con `SMS_REQUIRE_CONFIRMATION=true` cada envío real exige un `approval_token` de un solo uso, emitido por el operador con `python main.py mint "<texto exacto>"`, válido 15 min.
- **Nombres**: el código usa `ONEGLOBAL_*` / `GLOBAL_API`, el dominio es `iot.truphone.com`, y la documentación dice «1GLOBAL (antiguo Truphone)». La UI debe mostrar «1GLOBAL» y mapear los alias.
- **Ojo, README desfasado**: el README indica «transmisión real pendiente, `SMS_DRY_RUN=true`», pero el contenedor en ejecución está en otro estado (ver §2.1).

### 1.2 `Claude_workshop_AnthropicAPI` (RAG FMC130)

- **Backend FastAPI** (`backend/app/`): `POST /api/chat {question}` → embedding local (`intfloat/multilingual-e5-large`, fastembed) → `$vectorSearch` top-8 en MongoDB → Claude (Haiku) elige un candidato → el código arma `ParameterID: X Value: Y`. Rate limit 100/min, TLS con certificado autofirmado, caché de respuestas en `answer_cache`.
- **Datos**: `data/fmc130_parameters.json` (373 filas, 204 IDs de parámetro, 7 secciones) cargados en `fmc130_rag.parameters` con embedding y un índice `parameters_vector_index` en estado READY.
- **Pruebas unitarias**: 24 en verde. Las de aceptación (`test_acceptance.py`) llaman a la API real y no se han ejecutado.
- **Brecha crítica para el requisito de getparam/setparam**:
  - El selector y el formato **solo contemplan configuración**. La respuesta no tiene campo `action` (get/set) ni valor para lectura.
  - `Value:` para parámetros de rango sale como `<min-max>`, así que no es un valor utilizable.
  - Para `getparam` solo hace falta el `parameter_id`; para `setparam` hacen falta id **y** valor validado contra opciones/rango.
  - La caché está indexada por pregunta; hay que incluir la acción en la clave o subir `PROMPT_VERSION`.
- **README desfasado**: dice 2048 dimensiones con OpenRouter; los datos reales son 1024 dimensiones con e5 local.
- **Secretos**: `.env` y `certs/` están en `.gitignore`. No están versionados.

### 1.3 `openpets` (app Electron de mascota de escritorio)

- Monorepo pnpm (`pnpm 11.0.8`, Node ≥20). Escritorio en `apps/desktop/` con **Electron 42**, `electron-builder` y **target AppImage ya configurado** (`electron-builder.yml`, `appimage-payload.ts`, `release.md`, `development.md`).
- **Mascota y avatar**: pets en formato `pet.json` + spritesheet (webp/svg). Hay selección de mascota en la app (`docs/pets.md`) y un pet por defecto.
- **Proveedor Anthropic**: existe perfil de texto nativo Anthropic en el Control Center, con las credenciales en `PluginSecretsStore`. Sirve para la «apikey de Anthropic» sin inventar almacenamiento nuevo.
- **Asistente y capacidades**: el asistente del host llama capacidades registradas por plugins (`ctx.assistant.registerCapability`) con esquema JSON acotado. Es el punto natural para exponer «buscar parámetro», «leer parámetro», «configurar parámetro», «enviar SMS».
- **Red desde plugins**: `ctx.net.fetch` exige que el host esté en `manifest.network.hosts` **y** aprobado por el usuario. La red local requiere `network:local` y, según la doc, habla de endpoints HTTP locales; **no está confirmado que acepte HTTPS con certificado autofirmado en 127.0.0.1 ni llamadas POST con sesión MCP**. Esto es un riesgo a verificar en `apps/desktop/src/plugin-sdk-network.ts`.
- **Estado local**: `node_modules` **no instalado**. Repo limpio en `main`.

### 1.4 Bases de datos Mongo en Docker

| Contenedor | Imagen | Puerto host | Relación |
|---|---|---|---|
| `fmc130-mongodb` | `mongodb/mongodb-atlas-local` | 127.0.0.1:27040 (y 27041 TLS vía `fmc130-mongo-tls`) | **Sí**: BD `fmc130_rag` (`parameters` 373 docs, `answer_cache` 10). Otras BDs: `admin`, `config`, `local` |
| `mongodb-iot` | `mongo:8.0.5` | 0.0.0.0:27017 | No relacionado por nombre; no inspeccionado |
| `smtt_mongodb` | `mongodb/mongodb-atlas-local:8.0` | 0.0.0.0:27020 | Otro proyecto (`agente_soporte`); no inspeccionado |
| `ecoguide_dev-mongodb` | `mongodb/mongodb-atlas-local:8.0` | 127.0.0.1:27028 | No relacionado |

Sólo `fmc130-mongodb` es relevante. Las credenciales están en el entorno del contenedor; no se han copiado.

### 1.5 Servicios vivos relevantes

- **`mcp-server-mcp-http-1` (oneglobal-sms)**: `ONEGLOBAL_MODE=live`, `SMS_DRY_RUN=false`, `SMS_LIVE_ENABLED=true`, `SMS_REQUIRE_CONFIRMATION=true`, transporte `streamable-http`, publicado en **`0.0.0.0:8443`** (accesible desde toda la red).
- **`fmc130-backend`**: `127.0.0.1:8453` (HTTPS). **`fmc130-frontend`**: `127.0.0.1:4443`.

## 2. Riesgos y bloqueos

### 2.1 Seguridad — requiere acción inmediata del operador

1. El MCP está configurado para transmitir **SMS reales** (`live`) y escucha en todas las interfaces, mientras el README dice que la transmisión real está deshabilitada. La única barrera es el `approval_token` de un solo uso, que el modelo no debe poder generar. **Recomendación**: confirmar si es intencional. Si no, bajar a `SMS_LIVE_ENABLED=false` y publicar solo en `127.0.0.1`. No se ha tocado el contenedor.
2. Requisito de `setparam` **en conflicto con la política vigente** (allowlist + skill + README: «cambios setparam sin un flujo diseñado y revisado»). Hay que diseñar ese flujo explícitamente (ver §4, decisión D3).
3. Con `SMS_REQUIRE_CONFIRMATION=true`, una app de mascota no puede enviar nada sin que alguien mint-ee un token por cada carga exacta. El diseño actual asume operador CLI, no un usuario en una app.

### 2.2 Técnicos

- Tanto RAG (`:8453`) como MCP (`:8443`) usan **TLS autofirmado** en desarrollo. La app debe confiar en una CA local o el MCP debe ejecutarse dentro del AppImage por stdio.
- Empaquetar **MongoDB + modelo e5-large** dentro del AppImage no es viable. El RAG debe ser un servicio externo configurable, o reescribirse para correr en el propio binario.
- **Confirmar** en el código de `plugin-sdk-network.ts` si `ctx.net` soporta POST, cabeceras de sesión MCP y TLS autofirmado. Si no, la integración debe vivir en el proceso principal del host (nuevo módulo), no en un plugin.
- `dist-electron/` no está en `Claude_hackaton/.gitignore`; añadirlo al crear el repo.

### 2.3 Gobernanza de commits

- `Claude_hackaton/AGENTS.md` prohíbe líneas de atribución de IA en commits. La instrucción del sistema pide `Co-Authored-By`. Hay que decidir cuál aplica antes del primer commit. Pendiente de confirmación del usuario.

## 3. Información que falta (para cerrar la AppImage)

1. Dónde corre el RAG en producción (servicio externo en este equipo, o incluido en la app).
2. Si el MCP corre en stdio dentro del AppImage (requiere Python en el equipo destino) o como servicio HTTPS.
3. Quién aprueba los envíos reales: el usuario final en la app, o el operador con token CLI.
4. Imagen y nombre de la mascota FMC130 (o reutilizar el pet por defecto).
5. Idioma: español por defecto (las cadenas de OpenPets tienen i18n).

## 4. Decisiones que necesito del usuario

- **D1 — Base de la app**: (a) fork de OpenPets con branding FMC130 y plugin integrado; (b) plugin dentro de OpenPets sin fork. *Recomendación*: (a); un plugin no puede cambiar el nombre/appId ni el empaquetado, y el requisito es un AppImage propio.
- **D2 — Dónde vive la lógica de RAG/MCP**: (a) módulo del proceso principal de OpenPets; (b) plugin con `ctx.net`. *Recomendación*: (a) hasta confirmar que `ctx.net` soporta el flujo.
- **D3 — `setparam`**: (a) permitirlo solo con confirmación explícita de la app y token de aprobación generado por el operador **en la app** (secreto local); (b) mantenerlo bloqueado y ofrecer solo `getparam`. *Recomendación*: (b) para el hackathon; (a) requiere revisar la política de seguridad del MCP.
- **D4 — Aprobación de SMS**: (a) confirmación humana en la UI + token generado por la app; (b) token manual por el operador. *Recomendación*: (a) con MCP en `127.0.0.1`.
- **D5 — Estado del MCP vivo**: ¿mantener `live` en `0.0.0.0:8443` o cerrarlo? (Requiere su confirmación; no lo toco.)
- **D6 — Commits**: ¿Co-Authored-By o sin atribución (según `AGENTS.md`)?

## 5. Plan de trabajo propuesto

**Fase 0 — Preparación (sin cambios en repos fuente)**
1. Confirmar decisiones D1–D6 y el estado del MCP vivo (§2.1).
2. `pnpm install` en `openpets` (Node 24 válido; Electron 42 se descarga) y verificar `pnpm build` y `electron-builder --linux AppImage --x64 --dir` como base.

**Fase 1 — RAG con intención (en `Claude_workshop_AnthropicAPI`)**
3. Extender la respuesta del RAG con `action: "get" | "set"` y `value` obligatorio solo para `set`, validado contra opciones/rango.
4. Ampliar el prompt del selector y la clave de caché (o `PROMPT_VERSION`).
5. Añadir pruebas unitarias: pregunta de lectura → `getparam`; pregunta de escritura → `setparam` con valor; rango sin valor → pedir valor.
6. Corregir el README (dimensiones, embeddings).

**Fase 2 — Cliente de SMS (en `Claude_workshop_skill`)**
7. Definir el contrato `getparam`/`setparam` para la skill: ensamblado del texto (`getparam 138` / `setparam 138:1`), límite de 160 caracteres y validación de espacios iniciales.
8. Si se aprueba D3(a): flujo de aprobación de `setparam` en el MCP (sin cambiar la allowlist por defecto); si no, solo `getparam`.
9. Documentar en el README que `send_sms` requiere token y cómo se obtiene en la app.

**Fase 3 — Integración en la app (en `openpets` → `Claude_hackaton`)**
10. Crear el asistente FMC130 (capacidades: `fmc130.lookup`, `fmc130.read`, `fmc130.configure`, `fmc130.sendSms`) con esquemas acotados.
11. Pantalla de configuración: API key de Anthropic (reutilizando `PluginSecretsStore`), URLs de RAG y MCP, selector de avatar.
12. Cadenas en español; nombre visible «1GLOBAL»; alias ONEGLOBAL/GLOBAL/TRUPHONE documentados.

**Fase 4 — AppImage**
13. ✅ Ajustar `electron-builder.yml` (productName, appId, icono FMC130, sin plugins de terceros) y script de build en `Claude_hackaton` (`build-appimage.sh`, commits `4bab5a8`).
14. ✅/⚠️ Ejecutar el AppImage en Linux y verificar arranque (hecho en smoke headless del log). Pendiente de verificación visual GUI: selector de avatar, lectura de parámetro vía RAG, envío de `getparam` vía MCP en `replay` (sin SMS real) y que `setparam` pida confirmación.

**Fase 5 — Verificación**
15. Pruebas offline de los tres componentes (ya existen: 88 MCP, 24 RAG, más las nuevas).
16. Pruebas de aceptación solo tras autorización (consumen Anthropic y, en live, SMS reales).

## 6. Lo que no se ha verificado

- Los tests de aceptación del RAG no se han ejecutado (consumen la API real).
- El envío real por 1GLOBAL no se ha probado; el MCP vivo no se ha invocado.
- Smoke del AppImage limitado al arranque headless: la interacción GUI (pestaña «Asistente FMC130», consulta RAG, get/set con token) requiere sesión gráfica y queda para la fase de aceptación.
