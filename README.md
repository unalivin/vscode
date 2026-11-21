# Kodra

Kodra is an Android-focused code editor based on **Code - OSS**. The project reuses the shared workbench and browser/server code, with a planned native Android shell and a separately built Android/bionic runtime.

> **Porting status:** Stage 0 is complete and Stage 1 is in progress. The Linux ARM64 REH/REH-web workflow succeeded in [Actions run 44833150751](https://github.com/unalivin/vscode/actions/runs/44833150751), building, verifying, and uploading both packages. A follow-up package-content and service-path review is still in progress. These are Linux/glibc packages, not Android/bionic binaries and not an APK. Android runtime, shell, device behavior, and release support are not yet verified.

Planned canonical repository: <https://github.com/unalivin/kodra> (not currently resolvable in GitHub; this source tree currently lives at <https://github.com/unalivin/vscode>).

## Current scope

- Workbench/browser and local REH/web product cleanup, including Kodra branding.
- The built-in JavaScript debug/profile extensions are restored at pinned versions: `ms-vscode.js-debug` 1.140.1, `ms-vscode.js-debug-companion` 1.1.3 and `ms-vscode.vscode-js-profile-table` 1.0.11. Their exact upstream tags are MIT-licensed.
- Kodra's product configuration omits the Microsoft Marketplace/Settings Sync endpoints, the default Copilot agent and account endpoints, the voice endpoint, telemetry destinations, and the external Microsoft webview CDN. Shared upstream Agent Host/extension code and dependencies remain in the source tree, but Agent Host registers the Copilot provider only when `defaultChatAgent` is configured. Desktop tunnel metadata is retained for installer/CLI consumers; REH packaging omits the tunnel CLI name and Windows tunnel mutex metadata when no tunnel configuration exists. Package-content and outbound-service behavior still require verification, so this is not proof that every optional service path is absent or unreachable.
- Browser webviews use a loopback-only, per-webview `*.localhost` origin and a small allowlisted shell route in the local server. Resource access remains mediated by the workbench/service worker. This design still requires end-to-end browser and Android WebView verification.
- Android packaging and its bionic native dependencies are later stages. A Linux ARM64 server package must not be treated as an Android executable.

See [`PORTING_NOTES.md`](PORTING_NOTES.md) for the staged plan, architecture, audit findings, and verification gates. The Android app is not ready for installation or general use.

## Linux ARM64 REH artifacts

[Successful Actions run 44833150751](https://github.com/unalivin/vscode/actions/runs/44833150751) uploaded two 14-day artifacts:

- `vscode-reh-linux-arm64` — the Linux ARM64 remote extension host server (184,699,134 bytes).
- `vscode-reh-web-linux-arm64` — the browser workbench/web server assets (217,723,155 bytes).

That run checked the packaged Node binary's AArch64 ELF header and Kodra product identity before upload. A pending workflow change asserts that tunnel metadata, the tunnel CLI, and the built-in Copilot extension are absent; those assertions have not run yet, and local archive extraction remains blocked by the sandbox's download-host allowlist. Both packages target Linux/glibc and are build evidence only; do not run them as Android/bionic binaries.

## Upstream and license

Kodra is based on the open-source [Code - OSS](https://github.com/microsoft/vscode) source tree and retains its MIT license. The upstream source's copyright notices and license files are preserved. Kodra-specific changes and distribution are intended for the planned canonical repository above; development currently continues in [unalivin/vscode](https://github.com/unalivin/vscode).

## Contributions and porting decisions

This repository is being ported in gated stages. The next stages depend on Android ABI work and real-device verification; please consult `PORTING_NOTES.md` before treating a planned feature as available. Other requested extension bundles and their license/notice review remain separate gates.
