# Validation

## Recorded final result

Run on 2026-11-07 with Foundry (solc 0.8.26, Cancun, optimizer 200, `bytecode_hash = "none"`).

```sh
forge build
forge test                       # 37 tests, 0 failed (fuzz: 512 runs, pinned seed in foundry.toml)
forge fmt --check src test script
python3 tools/export_abi.py --check
FOUNDRY_PROFILE=fork forge test  # 1 test against Sepolia at block 12,077,300, 0 failed
```

What the default tests cover (local mocks of SqueekCore, SqueekNFT and SqueekStaking, no RPC):

- mint: start work stored, sequential ids, one per wallet, the 9,999 cap, no mint without a SqueekCore reading,
  Sepolia only;
- the reading: distance = work since mint × 887 mm (fuzzed), stage thresholds at 1/5/10/25/50/100 km, work below the
  start reads 0, napping / jogging / zoomies from the last three settled rounds, fewer than three rounds, a broken or
  gas-burning SqueekCore (status unknown), the holder tier from wallet and staking power, broken NFT or staking reads;
- the art and metadata: a whole SVG document, night and bedding when napping, the animation speed following the pace,
  the wheel's metal and one piece of gear per stage, the token's last digit on a Racer's bib, confetti after a new
  stage, rim pips past 100 km, the bottle by holder tier, every display, casing and treat, trait rarities, the JSON
  traits and its balanced braces, `tokenURI` through the contract with a broken core, ERC-721 / ERC-4906 interfaces,
  the trait rolls from id and start work, the `refresh` events, and `tokenURI` gas.

The fork test deploys against the real three addresses, mints, and checks the start work against SqueekCore, the live
reading and `tokenURI`.

The site in `dist/` was checked end to end on an anvil fork of Sepolia (block 12,078,256): deploy, two mints from the
command line, a third through the page with a stand-in wallet that forwards to the fork; the supply went to 3 / 9,999,
"your odometer" showed token #3 from `tokenURI`, the latest mints listed #3, #2, #1 from the `Minted` events, and
"Ask marketplaces to redraw" sent `refresh(3)` and confirmed. The LED board and the live numbers read Squeekchain's
API. Layout checked at 1280px and 390px (no horizontal scroll at 390px).

### Sizes from `forge build --sizes`

| Contract | Runtime (bytes) | Initcode (bytes) | Runtime margin |
| --- | ---: | ---: | ---: |
| SqueekOdometer | 23,212 | 23,947 | 1,364 |

### Gas

| What | Gas |
| --- | ---: |
| Deployment, measured (`forge create` on a local chain) | 5,126,572 |
| Deployment, conservative factory estimate (1,700 gas per runtime byte + 500,000) | 39,960,400 |
| `mint()` (from `forge test --gas-report`) | about 165,000 |
| `tokenURI()` view (from the tests) | 1.7 to 3.2 million |
| `refresh(id)` | about 24,000 |
