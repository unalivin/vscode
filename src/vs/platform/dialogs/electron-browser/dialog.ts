/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import { fromNow } from '../../../base/common/date.js';
import { isLinuxSnap } from '../../../base/common/platform.js';
import { localize } from '../../../nls.js';
import { IOSProperties } from '../../native/common/native.js';
import { IProductService } from '../../product/common/productService.js';
import { process } from '../../../base/parts/sandbox/electron-browser/globals.js';

function formatCopilotVersion(version: string | undefined): string {
	return version?.replace(/^(?<core>\d+\.\d+\.\d+)-(?:canary|unstable)(?=[.+-]|$)/, '$<core>').replace(/\.unsigned$/, '') || 'Unknown';
}

export function createNativeAboutDialogDetails(productService: IProductService, osProps: IOSProperties): { title: string; details: string; detailsToCopy: string } {
	let version = productService.version;
	if (productService.target) {
		version = `${version} (${productService.target} setup)`;
	} else if (productService.darwinUniversalAssetId) {
		version = `${version} (Universal)`;
	}

	const copilotRuntimeVersion = formatCopilotVersion(productService.copilotVersions?.runtime);
	const copilotSdkVersion = formatCopilotVersion(productService.copilotVersions?.sdk);

	const getDetails = (useAgo: boolean): string => {
		const details = localize({ key: 'aboutDetail', comment: ['Electron, Chromium, Node.js and V8 are product names that need no translation'] },
			"Based on Code - OSS\nVersion: {0}\nCommit: {1}\nDate: {2}\nElectron: {3}\nElectronBuildId: {4}\nChromium: {5}\nNode.js: {6}\nV8: {7}\nOS: {8}",
			version,
			productService.commit || 'Unknown',
			productService.date ? `${productService.date}${useAgo ? ' (' + fromNow(new Date(productService.date), true) + ')' : ''}` : 'Unknown',
			process.versions['electron'],
			process.versions['microsoft-build'],
			process.versions['chrome'],
			process.versions['node'],
			process.versions['v8'],
			`${osProps.type} ${osProps.arch} ${osProps.release}${isLinuxSnap ? ' snap' : ''}`
		);

		if (productService.copilotVersions) {
			return `${details}\n${localize({ key: 'aboutCopilotDetail', comment: ['Copilot is a product name that needs no translation'] }, "@github/copilot: {0}\n@microsoft/copilot-sdk: {1}", copilotRuntimeVersion, copilotSdkVersion)}`;
		}

		return details;
	};

	const details = getDetails(true);
	const detailsToCopy = getDetails(false);

	return {
		title: productService.nameLong,
		details: details,
		detailsToCopy: detailsToCopy
	};
}
