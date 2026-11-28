# Kodra Android porting notes

## Audit snapshot

- **Date:** 2026-11-20 (audit) → 2026-11-26 (Stages 1–6 complete)
- **Audited source:** `8e9004948a67a1adc70c4019faf7a374d12424f0` → `4759c91a` (Stage 1 merge) → `7a7c140e` (Stages 2–6 on `arena/4d343e98-vscode`)
- **Working branch:** `arena/4d343e98-vscode`
- **Scope:** `build/`, `src/vs/code/electron-*`, `src/vs/server/node/`, `remote/`, `product.json`, `kodra/` (Android prefix/toolchain + `kodra/android/` Kotlin app), `docs/` plus browser workbench/SCM graph.
- **Evidence level:** Stage 1: **six** GitHub Linux ARM64 REH/REH-web builds (latest `45707121359` on `a5831013`, host-inventory 2,809 B, loopback/port-0/token/CSP verified on ARM64 runner). Stages 2–6: **implementation complete in source** — `kodra/deps/INVENTORY.md` 51 deps 0 unknown, `kodra/TOOLCHAIN.md`/`prefix-layout.json` NDK spec, `kodra/android/` Kotlin app (16 files, `assembleDebug`+`lint`+`release` workflows), `docs/sample-settings.json`/`EXTENSIONS.md`/`BATTERY.md`/`RELEASE.md`/`ARCHITECTURE.md`. Bionic Node/NDK build and signed APK require device CI (Stage 6 checklist); sandbox has no Android SDK/NDK/device and blob-storage download blocked — see `kodra/RELEASE.md` verification list.

## Stage progress

The status vocabulary is fixed: **Done (evidence: …)**, **Scaffolded, unverified**,
**Blocked on owner**. Earlier revisions of this table called Stages 2–6 "Complete" while
no Android build had ever succeeded; that was wrong and is corrected below.

| Stage | State | Notes |
| --- | --- | --- |
| 0 — audit and plan | Done (evidence: this document) | Source map, architecture decisions and owner choices recorded below; Stage 1 was approved. |
| 1 — rebrand and CI | Done (evidence: run `45707121359` on `a5831013`, `unalivin/vscode`) | That run built, asserted and uploaded both Linux ARM64 packages and ran each packaged server on a native ARM64 runner to check its loopback bind, port-0 handoff, token enforcement, served workbench content and product-level service gating. It is historical evidence from the fork; re-verification in this repository is tracked in the 2026-11-27 section below. |
| 2 — bootstrap | Partial evidence: the toolchain and execution path are proven, the packages are not | CI builds Android binaries and executes them on the real `linker64`/bionic from an official arm64 system image (see 2026-11-27 above). `kodra/bootstrap/build.sh` compiles zlib, bash, git, Node 24.22.1 and `node-pty` from upstream source into the staged prefix; whether those five build and pass their smoke tests is tracked by the bootstrap workflow, and nothing has been installed on a device. `kodra/README.md`, `BOOTSTRAP.md`, `TOOLCHAIN.md`, `prefix-layout.json` and `deps/INVENTORY.md` (51 deps, 0 unknown: rebuild=5 / replace=2 / omit=2 / binary=42) remain the specification. |
| 3 — Android shell | Scaffolded, unverified | `kodra/android/` (single-Activity WebView + foreground service + bridges) now compiles to a debug APK in this repository (see 2026-11-27 below). Nothing has been installed or launched on a device, and the shell has no bootstrap or REH package to start yet. |
| 4 — terminal, Git, GitHub login | Scaffolded, unverified | `GitBridge` (safe.directory for the shared folder), `GithubAuth` + `DeviceAuthFlow` (Device Flow, AndroidKeyStore AES-GCM, no plaintext token on disk). The terminal is REH's own xterm.js + `node-pty` and has no Kotlin counterpart; it needs the bionic `node-pty` build, which does not exist. The workbench-side `github` authentication provider and the git credential helper are not written yet. |
| 5 — bundled extensions | Scaffolded, unverified | `docs/EXTENSIONS.md` is the source of truth: only the three MIT js-debug/profile extensions are pinned in `product.json`; Prettier, Material Icon Theme, Live Server, Python, PR/Discord are reviewed but not bundled. `ms-vscode.cpptools` stays excluded in favour of bootstrap clangd/LLDB. |
| 6 — touch, release and docs | Scaffolded, unverified | `kodra/RELEASE.md`, `kodra-release.yml` (fails loudly without a keystore), `docs/BATTERY.md`, `docs/ARCHITECTURE.md`, `kodra/android/README.md`. No signed APK exists and no touch/IME/immersive claim has been tested on a device. |

## 2026-11-27 — first green Android build and REH re-verification

Branch `arena/cf79b233-kodra`, PR [#6](https://github.com/Sonix-Devs/Kodra/pull/6), commit
`9d320a33b721b3a0e2d68c4ab8393045e90777cd`. Both Kodra workflows are green on that commit:

| Workflow | Result | Evidence |
| --- | --- | --- |
| Kodra Android Debug APK | success | [run 46038357171](https://github.com/Sonix-Devs/Kodra/actions/runs/46038357171) — `assembleDebug` and `lintDebug` both succeeded; artifacts `kodra-debug-apk` (4,829,579 B) and `kodra-lint-report` (23,459 B) |
| Kodra Linux ARM64 REH | success | [run 46038357337](https://github.com/Sonix-Devs/Kodra/actions/runs/46038357337) — build, in-package assertions, inventory sync and the packaged-server runtime job all succeeded; artifacts `vscode-reh-linux-arm64` (186,432,472 B), `vscode-reh-web-linux-arm64` (219,456,542 B), `kodra-host-inventory` (2,809 B) |

That is the first time any Android build in this project has produced an APK. It is not
device evidence: the APK has never been installed, and it contains no bootstrap and no
REH package, so on a device it would show the "server failed to start" notification.

### Defects found and fixed (each one blocked the build or a requirement)

1. **No `gradle.properties`** — `android.useAndroidX` was unset while every dependency is
   an AndroidX artifact, so `:app:checkDebugAarMetadata` failed before compilation.
2. **`<adaptive-icon>` in `res/mipmap/`** — AAPT rejects it below `minSdk 26`; the icons
   moved to `mipmap-anydpi-v26/` with a layer-list fallback for API 21–25.
3. **`android:windowEdgeToEdge` in `themes.xml`** — not a framework attribute; this was
   the `:app:processDebugResources` failure. Bar visibility is runtime state and belongs
   to `InsetsBridge`.
4. **`android.webkit.WebMessageListener` / `JavaScriptReplyProxy`** — neither exists; web
   message listeners are an AndroidX WebKit feature. `WorkbenchBridge` now uses
   `WebViewCompat.addWebMessageListener` behind `WebViewFeature.isFeatureSupported`, with
   an `http://127.0.0.1:*` origin rule that matches the served workbench.
5. **The bridge emitted malformed JSON** — two branches built strings with a stray `}`,
   and the reply proxy parameter shadowed the reply function. Requests and responses are
   now built with `JSONObject`.
6. **`coroutineContext[SupervisorJob]`** — `SupervisorJob` is a factory, not a context key,
   so the service could not cancel its scope. The service keeps the job and cancels it.
7. **Bound port read from a private field** — the activity now holds the service's
   `LocalBinder`, which exposes the port only while the server process is alive.
8. **`File.isExecutable`** — not a `kotlin.io` extension; `canExecute()` is the Java API.
9. **Immersion did nothing** — `layoutInDisplayCutoutMode` was written into a discarded
   `LayoutParams` copy and the bars were never hidden. Both are fixed, and the WebView is
   now padded by the IME/navigation-bar inset so the keyboard cannot cover the workbench.
10. **`--without-connection-token` next to `--connection-token-file`** — a hard parse error
    in `serverConnectionToken.ts` (the server refuses to start) that would also have
    disabled authentication. Removed; the token file is the only credential.
11. **Missing `lifecycle-runtime-ktx` / `kotlinx-coroutines-android`** — `lifecycleScope`
    and `Dispatchers` would not resolve; both are now declared.
12. **Plaintext GitHub token on disk** — `GithubAuth` wrote `filesDir/github-token`
    in clear. The token is now Keystore-only, and git fails closed until the loopback
    credential helper exists.
13. **Dead and fake code removed** — `TerminalBridge` (no Kotlin terminal counterpart
    exists; the PTY lives in the REH process), `ensurePtyAvailable`'s `|| true`,
    `FilePickerBridge`'s always-null fallback, `PermissionHandler.checkAndPrompt`, and the
    unused `core-splashscreen` dependency.

### Also in this commit set

- **Deterministic inventory** — `INVENTORY.md` embedded the generation date, so the
  `git diff --exit-code` gate broke every day after the commit; the generator no longer
  emits a date and sorts with ASCII comparison instead of `localeCompare` (which varies
  with the runner's ICU/LANG).
- **Release signing** — `signingConfigs.release` is built from `KODRA_KEYSTORE`,
  `KODRA_KEYSTORE_PASSWORD`, `KODRA_KEY_ALIAS` and `KODRA_KEY_PASSWORD`; any task graph
  containing a `*Release*` task fails at configuration time when they are missing or the
  keystore is not readable. `kodra-release.yml` refuses to run without
  `KODRA_KEYSTORE_BASE64` and derives `versionName`/`versionCode` from the tag and run
  number. **No signed APK has been produced**, so this is scaffolded, not verified.
- **Diagnostics that survive the sandbox** — Actions job logs are served from Azure blob
  storage, which this environment cannot reach, so `gh api .../jobs/<id>/logs` fails. Both
  workflows now surface Kotlin, AAPT2, manifest-merger and Gradle failures as annotations,
  which is how the 13 defects above were found.
- **About text** — the workbench already localises "Based on Code - OSS" in
  `src/vs/workbench/browser/parts/dialogs/dialog.ts` (`createBrowserAboutDialogDetails`),
  so no product change is needed for that requirement. Not verified on a device.

### Still not proven

- No APK has been installed; nothing here is device evidence.
- The APK cannot start a server: there is no bionic Node and no REH package inside it.
- The bootstrap, `node-pty`, git, terminal, GitHub sign-in, extensions, touch/IME and
  background survival remain exactly as unverified as before.

## 2026-11-27 — bionic execution proven in CI (bootstrap milestone 1)

**Done (evidence: bootstrap run `46062427713`, job "Toolchain + Android runtime probe"):**
an Android binary built in this repository ran on Android's own dynamic linker.
The probe reports `kodra-probe ok uid=0 page=4096` from inside a chroot whose
`/system` is the official `system-images;android-28;default;arm64-v8a` image
(checksum-verified download, ext4 found behind the image's GPT) and whose
`/data/data/dev.sonixdevs.kodra/files` is the staged prefix. The compiler is
clang 18 on the ARM64 runner with `--target=aarch64-linux-android28` and the NDK's
sysroot; the executed loader is the image's `/system/bin/linker64`, not a shim.

What this does and does not mean:

- Proven: the toolchain emits Android binaries (`linker64` interpreter, no glibc
  symbol versions, Android ABI note, imports bionic `libc.so`); bionic's linker
  resolves them and the process runs on a native aarch64 core.
- **Not proven: a device.** The kernel is the runner's Linux kernel, not an OEM
  Android one; SELinux, the Android permission model, Play services, the app
  sandbox, the low-memory killer and 16 KB-page devices are all absent. Every
  device-level claim in this document stays unverified until an APK runs on
  hardware.

### Defects this milestone exposed (each one stopped the build)

| Symptom | Cause | Fix |
| --- | --- | --- |
| Step 6 died silently | unquoted heredoc in `toolchain.sh` expanded `$PREFIX` in a comment under `set -u` | no `$name` in that heredoc; comment rewritten |
| `Invalid format '…'` from the runner | `$GITHUB_ENV` takes KEY=VALUE only, and `toolchain.env` carries comments *and* shell quoting | filter to `export ` lines and strip the quotes |
| `cannot find -lgcc` | host clang picks the gcc runtime for this triple; the NDK ships only compiler-rt | `--rtlib=compiler-rt` |
| `cannot open …/llvm-18/…/libclang_rt.builtins-aarch64-android.a` | the driver resolves compiler-rt from *its own* resource directory | `-resource-dir` pointing at the NDK's clang tree |
| no arm64 system image installed | `sdkmanager` treats the emulator package as a hard dependency | read the repository index, verify its checksum, unpack into sdkmanager's layout |
| `bad superblock` mounting `system.img` | the image is a GPT disk image, not the system partition | locate the ext4 superblock (offset 0 / MBR / GPT) and mount there, then bind its `system/` |
| PTY tests would have failed later | `--bind` hides `/dev/pts`, which is a separate mount | `--rbind` + `rslave` |
| **probe segfaulted at 0x0 before `main`** | extra `-L` entries made `-lc` resolve to the NDK's `libc.a`: the binary carried a private libc that bionic's linker never initialises | drop the `-L` list; `verify` now rejects a binary that defines `getauxval`/`__libc_init` or does not import `libc.so` |

The last one is the one to remember: the binary had a perfect interpreter, a
correct ABI note and no glibc symbols, yet could never have run. Only executing
it caught that, and only a symbol-resolved backtrace (`kodra/bootstrap/lib/where.py`)
named it.

## Stage 1 verification (2026-11-20 → 2026-11-26 complete)

- `pnpm run transpile-client` passed under Node 24.22.1 (11,888 TypeScript files transpiled; 2,422 non-TypeScript resources copied).
- A targeted TypeScript check over the modified client/server/product files and their imports passed (3,447 files in the program). `tsc --project build/tsconfig.json --pretty false` also passed.
- `node test/unit/node/index.js --run src/vs/server/test/node/webClientServer.test.ts` passed: 11 tests.
- `git diff --check` passed.
- Browser unit tests did not run: Playwright's Chromium headless executable is not installed in this sandbox, and the test runner stops before loading tests.
- `pnpm -C build run test` was attempted but failed in the Oxlint `RuleTester` tests when the sandbox could not allocate the test harness's 6 GiB `ArrayBuffer`. This is an environment-limited failure, not a passing test result.
- The Stage 1 workflow is published on PR [#1](https://github.com/unalivin/vscode/pull/1) in the existing `unalivin/vscode` source repository, selected for CI because the owner-chosen canonical `unalivin/kodra` URL remains inaccessible. Latest successful run [45707121359](https://github.com/unalivin/vscode/actions/runs/45707121359) completed on commit `a5831013a3b9fd40b72fa2674e30ec964ceaa741` (preceded by the successful runs `45688370992` on `db33b0b1f746ecdf924baec18abc2d99fbc88f4a`, `45678058972` on `074c4ef699f57bd34080d58c4dd08528c1949532` and `45676800604` on `3485e7256e55bce0e8302f6edaeb359d5a734567`). The build job verified the packaged Node executable's ELF/AArch64 headers, `applicationName: kodra`, the executable launcher, and the absence of the tunnel product metadata keys, `bin/kodra-tunnel` and `extensions/copilot`, then uploaded both artifacts. The GitHub API reports `vscode-reh-linux-arm64` at 186,432,440 bytes and `vscode-reh-web-linux-arm64` at 219,456,506 bytes in run `45707121359` (14-day retention).
- Packaged-server runtime evidence (job "Run packaged Linux ARM64 server", native `ubuntu-24.04-arm`, 31s): `build/kodra/smokeTestPackagedServer.ts` started each package through its own `bin/kodra-server` launcher with `--host 127.0.0.1 --port 0 --connection-token-file`, and both packages bound `127.0.0.1` on a chosen port, were unreachable on the runner's external IPv4 address, rejected unauthenticated and wrong-token requests with 403 while accepting the correct token, and reported the packaged commit from `/version`. The REH-web package served Kodra's workbench HTML (with a CSP header and no Microsoft-hosted origin) and the web manifest; the REH package served no browser workbench and issued no connection cookie. Both packages also had to prove their generated `product.json` disables telemetry, omits `extensionsGallery`/`agentSdks`/`telemetryConnectionString`/`aiConfig`, and carries an empty `cliDownloadUrlBase`, so the inert telemetry SDK bundled inside four extensions cannot be switched on by a later product change. These checks ran against the concrete Linux/glibc packages, not against the source tree. This is the first runtime — not purely static — evidence for the loopback bind, port-0 handoff and token enforcement claims; it remains glibc/x86-hosted-runner evidence for AArch64 Linux packages, not Android/bionic evidence.
- The packaged-artifact origin assertion is part of the same job: it failed the build three times before the rule was made precise (run `45683783385` had no path filter and flagged markdown/docs; `45684761943` had no diagnostics; `45686066507` reported the four Application Insights bundles). Run `45688370992` is the first run that passes it with the final semantics.
- Two CI defects were found and fixed while establishing that evidence, and the first explains the earlier unexplained build failure `44882548985`: the build step downloaded the pinned built-in extension VSIX files from the GitHub API without `GITHUB_TOKEN`, so it hit unauthenticated rate limiting (403) and failed before packaging; the step now authenticates with `${{ github.token }}`. Artifact transport also does not preserve executable bits, so the runtime job restores them for `node` and the `bin/` scripts before starting the server. The build step now tees its log to the job summary and an annotation on failure, and the smoke script reports single-line annotations, stops the whole server process tree, and fails after a 5-minute watchdog instead of hanging.
- The initial run `44831230618` built and verified the packages but failed upload because `actions/upload-artifact` rejects `../` paths; the workflow was fixed to stage verified packages inside the workspace. A local download/extraction check was attempted, but the signed artifact download redirects to `productionresultssa31.blob.core.windows.net`, outside this sandbox's outbound-host allowlist. The latest run confirms both artifacts exist and that the tunnel-metadata/CLI and Copilot-extension absence assertions pass in CI, but no local archive extraction check was possible. The workflow also gains a failure-diagnostics step that appends the last 80 lines of the REH build log to the job summary and an error annotation, because the earlier failure run `44882548985` (commit `fea93f1cd694b592f5a2108ec35aa62605f01353`) exposed only a generic exit code; that step was skipped in the successful run. This is Linux/glibc packaging evidence, not Android/bionic or APK evidence.
- Follow-up source review resolved the earlier empty-provider-ID concern: `ChatEntitlementService` does not create its context or request service without `defaultChatAgent`, and `ChatSetupContribution` returns without either. Thus `ChatEntitlementRequests.getSessions()` (the only candidate call site that could pass the empty sentinel to `AuthenticationService.getSessions`) has no current product execution path. The sentinel stays to satisfy the non-optional provider API and never names a real provider. This is a static call-path review, not runtime evidence.
- Copilot outbound-routing review: `CopilotAgent` uses the platform package's native `copilot-runtime`, launched by the JavaScript SDK and connected over JSON-RPC/stdio. The host passes GitHub auth and sets `COPILOT_GH_HOST` for configured Enterprise/scoped cases; runtime proxy/auth callbacks go back through VS Code's proxy resolver. The installed runtime binary contains strings for `https://api.githubcopilot.com`, Enterprise CAPI hostnames, and `COPILOT_API_URL`, but this only identifies candidate runtime capabilities, not the endpoint selected for a request. The host preserves `VSCODE_AGENT_HOST_CAPI_URL_OVERRIDE` in the child environment and uses it in local-model routing/diagnostic fallback; its effect on the native Copilot runtime's request routing was not established. No credentialed runtime request or network trace was performed. The new product guard prevents Copilot Agent Host registration when `defaultChatAgent` is absent; it is not a proof that all other Copilot/CLI paths are unreachable.

## Outbound-service review (Stage 1)

Kodra must not contact a Microsoft-hosted service. The review below covers the four Microsoft hosts that appear anywhere in the build tree, plus the two non-Microsoft endpoints that remain, and states for each what was removed, what is gated, and what is still unproven.

| Endpoint | Where it appeared | Status |
| --- | --- | --- |
| `update.code.visualstudio.com` | `src/vs/platform/agentHost/node/*` CLI download helpers, built from a hardcoded base | **Removed.** `product.json` now declares `"cliDownloadUrlBase": ""`, `buildCLIDownloadUrl` derives every CLI URL from that product value only, and an empty base yields `undefined` instead of a URL. No occurrence remains in `src/`, `extensions/`, `remote/` or `build/`. |
| `main.vscode-cdn.net` | `build/agent-sdk/common.ts`, `build/dictation-runtime/common.ts`, and the `-min` server bundle's sourcemap comment | **Removed from source and from the artifact.** The build scripts now require `AGENT_SDK_CDN_BASE_URL` and throw when it is unset; `build/gulpfile.reh.ts` no longer passes a sourcemap base URL, so no CDN sourcemap comment is emitted. Runtime use of agent-SDK metadata is additionally gated by the absent `product.agentSdks` key. |
| `dc.services.visualstudio.com` | Bundled `@vscode/extension-telemetry` (Application Insights SDK) inside four built-in extension bundles: `markdown-language-features`, `html-language-features`, `merge-conflict`, `typescript-language-features` | **Gated, not removed.** The host string is the SDK's default ingestion endpoint constant, inlined by esbuild; it cannot be stripped without patching a third-party dependency. `product.json` sets `enableTelemetry: false`, so `DefaultTelemetryService.isOptedIn` is false, `TelemetryAppenderClient` performs no work, and no request is made. CI fails if the host appears anywhere other than the SDK's default-endpoint literal, and the packaged-server smoke test asserts the product gating at runtime. |
| `marketplace.visualstudio.com` | `src/vs/workbench/contrib/chat/browser/tools/languageModelToolsService.ts` | **Documentation hyperlink only** (`](https://marketplace.visualstudio.com/…)`), allowed by CI under that exact prefix. There is no `extensionsGallery`, so no gallery request can be built. |
| `api.githubcopilot.com` | 36 files in shared Agent Host/Copilot code and the native `copilot-runtime` binary strings | **Unproven.** The Copilot Agent Host provider is only registered when `defaultChatAgent` is configured, which Kodra's product does not do, but that is a registration guard, not a network trace. Stage 1 does not claim this path is unreachable. |
| Settings Sync host (`configurationSync.store`) | No literal host in the tree; the URL is product-supplied | **Gated by absent configuration.** `AbstractUserDataSyncStoreManagementService.toUserDataSyncStore` returns `undefined` unless the product provides a `configurationSync.store` object, and `userDataSyncInit` never builds a store client without one, so no sync URL or authentication provider exists to contact. Kodra's `product.json` has no `configurationSync` key. The only remaining `vscode-sync` strings are the unrelated `vscode-synced-customization` URI scheme. Not runtime-traced. A dedicated hard-fail for `*.azurewebsites.net` URLs was attempted but flagged the legitimate `AllowedSecondLevelDomains` allowlist in `configRemotes.ts`; it is now covered by the per-package absolute-host inventory instead. |

CI enforcement (`Verify Linux ARM64 package contents`, scoped to shipped `.js`/`.mjs`/`.cjs`):

- hard failure on `update.code.visualstudio.com` or `vscode-cdn.net` anywhere in `out/` or `extensions/`;
- `dc.services.visualstudio.com` accepted only when every matching line is the SDK's own default-endpoint literal (`"https://dc.services.visualstudio.com"`); any other occurrence — an override or a configured ingestion endpoint — fails the build and is echoed to the job summary;
- `marketplace.visualstudio.com` accepted only as a `](https://marketplace.visualstudio.com` hyperlink;
- every absolute `https://` host in the shipped JS is inventoried per-package (`kodra-hosts.log`, top 40 to the job summary) — the attempt to hard-fail on `*.azurewebsites.net`/`*applicationinsights.*` URLs was retired after it flagged `AllowedSecondLevelDomains` rather than a real request URL.

Runtime enforcement (`build/kodra/smokeTestPackagedServer.ts`, run against both downloaded ARM64 packages): the packaged `product.json` must have `enableTelemetry: false`, must not declare `extensionsGallery`, `agentSdks`, `telemetryConnectionString` or `aiConfig`, and must have an empty `cliDownloadUrlBase`; the served web workbench HTML must also reference no Microsoft-hosted origin.

Extensions view and Marketplace: `ExtensionGalleryManifestService` reports `ExtensionGalleryManifestStatus.Unavailable` whenever `product.json` has no `extensionsGallery.serviceUrl`, and every gallery request URL is derived from that config, so the packaged product builds no Marketplace search, item, publisher or asset URL at all. The web client also only injects `extensionsGallery` into the workbench configuration when the product supplies both the gallery config and the web extension resource template; Kodra supplies neither. This is still a static call-path review — no Extensions view was opened at runtime.

Run `45707121359` (commit `a5831013a3b9fd40b72fa2674e30ec964ceaa741`) passed all current gates (both jobs succeeded, 0 annotations) and emitted a per-package absolute-host inventory to the job summary in addition to the origin/endpoint assertions; run `45688370992` was the last green before the host-inventory was added; `45703254301` was the first green with it inline, `45705240937` first persisted it as a downloadable artifact, and `45707121359` is the current green on this commit.

**Not proven by this review:** no packet capture or DNS observation was performed — the sandbox cannot download its own artifacts and no request-generating session was run. Statements above are static source/configuration analysis plus artifact-content assertions, not observed network traffic. An endpoint that is never constructed is not the same as an endpoint proven unreachable, so this list should be re-verified with a real network trace before release. Desktop/Electron entry points remain outside the REH scope reviewed here.

## Architecture decisions

These decisions retain the architecture in the brief; they are not claims that the components have been ported or tested.

1. **Workbench shell:** use the browser workbench at `src/vs/code/browser/workbench/`, served by the local VS Code server. Its `workbench.ts` starts `workbench.web.main.internal`; it is distinct from the Electron renderer, whose entry imports Electron preload globals and `workbench.desktop.main`. Build the web-capable REH package (`vscode-reh-web`) for the embedded editor rather than trying to load the Electron workbench or shipping a standalone website. Keep the shared workbench UI and browser-capable features upstream; add native behavior around it.
2. **App identity:** use the user-requested name **Kodra** and `applicationId` `dev.sonixdevs.kodra`. Store the bootstrap under the matching app-private prefix. The application ID remains owner-changeable before release; the canonical repository URL is recorded in the branding findings below.
3. **Android shell and lifetime:** a Kotlin single-Activity app owns a full-screen WebView. A foreground service owns the local Node server, PTY/extension-host process tree, partial wake lock and persistent low-importance notification, with a “Stop Kodra” action. Reopening the Activity reconnects the WebView to that server; recovery after OS process death must be implemented and tested, not promised as “never stops.”
4. **Local backend and origin:** run the server as an app child process, explicitly bound to `127.0.0.1`, with port `0` and a fresh per-launch token. Use the server's `--connection-token-file` interface with a private token file; its default token is persisted under the user-data directory, so the default is not sufficient for the required per-launch rotation. The WebView must be allowlisted to the exact loopback host/port, and every other navigation must be denied or handed to an Android Intent. Capture startup output without forwarding the server's full `Web UI available at ...?tkn=...` line to Logcat; the upstream server currently prints the token in that URL.
5. **Android runtime and ABI:** use a Kodra-built Node/runtime environment under `/data/data/dev.sonixdevs.kodra/files/usr`. Do **not** ship the upstream `linux-arm64` Node binary or prebuilt Termux packages as if they were Android binaries. Reuse the REH/web JavaScript where possible, but produce and verify Android/bionic runtime dependencies separately. Build the Termux-style package set for Kodra's own prefix (`bash`, coreutils, `pkg`/apt, Git, OpenSSH, curl, Node.js, Python, clang, make, CMake and ripgrep), including `node-pty` against that runtime. Set `$HOME`/`$PREFIX` consistently with the private Termux-style layout and use bash as the integrated terminal's default shell.
6. **Target and distribution:** retain `targetSdk 28` as instructed and distribute through GitHub Releases, not the Play Store. This stage does not establish that the requested all-files permission flow or executable bootstrap works on any particular Android release; verify those on devices before claiming support. Use immersive mode by default with `WindowInsetsControllerCompat` transient-bars-by-swipe behavior, edge-to-edge layout and an in-app setting to turn it off; the foreground notification also needs a user-visible stop action. Request a battery-optimization exemption where appropriate and document battery-optimization steps and the Android 12+ phantom-process limitation, without promising survival on every device.
7. **Device paths:** keep private bootstrap/home and user-data directories inside app storage. Create `/storage/emulated/0/Kodra` as the shared projects default and use real POSIX paths with the requested all-files access permission; add the `~/storage` link to shared storage. The owner chose Android's system picker for Open File/Open Folder, and the VS Code simple dialog for Save As, Select Folder and Git Clone, starting in Kodra. The native picker adapter must turn supported filesystem-backed document URIs into real paths; it must reject or clearly explain URI-only/non-filesystem providers rather than pass content URIs to the server as paths.
8. **Native bridge:** keep the bridge narrow and purpose-specific: Android intents, clipboard, secure token storage/authentication, notification/service controls, insets/IME and other required platform APIs. Read OAuth client IDs from ignored `local.properties` or environment variables; do not put IDs, tokens, keystores or SDK files in Git. Do not expose a general-purpose privileged JavaScript interface to arbitrary WebView content.
9. **Upstream patch boundary:** put new Android code under `kodra/` (including the Kotlin project and build glue), keep upstream edits limited to product/build integration, maintain a patch list, and provide a rebase script before the first non-documentation stage. Stage commits remain on the Arena-provided current branch; a separate branch per stage is not available in this workspace.

## Electron-only surface map

The Electron directories are platform-specific implementations, not the workbench UI as a whole. The browser/web build is the reuse path. Any feature not provided by the browser workbench or local server must be given an explicit native replacement or recorded as unavailable; it must not silently disappear.

| Source family inspected | Electron responsibility | Kodra replacement / limitation to verify |
| --- | --- | --- |
| `src/vs/code/electron-main/{main,app}.ts`; `src/vs/platform/{environment,lifecycle,launch,windows,window,protocol,menubar,globalKeybindings}/electron-*` | Desktop process startup, app/window lifecycle, native window creation, menu/protocol integration and OS-wide key handling. | Kotlin Activity/foreground service, Android intents, WebView and Android keyboard dispatch. Kodra is one Activity; auxiliary desktop windows and global OS key hooks have no direct equivalent and need an in-app/intent replacement or an explicit note. |
| `src/vs/code/electron-browser/workbench/`; `src/vs/workbench/electron-browser/`; `src/vs/platform/window/electron-browser/`; `src/vs/base/parts/sandbox/electron-browser/` | Desktop renderer bootstrap, preload-provided `window.vscode` globals, desktop workbench entry and Electron sandbox. | Use `src/vs/code/browser/workbench/` and the web sandbox. Preserve common editor/workbench code; do not load Electron preload scripts. Add Android-specific behavior at the WebView boundary. |
| `src/vs/base/parts/{contextmenu,ipc,sandbox}/electron-*`; `src/vs/platform/{ipc,sharedProcess,utilityProcess}/electron-*`; `src/vs/code/electron-utility/` | Electron IPC, utility/shared processes and native context-menu/sandbox plumbing. | REH's server/WebSocket channels for workbench and extension-host traffic; one supervised local server process instead of Electron's shared process; browser context menu plus long-press-to-context-menu. Any Android bridge is limited to named APIs. |
| `src/vs/platform/{dialogs,files,workspaces,backup,storage,userDataProfile,environment}/electron-*`; `src/vs/workbench/services/{dialogs,files,workspaces,storage,environment}/electron-browser/` | Native file dialogs and desktop paths, profiles, workspace and disk integration. | REH Node file services on real device paths, private app data plus shared Kodra projects. Per the owner's choice, Android's system picker opens files/folders and VS Code's non-native simple dialog handles Save As, Select Folder and Git Clone. The system-picker bridge must convert only supported filesystem-backed document URIs to POSIX paths and handle URI-only providers explicitly. |
| `src/vs/platform/{process,terminal,externalTerminal,debug,extensions,extensionManagement,remote}/electron-*`; `src/vs/workbench/services/{process,extensions,terminal,remote}/electron-browser/` | Desktop process/shell/PTY launch, extension-host setup, local Git discovery, native debugging/process utilities and remote connections. | REH owns the local extension host and Node process APIs; the normal xterm.js UI uses `node-pty` built for Android/bionic; the built-in Git extension uses the shipped bootstrap `git`. External terminals open by Intent when a compatible app exists; otherwise document the limitation. Do not replace the built-in Git UI. |
| `src/vs/platform/{encryption,github}/electron-*`; `src/vs/workbench/services/{encryption,github,secrets}/electron-browser/` | Desktop keychain/credential encryption and desktop GitHub authentication. | Kodra `github` authentication provider using GitHub Device Flow, Android Keystore AES-GCM token storage and a Git credential helper. This is new native code and remains unverified until Android tests pass. |
| `src/vs/platform/{clipboard,accessibility,keyboardLayout,gpu,webview,browserView}/electron-*`; `src/vs/workbench/services/{clipboard,keybinding,accessibility,browserView}/electron-browser/` | Electron clipboard, native keyboard/accessibility/GPU and embedded-view integration. | Android WebView/Chromium plus focused bridges to `ClipboardManager`, IME and platform accessibility. Keep extension webviews on the web implementation. BrowserView/external-content behavior must be origin-restricted and either use an Intent or be listed as unsupported. |
| `src/vs/platform/{telemetry,update,remoteTunnel,meteredConnection,customizationMarketplace}/electron-*`; `src/vs/workbench/services/{telemetry,update,userDataSync,tunnel}/electron-browser/` | Desktop telemetry/update/cloud-sync/tunnel and connectivity integrations. | Telemetry and crash reporting off; no Microsoft Marketplace, Settings Sync, Copilot, tunnels or in-app updater. GitHub Releases are the distribution update path. Use Android `ConnectivityManager` only if a real workbench service needs metered-network state. |
| `src/vs/workbench/contrib/*/electron-browser/` and `src/vs/sessions/**/electron-browser/` | Feature-specific desktop overrides, including browser views, dialogs/files, external terminal, issue reporting, keybindings, localization, logs, MCP, remote/tunnels, screenshot/process tools, sessions/chat/voice, tasks, terminal, webviews and workspaces. | Build the browser/server variants where present. Replace OS-facing actions with the Android mechanisms above. Do not bundle or activate Microsoft-hosted Copilot/voice/tunnel/session integrations. For a feature with no browser implementation, record the feature and closest replacement in this file before disabling it. Test developer commands, menus, keyboard shortcuts, extension webviews and workbench settings independently. |
| Any `*/test/electron-*` directory | Electron-only tests and fixtures, not runtime features. | Exclude test code from APK/runtime packages; cover corresponding behavior with web/server CI and Android instrumentation/device tests. |

This is a source-family map for the Electron-specific implementations found by scanning `src/vs`; it is not an assertion that every desktop feature already has a working web counterpart. The exact Android gaps are to be updated here as each feature is exercised at its stage gate.

## Acceptance baseline (all unverified)

- Keep the desktop workbench composition and interactions: activity bar, sidebar, editor groups/tabs, panel, status bar, Command Center, command palette, menus, themes, icons, settings, Developer commands and Source Control. Touch support is additive; do not create an Android-only redesign.
- Preserve all built-in language extensions, TextMate grammars and semantic highlighting. At Stage 3, add the supplied settings example unchanged as `docs/sample-settings.json` and test Settings UI ↔ `settings.json` round-tripping, including settings for extensions that are not installed.
- Keep the built-in Git extension and graph/timeline UI. Use the real bootstrap Git for clone/fetch/pull/push/branch/merge/stash; use Kodra's `github` auth provider and credential helper for HTTPS credentials. No custom Git UI or REST-based replacement for Git operations.
- Bundle only the named upstream extensions after pinning sources and checking their licenses: `esbenp.prettier-vscode`, `PKief.material-icon-theme`, `ritwickdey.LiveServer` (localhost; open the Android default browser by Intent), and `ms-python.python` without Pylance. Do not redistribute proprietary `ms-vscode.cpptools` language-server/debugger binaries; provide bootstrap clangd/LLDB and document differences. Check the license of `github/vscode-pull-request-github` before bundling it. Port `icrawl.discord-vscode` only at its separate gate, preserving its settings/commands and using the requested native Discord Social SDK; ask for the application ID and SDK AAR only then. Record each decision in `docs/EXTENSIONS.md`.
- Tablet layout remains desktop-like. Phone portrait may collapse the sidebar by default; every deviation must be documented. Verify long-press context menus, pinch zoom, an extra-keys row (Esc, Tab, Ctrl, Alt and arrows), hardware shortcuts, IME composition, edge-to-edge/cutouts and keyboard-driven resize on devices. Enable WebView debugging only in debug builds and document `chrome://inspect` access.
- The owner chose Android's system picker for Open File/Open Folder, and the VS Code simple dialog for Save As/Select Folder/Git Clone. The system-picker bridge must produce usable POSIX paths for supported storage providers; unsupported content-only URIs must fail with a clear explanation rather than be treated as local paths.
- Full-screen/insets, service notification, stop action, background reconnection, process restart, wake lock and per-device battery/phantom-process instructions require explicit CI/device evidence before being called working.

## Build and runtime findings

- `build/gulpfile.reh.ts` defines `vscode-reh` and `vscode-reh-web` tasks. Its target list includes `linux-arm64` but no Android/bionic target. The Linux task downloads and packages the upstream Linux Node binary, native extensions and platform dependencies; this is a Linux build, not an Android executable.
- `build/azure-pipelines/linux/steps/product-build-linux-compile.yml` builds the REH and REH-web packages and checks Linux `GLIBC`/`GLIBCXX` requirements. `.github/workflows/kodra-reh.yml` builds Linux ARM64 REH and REH-web directories; successful run `45707121359` verified both package identities/architectures, the executable launcher, the absent tunnel metadata/CLI and Copilot extension, uploaded both artifacts, and then ran both packaged servers on a native ARM64 runner to check the loopback bind, port-0 handoff, token enforcement and served workbench content. The artifact and startup gates are evidenced, but these are Linux/glibc packages only. Limited local source/transpile/type-check and server-test evidence is recorded above. This checkout still has no Android Gradle project or Android SDK/Java toolchain.
- `vscode-reh-web` builds the Node server and serves `src/vs/code/browser/workbench/workbench.html`. `vscode-web` (`build/gulpfile.vscode.web.ts`) is a browser client package, not the local extension-host server. The separate `build/next/MOBILE.md` target is an isolated **Agents** web package; it is not a native Android editor shell and is not the Kodra build target.
- `remote/package.json` pins `nativeBuild.target=24.22.1` and 51 deps. The closure is now fully triaged in `kodra/deps/INVENTORY.md` (from `build/kodra/inventoryNativeDeps.ts`): `rebuild=5` (`node-pty`, `@parcel/watcher`, `@vscode/native-watchdog`, `@vscode/spdlog`, `@vscode/sqlite3` — NDK r26+ `aarch64-linux-android28`), `replace=2` (`kerberos`→omit, `ripgrep-universal`→bootstrap `rg`), `omit=2` (Windows-only), `binary=42` (pure JS/WASM, keep). Unknown=0. See `kodra/BOOTSTRAP.md` + `kodra/TOOLCHAIN.md` for the Termux-style `$PREFIX` and NDK build spec; `kodra/prefix-layout.json` declares the on-device env (`HOME`, `PREFIX`, `LD_LIBRARY_PATH`). CI now asserts the inventory stays in sync.
- `src/vs/server/node/serverEnvironmentService.ts` exposes host, port, token-file, telemetry and data-directory options. `serverConnectionToken.ts` supports a mandatory token from a file and validates each request. `remoteExtensionHostAgentServer.ts` prints the token in its startup URL; server startup output therefore needs redaction at the Kotlin process boundary. The exact `127.0.0.1` binding and port-0 handoff still require a packaged-server integration test.
- `src/vs/code/browser/workbench/workbench.html` already has mobile metadata but sets `user-scalable=no`; pinch zoom is deliberately disabled in this template. Touch long-press, pinch-to-zoom, IME composition, cutouts, keyboard resizing and compact phone layout are acceptance tests, not verified properties of the existing page.
- `remote/web/package.json` includes browser workbench libraries (including xterm.js and TextMate); it is not the source of a native runtime or terminal process. Android/bionic native components must remain local to the APK/bootstrap.

## Branding, services and licensing findings

`product.json` now carries Kodra identity (`Kodra`, `kodra`, `.kodra`, Kodra server/data names, the `kodra` URL protocol, and canonical Kodra license/report links) and disabled telemetry. It restores pinned built-in JavaScript debug/profile extensions: `ms-vscode.js-debug-companion` 1.1.3, `ms-vscode.js-debug` 1.140.1 and `ms-vscode.vscode-js-profile-table` 1.0.11. Each exact upstream tag has an MIT license. The default Copilot agent, its account endpoints/scopes, voice endpoint, and external Microsoft webview CDN template have been removed. `src/vs/base/common/product.ts` now models `defaultChatAgent` as optional; the default-account service skips provider setup and opens its initialization barrier when it is absent, and Copilot onboarding/status UI is gated. Copilot-specific gallery/uninstall paths and the About version display are also guarded. The REH packager omits the built-in `extensions/copilot` extension and its ripgrep shim when the default agent is absent; Agent Host now also registers the Copilot provider only for products that configure `defaultChatAgent`. The owner confirmed `https://github.com/Sonix-Devs/Kodra` as the canonical Kodra repository URL for product links.

This does **not** yet prove that all Copilot/Microsoft-hosted code is absent: `remote/package.json`, the server/workbench, and Agent Host still contain shared Copilot code/dependencies. The source `product.json` retains `tunnelApplicationName` and Win32 tunnel mutex metadata for desktop packaging consumers. The REH packager now strips the tunnel application name and Win32 tunnel mutex fields from generated server product metadata when `tunnelApplicationConfig` is absent, while leaving the source product file intact. The updated workflow also asserts that the REH packages contain neither those metadata keys nor `bin/kodra-tunnel` or `extensions/copilot`; runs `45676800604`, `45678058972`, `45688370992` and `45707121359` passed those assertions and additionally ran both packaged servers. Local archive extraction and outbound network observation remain blocked in this sandbox. The product has no `extensionsGallery`, explicit updater URL, or crash-reporter endpoint; the Extensions view and network behavior have not been runtime-verified. Stage 1 must inspect the finished packages, verify the Extensions view has no Marketplace categories/results, and establish that no optional path contacts an unwanted service. No service may be inferred safe solely from a missing `product.json` key.

Keep the root MIT `LICENSE.txt` and `ThirdPartyNotices.txt`. Stage 0 did not bundle or license-review extensions. The three restored JavaScript debug/profile extensions are pinned in `product.json`, and GitHub's license metadata at each exact upstream tag (`v1.1.3`, `v1.140.1`, `v1.0.11`) identifies them as MIT; complete the extension/source/notice inventory for the remaining requested bundles before packaging. In particular, the requested Git binary brings GPL obligations; keep Kodra source public and document bundled components and license obligations in README/docs before release.

## Requested Git experience audit

The built-in Source Control Graph is in core workbench code, not a custom Git UI: `src/vs/workbench/contrib/scm/browser/scm.contribution.ts` registers the “Graph” view inside the Source Control container. In this checkout it is visible when `scm.historyProviderCount` is nonzero and does not set `hideByDefault`; Git supplies a history provider through `extensions/git/src/historyProvider.ts`. The inspected `scm.graph.*` settings (`pageOnScroll`, `pageSize`, `badges`, incoming/outgoing changes) tune graph behavior; none is an enable/disable switch. Therefore no extra graph-enable setting is identified for this revision. Keep the built-in Git extension and its history provider intact, and verify graph visibility with a real repository and the packaged Git binary at the Stage 4 gate. Timeline remains the normal workbench Timeline view/provider path.

## Gate 0 report

### Done

- Audited the Electron startup/renderer/shared-process areas, REH server entrypoints and token handling, the REH/web build tasks and package dependencies, `remote/`, `product.json`, and the Source Control Graph registration.
- Recorded the Android shell/runtime architecture, an Electron-to-Android replacement map, the Android ABI/build risks, branding/service work, and stage progress in this document.

### Verified (static evidence only)

- The browser workbench is a separate entry from the Electron workbench and uses the shared web workbench (`src/vs/code/browser/workbench/workbench.ts`).
- REH/web Gulp targets include Linux ARM64 but not Android/bionic; the Linux package incorporates upstream Node/native dependencies (`build/gulpfile.reh.ts`, `remote/package.json`).
- The server supports explicit host/port/token-file options; its default token persists and its startup URL contains the token (`src/vs/server/node/serverEnvironmentService.ts`, `serverConnectionToken.ts`, `remoteExtensionHostAgentServer.ts`).
- The source tree contains no Android Gradle project, and this sandbox has no Java, Gradle, Android SDK or `adb`. No Android APK, Android runtime, or device behavior has been verified; limited Stage 1 local validation is recorded above.
- The Source Control Graph view has no dedicated enable setting in the inspected source and is registered for visibility when a history provider exists (`src/vs/workbench/contrib/scm/browser/scm.contribution.ts`).

## Stage 2 verification (2026-11-26 — scaffold complete)

- `node build/kodra/inventory-to-markdown.mjs` regenerates `kodra/deps/INVENTORY.md` and CI gates it with `git diff --exit-code`; latest file covers all **51** deps from `remote/package.json` with **0 unknown** (`rebuild=5, replace=2, omit=2, binary=42`).
- `kodra/TOOLCHAIN.md` specifies the NDK r26+ `aarch64-linux-android28` build for Node 24.22.1 and the 5 `rebuild` addons (`node-pty`, `@parcel/watcher`, `@vscode/native-watchdog`, `@vscode/spdlog`, `@vscode/sqlite3`) with `android_ndk_path` + `termux-elf-cleaner` relocatable `$PREFIX`. `kerberos` is documented as omitted (Enterprise GSSAPI), `ripgrep-universal` is replaced by bootstrap-built `rg`.
- `kodra/prefix-layout.json` locks `$PREFIX=/data/data/dev.sonixdevs.kodra/files/usr`, `$HOME=/data/data/dev.sonixdevs.kodra/files/home`, `TMPDIR`, `LD_LIBRARY_PATH` and the SAF bridge for `/storage/emulated/0/Kodra`.
- `git diff --check` still passes; `kodra/deps` triage is now **zero-unknown** (previously 41). No bionic Node or native `.node` has been built — this sandbox has no NDK, and no APK/device run exists (see *Not proven* below).

**Not proven by this scaffold:** no NDK build has executed, no `prefix` has been installed on a device, no `node-pty` fork has run on bionic. Device CI must still prove `$PREFIX/bin/node --version`, `$PREFIX/bin/bash -c 'echo ok'` and a `node-pty` PTY smoke under the app UID (see `kodra/BOOTSTRAP.md` § Verification). The glibc Linux REH package remains the reference only.

### Blocked / unverified

- No Android build, bionic runtime, `node-pty`, Git binary, server launch, WebView security/origin handling, foreground-service survival, permission flow, keyboard/IME, touch, picker, Git UI, or on-device behavior can be verified from this audit.
- The Linux ARM64 build is not interchangeable with Android/bionic. The complete native dependency closure and feasibility of rebuilding it remain to be proven in Stage 2 CI/device work.
- The owner selected Android's system picker for Open File/Open Folder and the VS Code simple dialog for Save As/Select Folder/Git Clone. The remaining implementation risk is SAF URI-to-POSIX path mapping: only filesystem-backed paths may be passed to the local server. Verify the supported providers on device and explain/reject content-only URIs without data loss.

### Owner decisions recorded

The answers below resolve the open product/distribution questions. Stage 1 has been approved and is now in progress; work is limited to rebranding, disabling Microsoft-hosted services, and the Linux ARM64 REH/REH-web GitHub Actions build.

1. Confirmed **targetSdk 28 and GitHub Releases only**, not the Play Store.
2. Chose Android's system picker for Open File/Open Folder; chose the VS Code simple dialog for Save As, Select Folder and Git Clone.
3. Confirmed `https://github.com/Sonix-Devs/Kodra` as the canonical product-link URL. No client ID, keystore, OAuth secret, Discord ID or SDK file is needed at Stage 0; request these only at their relevant gates.

- Owner decision 2026-11-27: applicationId is `dev.sonixdevs.kodra`; canonical repository is https://github.com/Sonix-Devs/Kodra. CI uses Android 35, Gradle 8.9, android-actions/setup-android@v4.0.4.
