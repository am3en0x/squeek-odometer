# Deploying Squeek Odometer through IMD

The project is finished in this repository; IMD is asked to review it, deploy it on Sepolia and host the site. The
wallet that pays for the first job owns the IMD project, so pay from the wallet verified on your Squeekchain Genesis
profile (an ordinary wallet, not a Safe).

## What it costs

One `workflow.open` is 0.5 IMD (IMD docs, "Paid actions"), paid on Ethereum
(`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`) or Robinhood Chain (`0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`). A job
paid on a mainnet can still deploy on Sepolia (`chainId` 11155111). The Sepolia Intake sells only oracle questions.

## The job

- Action: `workflow.open` (contracts, review, deployment, then a site built against the live addresses).
- Repository: this repository's public GitHub URL, `baseCommit` = the commit to deploy (40 lowercase hex), resolved
  with `POST /requests/import` first (the launch page does this for you).
- On chain: `evm_contracts`, chain id `11155111`, contract `SqueekOdometer`; constructor arguments in `launch.json`.
  No `owner` field: the contract has no privileged role.
- Site: `dist/` as the static site (no build step), IPFS label `squeek-odometer`.

Objective to paste (it is under the 8,000-character limit):

```
Ship Squeek Odometer from this repository, as it is: review it, deploy it on Sepolia, host its site.

What it is: a free, fully on-chain dynamic ERC-721 for Squeekchain's Genesis Code Lane. Each token stores
SqueekCore's cumulativeWork at mint and renders, in tokenURI, how far Squeektoshi the hamster has run since
(work x 887 mm), his status from the last three settled rounds (napping, jogging, zoomies), a stage with gear at
1/5/10/25/50/100 km, and a gold frame when the owner holds or stakes a Squeek.

Contracts: one contract, src/SqueekOdometer.sol (with src/art/*, src/Types.sol, src/interfaces/ISqueek.sol). Foundry,
solc 0.8.26, evm_version cancun, bytecode_hash = "none", dependencies vendored in lib/ (no submodules, no FFI).
Checks: forge build; forge test (37 tests, no network, pinned fuzz seed); forge fmt --check src test script;
python3 tools/export_abi.py --check; FOUNDRY_PROFILE=fork forge test needs a Sepolia RPC. Runtime 23,212 bytes;
deployment measured 5,126,572 gas (conservative factory estimate 39,960,400). Details in docs/VALIDATION.md, the
builder's security notes in docs/SECURITY.md.

Deploy: SqueekOdometer on Sepolia (11155111) with the constructor arguments from launch.json, in order:
SqueekCore 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4, SqueekNFT 0xC4C7982657f00509548F3a3a41db7FA439a6856B,
SqueekStaking 0x50fd1780526C3186A0c037c7622203bC4fb611ca. No owner, no initialization call, zero value. The
constructor reverts outside Sepolia and makes no external calls.

Review: an independent adversarial review of the contract before deployment. Points to check: mint is free and one
per wallet with a 9,999 cap; every Squeekchain read is a gas-capped staticcall that copies a fixed number of words
(_read), so tokenURI cannot revert for an existing token; no privileged role or payable path exists.

Site: dist/ is the static site with no build step (index.html, app.js, led.js, style.css, config.js, fonts/,
samples/, svg assets; design in DESIGN.md). Publish it as is to IPFS with the label squeek-odometer, with the deployed
SqueekOdometer address and deployment block written into dist/config.js (address, fromBlock); app.js also reads
imd-deployment.json next to the page if config.js has no address. Do not change the contract or the art.
```

## If IMD cannot host the site

IMD's docs say member sites are closed for now (`503 member_sites_closed`). The site is static, so it can be served
from any host (for example GitHub Pages from `dist/`) once `dist/config.js` holds the deployed address and block.
