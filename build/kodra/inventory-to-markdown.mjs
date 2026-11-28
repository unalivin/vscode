import fs from 'fs';
import path from 'path';
const repoRoot = path.resolve(import.meta.dirname, '../..');
const pkg = JSON.parse(fs.readFileSync(path.join(repoRoot, 'remote/package.json'), 'utf8'));

// Full triage: 51 deps from remote/package.json. Classification:
// - rebuild: native addon must be rebuilt with NDK bionic Node 24.22.1
// - replace: prebuilt binary unsuitable for bionic — ship bootstrap replacement
// - omit: Windows-only, not applicable on Android
// - binary: pure JS / WASM; keep as-is (verify on device where noted)
const rules = {
  'node-pty': ['rebuild','ABI: native addon against bionic Node 24.22.1; glibc prebuild unusable.'],
  '@parcel/watcher': ['rebuild','native watcher; rebuild or polling fallback.'],
  '@vscode/native-watchdog': ['rebuild','watchdog/ptrace; bionic rebuild.'],
  '@vscode/spdlog': ['rebuild','native logger; bionic rebuild or replace.'],
  '@vscode/sqlite3': ['rebuild','native sqlite; bionic toolchain or omit (lose workspace DB).'],

  '@vscode/ripgrep-universal': ['replace','prebuilt glibc/musl rg; ship bootstrap-built rg.'],
  'kerberos': ['replace','GSSAPI/Kerberos rare on Android; omit, document Enterprise loss.'],

  '@vscode/windows-process-tree': ['omit','Windows-only.'],
  '@vscode/windows-registry': ['omit','Windows-only.'],

  // Pure JS / WASM — keep
  '@devcontainers/cli': ['binary','JS CLI for devcontainers; keep, docker gap is expected on Android.'],
  '@hpke/core': ['binary','Pure JS HPKE; keep.'],
  '@microsoft/1ds-core-js': ['binary','1DS telemetry JS (inert, enableTelemetry:false); keep.'],
  '@microsoft/1ds-post-js': ['binary','1DS post channel JS; keep.'],
  '@microsoft/copilot-sdk': ['binary','Copilot SDK JS wrapper; gated by defaultChatAgent absent — keep.'],
  '@vscode/copilot-api': ['binary','Copilot API shim; gated — keep.'],
  '@vscode/deviceid': ['binary','Device ID; Linux reads /etc/machine-id, Android falls back to ANDROID_ID — verify on device.'],
  '@vscode/diff': ['binary','Pure JS diff; keep.'],
  '@vscode/fs-copyfile': ['binary','fs.copyFile wrapper with copy_file_range fast-path; bionic fallback is plain copy — keep.'],
  '@vscode/iconv-lite-umd': ['binary','Pure JS charset conversion; keep.'],
  '@vscode/proxy-agent': ['binary','PAC/proxy JS agent; keep.'],
  '@vscode/sandbox-runtime': ['binary','JS sandbox helpers; keep.'],
  '@vscode/tree-sitter-wasm': ['binary','WASM tree-sitter; keep.'],
  '@vscode/vscode-languagedetection': ['binary','WASM language detection; keep.'],
  '@xterm/addon-clipboard': ['binary','xterm.js addon JS; keep.'],
  '@xterm/addon-image': ['binary','xterm.js addon JS; keep.'],
  '@xterm/addon-ligatures': ['binary','xterm.js addon JS; keep.'],
  '@xterm/addon-progress': ['binary','xterm.js addon JS; keep.'],
  '@xterm/addon-search': ['binary','xterm.js addon JS; keep.'],
  '@xterm/addon-serialize': ['binary','xterm.js addon JS; keep.'],
  '@xterm/addon-unicode11': ['binary','xterm.js addon JS; keep.'],
  '@xterm/addon-webgl': ['binary','xterm.js addon JS + WebGL/canvas fallback; keep.'],
  '@xterm/headless': ['binary','Pure JS xterm headless; keep.'],
  '@xterm/xterm': ['binary','xterm.js core JS; keep.'],
  'cookie': ['binary','JS cookie parser; keep.'],
  'detect-libc': ['binary','Detects glibc vs musl; on bionic returns unknown — harmless, keep.'],
  'http-proxy-agent': ['binary','JS proxy agent; keep.'],
  'https-proxy-agent': ['binary','JS proxy agent; keep.'],
  'jschardet': ['binary','JS charset detection; keep.'],
  'katex': ['binary','JS math rendering; keep.'],
  'libsodium-wrappers': ['binary','Sodium wrappers with WASM fallback; keep.'],
  'minimist': ['binary','JS arg parser; keep.'],
  'ssh2': ['binary','Pure JS SSH2 via Node crypto (OpenSSL in bionic Node); keep.'],
  'tar': ['binary','JS tar; keep.'],
  'tas-client': ['binary','TAS experimentation JS client; keep (inert).'],
  'vscode-oniguruma': ['binary','Oniguruma via WASM (onig.wasm) with native fallback — force WASM on Android; keep.'],
  'vscode-regexpp': ['binary','JS regex parser; keep.'],
  'vscode-textmate': ['binary','JS TextMate; keep.'],
  'ws': ['binary','JS WebSocket; keep.'],
  'yauzl': ['binary','JS zip reader; keep.'],
  'yazl': ['binary','JS zip writer; keep.'],
  'zod': ['binary','JS schema validation; keep.'],
};

// Locale-independent ordering: `localeCompare` changes order with the CI runner's
// ICU data and LANG, which would make the committed file differ between machines.
const compareAscii = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

const deps = pkg.dependencies;
const rows = Object.entries(deps).map(([name,ver])=>{
  const r=rules[name];
  if (!r) throw new Error(`Missing triage for ${name} — update inventory-to-markdown.mjs`);
  return {name, ver, klass:r[0], reason:r[1]};
}).sort((a,b)=>compareAscii(a.klass,b.klass)||compareAscii(a.name,b.name));

const md = [`# Bootstrap inventory (generated — do not edit)`,
`Generated from remote/package.json nativeBuild ${pkg.nativeBuild.target} @ ${pkg.nativeBuild.disturl}`,
'',
'| package | version | class | notes |',
'|---|---|---|---|',
...rows.map(r=>`| \`${r.name}\` | \`${r.ver}\` | ${r.klass} | ${r.reason} |`),
'',
`_Total deps: ${rows.length}; by class: ${['rebuild','replace','omit','binary'].map(k=>`${k}=${rows.filter(r=>r.klass===k).length}`).join(', ')}_`,
'',
'> Linux/glibc REH closure is NOT shippable on bionic. This file is the Stage-2 source of truth; CI will diff it against generated output. Stage 2 declares **zero unknown** — every dep has a documented bionic disposition.',
];

fs.mkdirSync(path.join(repoRoot,'kodra/deps'),{recursive:true});
fs.writeFileSync(path.join(repoRoot,'kodra/deps/INVENTORY.md'), md.join('\n')+'\n');
console.log('wrote kodra/deps/INVENTORY.md with', rows.length, 'rows, unknown=0');
