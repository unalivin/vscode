# Kodra

Kodra is a native Android application that runs the Visual Studio Code workbench on the
device. It is not a website, a remote workspace or a browser tab: a Kotlin shell starts a
local VS Code server on `127.0.0.1` and renders the real browser workbench in a full-screen
`WebView`, while a Termux-style bootstrap under the app's private storage provides the
POSIX environment (bash, git, node, python, clang…) the workbench expects.

Kodra is based on [Code - OSS](https://github.com/microsoft/vscode) and keeps its MIT
license. It is distributed through GitHub Releases, never the Play Store.

- Package / namespace: `dev.sonixdevs.kodra`
- Bootstrap prefix: `/data/data/dev.sonixdevs.kodra/files/usr`
- Default projects folder: `/storage/emulated/0/Kodra`

## Status

Statuses are the only ones used in this repository: **Done (evidence: …)** means a CI run
or an executed test backs the claim, **Scaffolded, unverified** means the code exists and
no build has exercised it, **Blocked on owner** means it needs a secret, a device or a
decision from the owner.

| Area | Status | Evidence |
| --- | --- | --- |
| Product identity, Microsoft-service gating (`product.json`) | Done (evidence: [run 46038357337](https://github.com/Sonix-Devs/Kodra/actions/runs/46038357337)) | `kodra-reh.yml` asserts the packaged product has `enableTelemetry: false`, no `extensionsGallery`/`agentSdks`/`telemetryConnectionString`/`aiConfig`, an empty `cliDownloadUrlBase`, and no tunnel metadata; see `PORTING_NOTES.md` § Outbound-service review |
| Linux ARM64 REH + REH-web packages | Done (evidence: [run 46038357337](https://github.com/Sonix-Devs/Kodra/actions/runs/46038357337) on `9d320a33`) | Both jobs succeeded: packages built and asserted, then each packaged server was started on a native ARM64 runner and checked for loopback bind, port-0 handoff and token enforcement. Artifacts: `vscode-reh-linux-arm64` 186,432,472 B, `vscode-reh-web-linux-arm64` 219,456,542 B, `kodra-host-inventory` 2,809 B |
| Android debug APK | Done (evidence: [run 46038357171](https://github.com/Sonix-Devs/Kodra/actions/runs/46038357171) on `9d320a33`) | `assembleDebug` and `lintDebug` succeeded; artifact `kodra-debug-apk` 4,829,579 B. The APK has **not** been installed on any device, and it contains no bootstrap or REH package yet |
| Bionic Node + Termux-style bootstrap | Scaffolded, unverified | Design and dependency triage only (`kodra/BOOTSTRAP.md`, `kodra/TOOLCHAIN.md`, `kodra/deps/INVENTORY.md`); no NDK build has run |
| Terminal (xterm.js + node-pty) | Scaffolded, unverified | The terminal is REH's own; it needs the bionic `node-pty` build, which does not exist yet |
| Built-in Git on the bundled `git` | Scaffolded, unverified | `GitBridge` sets `safe.directory`; no git binary has been built or run on a device |
| GitHub sign-in (Device Flow + Keystore) | Scaffolded, unverified | `DeviceAuthFlow`/`GithubAuth`; needs an OAuth client ID and a device to test, and the `github` workbench authentication provider is not written yet |
| Release APK signing | Scaffolded, unverified | `kodra-release.yml` fails without `KODRA_KEYSTORE_BASE64`; no signed release has been produced |
| Bundled extensions | Scaffolded, unverified | Only the three MIT js-debug/profile extensions are pinned in `product.json`; the rest are reviewed in `docs/EXTENSIONS.md` |
| Discord presence (`icrawl.discord-vscode`) | Blocked on owner | Needs the Discord application ID and `discord_partner_sdk.aar` |
| Touch, immersive mode, IME, phone layout | Scaffolded, unverified | Code exists (`ExtraKeysView`, `InsetsBridge`); every claim needs a physical device |
| Background survival (foreground service, wake lock) | Scaffolded, unverified | `KodraService`; OEM process killing cannot be promised, see `docs/BATTERY.md` |

**Kodra is not usable yet.** The debug APK builds in CI, but nothing in this repository has
ever run on an Android device, the bootstrap has never been compiled, and the APK contains
no server to start — installing it today would show a "server failed to start" notification.

## Documentation

| Document | Contents |
| --- | --- |
| [`PORTING_NOTES.md`](PORTING_NOTES.md) | Staged plan, architecture decisions, Electron-to-Android surface map, CI history, honest per-stage status |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | How the Activity, service, server, bootstrap and bridges fit together |
| [`docs/EXTENSIONS.md`](docs/EXTENSIONS.md) | Which extensions are bundled, at which tag, under which license |
| [`docs/BATTERY.md`](docs/BATTERY.md) | Battery-optimisation and phantom-process instructions for users |
| [`kodra/BOOTSTRAP.md`](kodra/BOOTSTRAP.md) | Bootstrap package set, bionic Node build and the `$PREFIX` layout |
| [`kodra/TOOLCHAIN.md`](kodra/TOOLCHAIN.md) | NDK toolchain and native-addon rebuild matrix |
| [`kodra/RELEASE.md`](kodra/RELEASE.md) | Release process, signing secrets and the device verification checklist |
| [`kodra/android/README.md`](kodra/android/README.md) | Building the app locally, `chrome://inspect` setup |

## Repository layout

Upstream Code - OSS sources are kept as close to untouched as the port allows; Kodra's own
code lives in `kodra/` and its build glue in `build/kodra/`.

```
kodra/android/        Kotlin app (single Activity + foreground service + bridges)
kodra/deps/           Triage of every native dependency: rebuild / replace / omit / keep
build/kodra/          Inventory tooling and the packaged-server smoke test
docs/                 Architecture, extensions, battery and settings reference
```

## Building

The app builds with Gradle 8.9, AGP 8.7.3, Kotlin 1.9.24, `compileSdk 35`, `minSdk 21`,
`targetSdk 28`:

```sh
cd kodra/android
cp local.properties.example local.properties   # sdk.dir; never commit this file
gradle :app:assembleDebug
```

CI runs the same build in [`.github/workflows/kodra-android.yml`](.github/workflows/kodra-android.yml)
and uploads the APK as an artifact. Secrets — keystore, OAuth client ID, Discord SDK — are
supplied through `local.properties`, environment variables or repository secrets and are
never committed.

## Licensing

Kodra keeps the upstream MIT license and `ThirdPartyNotices.txt`. Additional obligations
are recorded per component in [`docs/EXTENSIONS.md`](docs/EXTENSIONS.md) and
`PORTING_NOTES.md`; in particular the bundled `git` binary is GPL-2.0 and the bootstrap
packages carry their own licenses, which is why Kodra's own source stays public.
