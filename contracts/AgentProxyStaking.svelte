<script lang="ts">
	import { explorerTxUrl, isLoggedIn } from '$lib/stacks/stacks-connect';
	import { getConfig, getDaoConfig } from '$stores/store_helpers';
	import { callContractReadOnly, getAddressFromOutScript, getStacksNetwork, REGTEST_NETWORK } from '@mijoco/stx_helpers/dist/index';
	import { onMount } from 'svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import { showContractCall } from '@stacks/connect';
	import { Cl, PostConditionMode, serializeCV } from '@stacks/transactions';
	import type { TransactionProofSet } from './proof-types';
	import * as btc from '@scure/btc-signer';
	import { hex } from '@scure/base';
	import { btcToken } from '$lib/predictions/predictions';

	export let proof: TransactionProofSet;
	let errorMessage: string | undefined;
	let txId: string;

	const doBitcoinPrediction = async () => {
		errorMessage = undefined;
		if (!isLoggedIn()) {
			errorMessage = 'Please connect your wallet';
			return;
		}
		const contractAddress = getDaoConfig().VITE_DOA_DEPLOYER;
		const contractName = getDaoConfig().VITE_DAO_MARKET_BITCOIN;
		let functionName = 'predict-category';

		let functionArgs = [
			Cl.uint(proof.height),
			Cl.bufferFromHex(proof.txHex),
			Cl.bufferFromHex(proof.header),
			Cl.uint(proof.txIndex),
			Cl.uint(proof.treeDepth),
			Cl.list(proof.wproof.map((o) => Cl.bufferFromHex(o))),
			Cl.bufferFromHex(proof.computedWtxidRoot ? proof.computedWtxidRoot : proof.merkleRoot),
			proof.witnessReservedValue ? Cl.some(Cl.bufferFromHex(proof.witnessReservedValue)) : Cl.none(),
			proof.witnessReservedValue ? Cl.some(Cl.bufferFromHex(proof.ctxHex)) : Cl.none(),
			proof.witnessReservedValue ? Cl.some(Cl.list(proof.cproof.map((o) => Cl.bufferFromHex(o)))) : Cl.none()
		];

		await showContractCall({
			network: getStacksNetwork(getConfig().VITE_NETWORK),
			postConditions: [],
			postConditionMode: PostConditionMode.Allow,
			contractAddress,
			contractName,
			functionName,
			functionArgs,
			onFinish: (data) => {
				txId = data.txId;
			},
			onCancel: () => {
				console.log('popup closed!');
			}
		});
	};

	export const verifySegwit = async (proof: TransactionProofSet) => {
		let functionArgs = [
			`0x${serializeCV(Cl.uint(proof.height))}`,
			`0x${serializeCV(Cl.bufferFromHex(proof.txHex))}`,
			`0x${serializeCV(Cl.bufferFromHex(proof.header))}`,
			`0x${serializeCV(Cl.uint(proof.txIndex))}`,
			`0x${serializeCV(Cl.uint(proof.treeDepth))}`,
			`0x${serializeCV(Cl.list(proof.wproof.map((o) => Cl.bufferFromHex(o))))}`,
			`0x${serializeCV(Cl.bufferFromHex(proof.computedWtxidRoot ? proof.computedWtxidRoot : proof.merkleRoot))}`,
			`0x${serializeCV(Cl.bufferFromHex(proof.witnessReservedValue!))}`,
			`0x${serializeCV(Cl.bufferFromHex(proof.ctxHex))}`,
			`0x${serializeCV(Cl.list(proof.cproof.map((o) => Cl.bufferFromHex(o))))}`
		];
		const data = {
			contractAddress: getDaoConfig().VITE_DOA_DEPLOYER,
			contractName: getDaoConfig().VITE_DAO_MARKET_BITCOIN,
			functionName: 'verify-segwit',
			functionArgs
		};
		const response = await callContractReadOnly(getConfig().VITE_STACKS_API, data);
		let result = (response.value?.value || response.value) as string;
		console.log('verifySegwit: result: ', result);
		return result;
	};

	export const getOutputSegwit = async (output: number, proof: TransactionProofSet) => {
		const functionArgs = [`0x${serializeCV(Cl.bufferFromHex(proof.txHex))}`, `0x${serializeCV(Cl.uint(output))}`];
		const data = {
			contractAddress: getDaoConfig().VITE_DOA_DEPLOYER,
			contractName: getDaoConfig().VITE_DAO_MARKET_BITCOIN,
			functionName: 'get-output-segwit',
			functionArgs
		};
		const response = await callContractReadOnly(getConfig().VITE_STACKS_API, data);
		let result = (response.value?.value || response.value) as any;
		console.log('getOutputSegwit: ' + output + ' result: ', result);
		return result;
	};

	export const parsePayloadSegwit = async (proof: TransactionProofSet) => {
		const functionArgs = [`0x${serializeCV(Cl.bufferFromHex(proof.txHex))}`];
		const data = {
			contractAddress: getDaoConfig().VITE_DOA_DEPLOYER,
			contractName: getDaoConfig().VITE_DAO_MARKET_BITCOIN,
			functionName: 'parse-payload-segwit',
			functionArgs
		};
		const response = await callContractReadOnly(getConfig().VITE_STACKS_API, data);
		let result = (response.value?.value || response.value) as string;
		console.log('getOutputSegwit: result: ', result);
		return result;
	};

	export const isMarketWalletOutput = async (scriptPubKey: string) => {
		const functionArgs = [`0x${serializeCV(Cl.bufferFromHex(scriptPubKey))}`];
		const data = {
			contractAddress: getDaoConfig().VITE_DOA_DEPLOYER,
			contractName: getDaoConfig().VITE_DAO_MARKET_BITCOIN,
			functionName: 'is-market-wallet-output',
			functionArgs
		};
		const response = await callContractReadOnly(getConfig().VITE_STACKS_API, data);
		let result = (response.value?.value || response.value) as string;
		console.log('getOutputSegwit: result: ', result);
		return result;
	};

	onMount(async () => {
		const marketId = 0; //Number(page.params.slug);
		const marketType = 3; //Number(page.params.marketType);
		await parsePayloadSegwit(proof);
		await getOutputSegwit(0, proof);
		const res = await getOutputSegwit(1, proof);
		const spk = (res.scriptPubKey.value as string).substring(2);
		const address = getAddressFromOutScript('devnet', hex.decode(spk));

		console.log('getOutputSegwit: hash: ', address);
		const res1 = await isMarketWalletOutput(res.scriptPubKey.value);
		await getOutputSegwit(2, proof);
		await verifySegwit(proof);
	});
</script>

<!-- Staking Interface -->
<div class="card bg-neutral shadow-xl">
	<div class="card-body">
		<h2 class="card-title mb-6 text-2xl">Finalise Staking</h2>

		{#if txId}
			<div class="mb-4 flex w-full justify-start gap-x-4">
				<Banner bannerType={'info'} message={'your request is being processed. See <a href="' + explorerTxUrl(txId) + '" target="_blank">' + txId + '</a>'} />
			</div>
		{/if}
		{#if errorMessage}
			<div class="mb-4 flex w-full justify-start gap-x-4">
				<Banner bannerType={'info'} message={errorMessage} />
			</div>
		{/if}
		<p>Simulates the back end the users bitcoin transaction to the prediciton contract</p>
		<button on:click={() => doBitcoinPrediction()} class="btn btn-primary"> submit </button>
	</div>
</div>