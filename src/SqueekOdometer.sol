// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ISqueekCore, ISqueekNFT, ISqueekStaking} from "./interfaces/ISqueek.sol";

/// @title Squeek Odometer
/// @notice A free, fully on-chain odometer for Squeektoshi, the hamster whose wheel powers Squeekchain. Each token
/// remembers the wheel's settled work when it was minted and shows how far he has run since, read live from
/// SqueekCore. No owner, no admin, no upgrade, no funds.
contract SqueekOdometer is ERC721 {
    /// @notice Everything a token shows, derived on every read.
    struct Reading {
        uint256 startWork; // SqueekCore cumulativeWork when the token was minted
        uint256 work; // settled work since then (one unit = one wheel turn)
        uint256 distanceMm; // work * MM_PER_WORK
        uint8 stage; // 0 Newbie .. 6 Legend
        uint8 status; // NAPPING, JOGGING, ZOOMIES or UNKNOWN
        bool holder; // the token's owner holds a Squeek, in the wallet or deposited in staking
        uint64 blockHeight; // Squeek block height
        bool live; // SqueekCore answered
    }

    uint256 public constant MAX_SUPPLY = 9_999;
    /// @notice Wheel distance per work unit. The device estimates distance from a fixed wheel circumference; its
    /// lifetime figures (22,789,368 mm over 25,701 units) give 886.7 mm, live speed/RPM readings about 880 mm.
    uint256 public constant MM_PER_WORK = 887;
    /// @notice Work over the last three settled rounds (30 minutes) at or above which he has the zoomies.
    uint256 public constant ZOOMIES_WORK = 1_500;
    uint8 public constant NAPPING = 0;
    uint8 public constant JOGGING = 1;
    uint8 public constant ZOOMIES = 2;
    uint8 public constant UNKNOWN = 3;
    /// @dev Gas each read of a Squeekchain contract may use: a broken or hostile dependency can only fail its read.
    uint256 internal constant READ_GAS = 500_000;

    ISqueekCore public immutable core;
    ISqueekNFT public immutable squeeks;
    ISqueekStaking public immutable staking;

    uint256 public totalMinted;
    /// @notice The token a wallet minted (0: none). A wallet mints once, even after it sends its token away.
    mapping(address => uint256) public idOf;
    mapping(uint256 => uint256) public startWork;
    mapping(uint256 => uint256) public mintedAt;

    event Minted(uint256 indexed id, address indexed to, uint256 startWork);

    error AlreadyMinted();
    error SoldOut();
    error CoreUnreadable();
    error WrongChain();

    constructor(address core_, address squeeks_, address staking_) ERC721("Squeek Odometer", "ODOMETER") {
        // Sepolia only (31337: local tests); no external calls here, so a deploy rehearsal on an empty chain works
        if (block.chainid != 11155111 && block.chainid != 31337) revert WrongChain();
        core = ISqueekCore(core_);
        squeeks = ISqueekNFT(squeeks_);
        staking = ISqueekStaking(staking_);
    }

    /// @notice Free, one per wallet. The odometer starts from the wheel's settled work right now.
    function mint() external returns (uint256 id) {
        if (idOf[msg.sender] != 0) revert AlreadyMinted();
        if (totalMinted >= MAX_SUPPLY) revert SoldOut();
        (bool ok, uint256[8] memory s) = _read(address(core), abi.encodeCall(ISqueekCore.state, ()), 2);
        // a token must start from a real reading
        if (!ok) revert CoreUnreadable();
        id = ++totalMinted;
        idOf[msg.sender] = id;
        startWork[id] = s[1];
        mintedAt[id] = block.timestamp;
        _mint(msg.sender, id);
        emit Minted(id, msg.sender, s[1]);
    }

    /// @notice What token `id` shows now. Reverts for a token that does not exist.
    function reading(uint256 id) public view returns (Reading memory r) {
        address owner = _requireOwned(id);
        r.startWork = startWork[id];
        // CoreState is static: settledThroughRound, cumulativeWork, cumulativeBlockUnits, blockHeight, ...
        (bool ok, uint256[8] memory s) = _read(address(core), abi.encodeCall(ISqueekCore.state, ()), 4);
        if (ok) {
            r.live = true;
            r.work = s[1] > r.startWork ? s[1] - r.startWork : 0;
            r.blockHeight = uint64(s[3]);
            r.status = _status(uint64(s[0]));
        } else {
            r.status = UNKNOWN;
        }
        r.distanceMm = r.work * MM_PER_WORK;
        r.stage = stageOf(r.distanceMm);
        r.holder = _holds(owner);
    }

    /// @notice Stage for a distance: 0 Newbie, 1 Warm-up (1 km), 2 Jogger (5), 3 Runner (10), 4 Racer (25),
    /// 5 Marathoner (50), 6 Legend (100 km).
    function stageOf(uint256 distanceMm) public pure returns (uint8 stage) {
        uint32[6] memory km = [uint32(1), 5, 10, 25, 50, 100];
        for (uint256 i; i < 6; i++) {
            if (distanceMm < uint256(km[i]) * 1_000_000) return stage;
            stage++;
        }
    }

    /// @dev Napping, jogging or zoomies from the work settled in the last three rounds (up to `settled`).
    function _status(uint64 settled) internal view returns (uint8) {
        if (settled == 0) return NAPPING;
        uint64 from = settled > 3 ? settled - 3 : 0;
        // RoundPage is dynamic: [offset, certifiedThroughRound, start(cumulativeWork, ..), end(cumulativeWork, ..)]
        (bool ok, uint256[8] memory p) =
            _read(address(core), abi.encodeCall(ISqueekCore.roundPage, (from, settled, 3)), 6);
        if (!ok) return UNKNOWN;
        uint256 w = p[5] > p[2] ? p[5] - p[2] : 0;
        if (w == 0) return NAPPING;
        return w >= ZOOMIES_WORK ? ZOOMIES : JOGGING;
    }

    /// @dev A Squeek in the wallet, or Squeeks deposited in staking (staking then owns them, so the wallet holds 0).
    function _holds(address who) internal view returns (bool) {
        (bool ok, uint256[8] memory b) = _read(address(squeeks), abi.encodeCall(ISqueekNFT.balanceOf, (who)), 1);
        if (ok && b[0] > 0) return true;
        (ok, b) = _read(address(staking), abi.encodeCall(ISqueekStaking.accountPower, (who)), 1);
        return ok && b[0] > 0;
    }

    /// @dev A gas-capped static call that copies at most `words` words of the answer (no return-data bomb) and fails
    /// unless the answer has at least that many.
    function _read(address to, bytes memory data, uint256 words) internal view returns (bool ok, uint256[8] memory w) {
        assembly ("memory-safe") {
            ok := staticcall(READ_GAS, to, add(data, 0x20), mload(data), w, mul(words, 0x20))
            if lt(returndatasize(), mul(words, 0x20)) { ok := 0 }
        }
    }
}
