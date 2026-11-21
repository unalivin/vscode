/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import assert from 'assert';
import { createHash } from 'crypto';
import { promises } from 'fs';
import { FileAccess } from '../../../base/common/network.js';
import { htmlAttributeEncodeValue } from '../../../base/common/strings.js';
import { ensureNoDisposablesAreLeakedInTestSuite } from '../../../base/test/common/utils.js';
import { createLocalWebviewShellEndpoint, createNlsUrl, createScriptNonce, createWorkbenchContentSecurityPolicy, getWebviewFrameSource, getWebviewShellAssetName, isLocalWebviewServerAuthority, isLocalWebviewShellRequest, isSafeBasePath, renderWorkbenchTemplate } from '../../node/webClientServer.js';

/**
 * Decodes the five entities produced by `htmlAttributeEncodeValue`, the same way a browser
 * does when reading a quoted attribute value back via `getAttribute()`.
 */
function decodeHtmlAttribute(value: string): string {
	return value.replace(/&(lt|gt|quot|apos|amp);/g, (_, entity) => {
		switch (entity) {
			case 'lt': return '<';
			case 'gt': return '>';
			case 'quot': return '"';
			case 'apos': return '\'';
			case 'amp': return '&';
		}
		return _;
	});
}

function getAttributeValue(html: string, elementId: string): string {
	const match = new RegExp(`<meta id="${elementId}" data-settings="([^"]*)"`).exec(html);
	assert.ok(match, `expected a data-settings attribute on ${elementId}`);
	return match[1];
}

async function readWorkbenchTemplate(): Promise<string> {
	const templatePath = FileAccess.asFileUri('vs/code/browser/workbench/workbench.html').fsPath;
	return (await promises.readFile(templatePath)).toString();
}

suite('WebClientServer', () => {
	ensureNoDisposablesAreLeakedInTestSuite();

	test('escapes workbench template substitutions', async () => {
		const template = await readWorkbenchTemplate();
		const forwardedPrefix = `/'); alert(document.cookie); new URL('x`;
		const localeUrl = `https://example.com/fr"><script>alert(document.cookie)</script><x/nls.messages.js`;
		const values = {
			WORKBENCH_WEB_CONFIGURATION: JSON.stringify({ serverBasePath: forwardedPrefix }),
			WORKBENCH_AUTH_SESSION: '',
			WORKBENCH_WEB_BASE_URL: forwardedPrefix,
			WORKBENCH_NLS_URL: localeUrl,
			WORKBENCH_NLS_FALLBACK_URL: '/static/out/nls.messages.js',
			WORKBENCH_SCRIPT_NONCE: createScriptNonce()
		};

		const rendered = renderWorkbenchTemplate(template, values);

		assert.deepStrictEqual({
			scriptElementCount: rendered.match(/<script(?:\s|>)/g)?.length,
			inlineScriptWithoutNonceCount: rendered.match(/<script(?![^>]*\bsrc=)(?![^>]*\bnonce=)[^>]*>/g)?.length ?? 0,
			containsRawForwardedPrefix: rendered.includes(forwardedPrefix),
			containsRawLocaleUrl: rendered.includes(localeUrl),
			containsEncodedForwardedPrefix: rendered.includes(htmlAttributeEncodeValue(forwardedPrefix)),
			containsEncodedLocaleUrl: rendered.includes(htmlAttributeEncodeValue(localeUrl))
		}, {
			scriptElementCount: 6,
			inlineScriptWithoutNonceCount: 0,
			containsRawForwardedPrefix: false,
			containsRawLocaleUrl: false,
			containsEncodedForwardedPrefix: true,
			containsEncodedLocaleUrl: true
		});
	});

	test('round-trips the workbench configuration through attribute encoding', async () => {
		const template = await readWorkbenchTemplate();
		const configuration = {
			remoteAuthority: 'localhost:3000',
			serverBasePath: '/proxy&a=1',
			folderUri: { scheme: 'vscode-remote', path: '/it\'s/a "folder"/<x>' }
		};
		const baseUrl = '/proxy&a=1/stable/static';

		const rendered = renderWorkbenchTemplate(template, {
			WORKBENCH_WEB_CONFIGURATION: JSON.stringify(configuration),
			WORKBENCH_AUTH_SESSION: '',
			WORKBENCH_WEB_BASE_URL: baseUrl,
			WORKBENCH_NLS_URL: '',
			WORKBENCH_NLS_FALLBACK_URL: `${baseUrl}/out/nls.messages.js`,
			WORKBENCH_SCRIPT_NONCE: createScriptNonce()
		});

		assert.deepStrictEqual({
			configuration: JSON.parse(decodeHtmlAttribute(getAttributeValue(rendered, 'vscode-workbench-web-configuration'))),
			baseUrl: decodeHtmlAttribute(getAttributeValue(rendered, 'vscode-workbench-web-base-url'))
		}, {
			configuration,
			baseUrl
		});
	});

	test('authorizes exactly the rendered inline scripts via the request nonce', async () => {
		const template = await readWorkbenchTemplate();
		const scriptNonce = createScriptNonce();

		const rendered = renderWorkbenchTemplate(template, {
			WORKBENCH_WEB_CONFIGURATION: '{}',
			WORKBENCH_AUTH_SESSION: '',
			WORKBENCH_WEB_BASE_URL: '/static',
			WORKBENCH_NLS_URL: '',
			WORKBENCH_NLS_FALLBACK_URL: '/static/out/nls.messages.js',
			WORKBENCH_SCRIPT_NONCE: scriptNonce
		});
		const policy = createWorkbenchContentSecurityPolicy(scriptNonce, undefined, 'localhost:3000', false);

		assert.deepStrictEqual({
			renderedNonces: [...new Set(Array.from(rendered.matchAll(/nonce="([^"]*)"/g), match => match[1]))],
			policyAuthorizesRenderedNonce: policy.includes(`'nonce-${scriptNonce}'`)
		}, {
			renderedNonces: [scriptNonce],
			policyAuthorizesRenderedNonce: true
		});
	});

	test('uses a unique nonce without hashing rendered scripts', () => {
		const firstNonce = createScriptNonce();
		const secondNonce = createScriptNonce();
		const injectedScriptHash = `'sha256-${createHash('sha256').update('alert(document.cookie)').digest('base64')}'`;
		const policy = createWorkbenchContentSecurityPolicy(firstNonce, 'https://example.com/nls/', 'localhost:3000', false);

		assert.deepStrictEqual({
			noncesDiffer: firstNonce !== secondNonce,
			hasRequestNonce: policy.includes(`'nonce-${firstNonce}'`),
			hasStaticNonce: policy.includes('nonce-1nline-m4p'),
			hasInjectedScriptHash: policy.includes(injectedScriptHash)
		}, {
			noncesDiffer: true,
			hasRequestNonce: true,
			hasStaticNonce: false,
			hasInjectedScriptHash: false
		});
	});

	test('encodes the locale as one NLS URL path segment', () => {
		const locale = `fr"><script>alert(document.cookie)</script><x`;

		assert.strictEqual(
			createNlsUrl('https://example.com/nls/', 'commit', '1.0.0', locale),
			'https://example.com/nls/commit/1.0.0/fr%22%3E%3Cscript%3Ealert(document.cookie)%3C%2Fscript%3E%3Cx/nls.messages.js'
		);
	});

	test('only accepts absolute paths as a forwarded base path', () => {
		const basePaths = [
			'/',
			'/proxy',
			'/user/123/vscode',
			'//evil.com',
			'/\\evil.com',
			'https://evil.com',
			'evil.com',
			'/proxy?next=https://evil.com',
			'/proxy#fragment',
			'/proxy\r\nLocation: https://evil.com'
		];

		assert.deepStrictEqual(basePaths.map(isSafeBasePath), [
			true,
			true,
			true,
			false,
			false,
			false,
			false,
			false,
			false,
			false
		]);
	});

	test('serves only the bundled webview shell allowlist', () => {
		const paths = [
			'/webview-shell/index.html',
			'/webview-shell/fake.html',
			'/webview-shell/service-worker.js',
			'/webview-shell/../../product.json',
			'/webview-shell/%69ndex.html',
			'/webview-shell/index.html/extra',
			'/static/index.html'
		];

		assert.deepStrictEqual(paths.map(getWebviewShellAssetName), [
			'index.html',
			'fake.html',
			'service-worker.js',
			undefined,
			undefined,
			undefined,
			undefined
		]);
	});

	test('configures a per-webview localhost shell endpoint only for matching local authorities', () => {
		assert.deepStrictEqual([
			isLocalWebviewServerAuthority('localhost:3000'),
			isLocalWebviewServerAuthority('127.0.0.1:3000'),
			isLocalWebviewServerAuthority('[::1]:3000'),
			isLocalWebviewServerAuthority('example.com:3000'),
			isLocalWebviewServerAuthority('localhost:3000/path'),
			createLocalWebviewShellEndpoint('localhost:3000', 3000, '/stable/webview-shell'),
			createLocalWebviewShellEndpoint('localhost:3000', 3001, '/stable/webview-shell'),
			createLocalWebviewShellEndpoint('example.com:3000', 3000, '/stable/webview-shell'),
			createLocalWebviewShellEndpoint('localhost:3000', 3000, '//evil.example')
		], [
			true,
			true,
			true,
			false,
			false,
			'http://{{uuid}}.localhost:3000/stable/webview-shell/',
			undefined,
			undefined,
			undefined
		]);
	});

	test('restricts the public shell route to a hashed localhost origin on the loopback socket', () => {
		const isolatedHost = `${'a'.repeat(52)}.localhost:3000`;
		assert.deepStrictEqual([
			isLocalWebviewShellRequest(isolatedHost, 3000, '127.0.0.1', '127.0.0.1'),
			isLocalWebviewShellRequest('localhost:3000', 3000, '127.0.0.1', '127.0.0.1'),
			isLocalWebviewShellRequest(isolatedHost, 3001, '127.0.0.1', '127.0.0.1'),
			isLocalWebviewShellRequest(isolatedHost, 3000, '192.168.1.2', '127.0.0.1'),
			isLocalWebviewShellRequest(isolatedHost, 3000, '127.0.0.1', '192.168.1.2'),
			isLocalWebviewShellRequest('bad-host.localhost:3000', 3000, '127.0.0.1', '127.0.0.1'),
			isLocalWebviewShellRequest('a'.repeat(52) + '.localhost:3000/path', 3000, '127.0.0.1', '127.0.0.1')
		], [true, false, false, false, false, false, false]);
	});

	test('limits the workbench frame-src to the configured webview endpoint', () => {
		const localEndpoint = 'http://{{uuid}}.localhost:3000/stable/webview-shell/';
		const upstreamEndpoint = 'https://{{uuid}}.vscode-cdn.net/stable/pre/';
		const nonce = createScriptNonce();
		const defaultPolicy = createWorkbenchContentSecurityPolicy(nonce, undefined, 'localhost:3000', false);
		const localPolicy = createWorkbenchContentSecurityPolicy(nonce, undefined, 'localhost:3000', false, getWebviewFrameSource(localEndpoint));

		assert.strictEqual(getWebviewFrameSource(localEndpoint), 'http://*.localhost:3000');
		assert.strictEqual(getWebviewFrameSource(upstreamEndpoint), 'https://*.vscode-cdn.net');
		assert.ok(defaultPolicy.includes("frame-src 'self' 'none' data:"));
		assert.ok(!defaultPolicy.includes('vscode-cdn.net'));
		assert.ok(localPolicy.includes("frame-src 'self' http://*.localhost:3000 data:"));
		assert.throws(() => getWebviewFrameSource('https://example.com/{{uuid}}/shell/'));
	});
});
