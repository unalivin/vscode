# Bootstrap inventory (generated — do not edit)
Generated from remote/package.json nativeBuild 24.22.1 @ https://nodejs.org/dist

| package | version | class | notes |
|---|---|---|---|
| `@devcontainers/cli` | `0.88.0` | binary | JS CLI for devcontainers; keep, docker gap is expected on Android. |
| `@hpke/core` | `^1.9.0` | binary | Pure JS HPKE; keep. |
| `@microsoft/1ds-core-js` | `^3.2.13` | binary | 1DS telemetry JS (inert, enableTelemetry:false); keep. |
| `@microsoft/1ds-post-js` | `^3.2.13` | binary | 1DS post channel JS; keep. |
| `@microsoft/copilot-sdk` | `2.0.1` | binary | Copilot SDK JS wrapper; gated by defaultChatAgent absent — keep. |
| `@vscode/copilot-api` | `^0.5.2` | binary | Copilot API shim; gated — keep. |
| `@vscode/deviceid` | `^0.1.1` | binary | Device ID; Linux reads /etc/machine-id, Android falls back to ANDROID_ID — verify on device. |
| `@vscode/diff` | `0.0.2-145` | binary | Pure JS diff; keep. |
| `@vscode/fs-copyfile` | `2.0.0` | binary | fs.copyFile wrapper with copy_file_range fast-path; bionic fallback is plain copy — keep. |
| `@vscode/iconv-lite-umd` | `0.7.1` | binary | Pure JS charset conversion; keep. |
| `@vscode/proxy-agent` | `^0.46.0` | binary | PAC/proxy JS agent; keep. |
| `@vscode/sandbox-runtime` | `0.0.1` | binary | JS sandbox helpers; keep. |
| `@vscode/tree-sitter-wasm` | `^0.3.1` | binary | WASM tree-sitter; keep. |
| `@vscode/vscode-languagedetection` | `1.0.23` | binary | WASM language detection; keep. |
| `@xterm/addon-clipboard` | `^0.3.0-beta.335` | binary | xterm.js addon JS; keep. |
| `@xterm/addon-image` | `^0.10.0-beta.332` | binary | xterm.js addon JS; keep. |
| `@xterm/addon-ligatures` | `^0.11.0-beta.331` | binary | xterm.js addon JS; keep. |
| `@xterm/addon-progress` | `^0.3.0-beta.331` | binary | xterm.js addon JS; keep. |
| `@xterm/addon-search` | `^0.17.0-beta.331` | binary | xterm.js addon JS; keep. |
| `@xterm/addon-serialize` | `^0.15.0-beta.331` | binary | xterm.js addon JS; keep. |
| `@xterm/addon-unicode11` | `^0.10.0-beta.331` | binary | xterm.js addon JS; keep. |
| `@xterm/addon-webgl` | `^0.20.0-beta.330` | binary | xterm.js addon JS + WebGL/canvas fallback; keep. |
| `@xterm/headless` | `^6.1.0-beta.335` | binary | Pure JS xterm headless; keep. |
| `@xterm/xterm` | `^6.1.0-beta.337` | binary | xterm.js core JS; keep. |
| `cookie` | `^0.7.0` | binary | JS cookie parser; keep. |
| `detect-libc` | `^2.1.2` | binary | Detects glibc vs musl; on bionic returns unknown — harmless, keep. |
| `http-proxy-agent` | `^7.0.0` | binary | JS proxy agent; keep. |
| `https-proxy-agent` | `^7.0.2` | binary | JS proxy agent; keep. |
| `jschardet` | `3.1.4` | binary | JS charset detection; keep. |
| `katex` | `^0.16.22` | binary | JS math rendering; keep. |
| `libsodium-wrappers` | `^0.8.4` | binary | Sodium wrappers with WASM fallback; keep. |
| `minimist` | `^1.2.8` | binary | JS arg parser; keep. |
| `ssh2` | `^1.16.0` | binary | Pure JS SSH2 via Node crypto (OpenSSL in bionic Node); keep. |
| `tar` | `^7.5.20` | binary | JS tar; keep. |
| `tas-client` | `0.4.6` | binary | TAS experimentation JS client; keep (inert). |
| `vscode-oniguruma` | `1.7.0` | binary | Oniguruma via WASM (onig.wasm) with native fallback — force WASM on Android; keep. |
| `vscode-regexpp` | `^3.1.0` | binary | JS regex parser; keep. |
| `vscode-textmate` | `^9.3.2` | binary | JS TextMate; keep. |
| `ws` | `^8.19.0` | binary | JS WebSocket; keep. |
| `yauzl` | `^3.3.1` | binary | JS zip reader; keep. |
| `yazl` | `^2.4.3` | binary | JS zip writer; keep. |
| `zod` | `^4.4.3` | binary | JS schema validation; keep. |
| `@vscode/windows-process-tree` | `^0.8.0` | omit | Windows-only. |
| `@vscode/windows-registry` | `^1.3.0` | omit | Windows-only. |
| `@parcel/watcher` | `^2.5.6` | rebuild | native watcher; rebuild or polling fallback. |
| `@vscode/native-watchdog` | `^1.4.6` | rebuild | watchdog/ptrace; bionic rebuild. |
| `@vscode/spdlog` | `^0.15.8` | rebuild | native logger; bionic rebuild or replace. |
| `@vscode/sqlite3` | `5.1.12-vscode` | rebuild | native sqlite; bionic toolchain or omit (lose workspace DB). |
| `node-pty` | `^1.2.0-beta.18` | rebuild | ABI: native addon against bionic Node 24.22.1; glibc prebuild unusable. |
| `@vscode/ripgrep-universal` | `^1.18.0` | replace | prebuilt glibc/musl rg; ship bootstrap-built rg. |
| `kerberos` | `2.1.1` | replace | GSSAPI/Kerberos rare on Android; omit, document Enterprise loss. |

_Total deps: 51; by class: rebuild=5, replace=2, omit=2, binary=42_

> Linux/glibc REH closure is NOT shippable on bionic. This file is the Stage-2 source of truth; CI will diff it against generated output. Stage 2 declares **zero unknown** — every dep has a documented bionic disposition.
