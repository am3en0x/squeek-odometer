# Security review handoff

What a reviewer needs to judge `SqueekOdometer` before it is deployed. The builder's tests and these notes are not an
independent review.

## Authorization and state boundaries

- There is no owner, admin, role, pause, upgrade path, initializer or proxy. Nothing in the contract can be changed
  after deployment by anyone.
- The only state-changing functions are `mint()`, the standard ERC-721 transfer and approval functions (OpenZeppelin
  5.7.0, unmodified), and `refresh(id)` / `refreshAll()`, which only emit ERC-4906 events.
- `mint()` takes no arguments and acts for `msg.sender`: one token per wallet (`idOf[msg.sender] != 0` reverts
  `AlreadyMinted`, also after the token is sent away), at most `MAX_SUPPLY = 9,999` (`SoldOut`). It uses `_mint`, not
  `_safeMint`, so there is no receiver callback during the mint. Contract wallets may mint.
- Per token the contract stores only `startWork` (SqueekCore `cumulativeWork` at mint) and `mintedAt`. Everything a
  token shows is derived on read.

## Custody and value flow

- No function is payable and there is no `receive` or `fallback`: plain ETH transfers revert. The contract never holds
  or moves ETH or tokens, has no fees and no withdrawal.
- Royalties are not implemented (no ERC-2981).

## External calls and liveness

- The contract reads three Squeekchain contracts on Sepolia, fixed at deployment (immutable): SqueekCore `state()` and
  `roundPage()`, SqueekNFT `balanceOf()`, SqueekStaking `accountPower()`. It never calls them with value and never
  writes to them.
- Every read goes through `_read`: a `staticcall` capped at 500,000 gas that copies at most the words it needs into a
  fixed buffer (no return-data bomb) and fails unless the answer is at least that long. A reverting, missing, slow or
  hostile dependency can therefore only fail its own read.
- `mint()` requires a successful SqueekCore read (`CoreUnreadable` otherwise), so every token starts from a real value.
- `reading()` and `tokenURI()` never revert for an existing token: an unreadable SqueekCore gives status "unknown" and
  no distance; unreadable NFT or staking reads give no holder tier. A missing token reverts as in ERC-721.
- If Squeekchain redeploys SqueekCore (it is in active development), existing tokens keep reading the old address.
  That is a known limitation of an ownerless design: a new deployment of this contract would be needed.

## Determinism, arithmetic, and bounded work

- Solidity 0.8.26 checked arithmetic. Work below the start reads as 0 (no underflow). Distance is `work * 887`, far from
  overflow for any realistic work count.
- Traits (display, casing, treat) are a pure function of `keccak256(id, startWork)`; they are not randomness a minter
  can meaningfully grind on a free testnet mint, and they carry no value.
- `tokenURI` builds the SVG and JSON in a single buffer allocated once (`OdometerArt._buf`), so rendering is linear.
  Measured in tests: about 1.7 to 3.2 million gas per `tokenURI` call, well inside node `eth_call` limits.
- The only loops are over fixed small arrays (stages, glyph runs, at most 12 rim pips, the sprite data).

## Issues found and repaired during implementation

- A broken dependency could have made `tokenURI` revert (high-level calls revert on malformed return data): replaced by
  the gas-capped, length-checked `_read`.
- The odometer text could overflow the screen past 999.99 km: whole kilometres are shown from 1,000 km.
- The holder flag ignored Squeeks deposited in staking (staking owns them): `accountPower` is read as well.

## Review decisions and release responsibilities

- Deploy only on Sepolia (chain id 11155111); the constructor reverts elsewhere (31337 is allowed for local tests).
- Constructor arguments, in order: SqueekCore `0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4`, SqueekNFT
  `0xC4C7982657f00509548F3a3a41db7FA439a6856B`, SqueekStaking `0x50fd1780526C3186A0c037c7622203bC4fb611ca`
  (release `core-sepolia-20261103`). The constructor makes no external calls, so a deploy rehearsal on an empty chain
  succeeds.
- No initialization call, no funding, no token, no pool.
