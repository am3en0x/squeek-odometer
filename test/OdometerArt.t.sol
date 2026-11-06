// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OdometerArt} from "../src/art/OdometerArt.sol";
import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {Reading} from "../src/Types.sol";
import {MockCore, MockNFT, MockStaking} from "./mocks/Mocks.sol";

contract ArtHarness {
    function svg(Reading memory r) external pure returns (string memory) { return string(OdometerArt.svg(1, r)); }
    function svgId(uint256 id, Reading memory r) external pure returns (string memory) { return string(OdometerArt.svg(id, r)); }
    function fur(uint256 roll) external pure returns (uint8) { return OdometerArt.furOf(roll); }
    function json(uint256 id, Reading memory r) external pure returns (string memory) { return string(OdometerArt.json(id, r)); }
    function km(uint256 mm) external pure returns (string memory) { return string(OdometerArt.kmText(mm)); }
}

contract OdometerArtTest is Test {
    ArtHarness art = new ArtHarness();

    function _rf(uint8 stage, uint8 status, uint8 fur) internal pure returns (Reading memory r) {
        r = _r(stage, status, false, 1_000_000);
        r.fur = fur;
    }

    function _r(uint8 stage, uint8 status, bool holder, uint256 mm) internal pure returns (Reading memory r) {
        r.stage = stage;
        r.status = status;
        r.holder = holder;
        r.distanceMm = mm;
        r.work = mm / 887;
        r.startWork = 11_048;
        r.blockHeight = 1_140;
        r.live = status != 3;
        r.tier = holder ? 3 : 0;
        r.pace = status == 2 ? 1_800 : status == 1 ? 600 : 0;
    }

    function _has(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i + n.length <= h.length; i++) {
            bool ok = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) { ok = false; break; }
            }
            if (ok) return true;
        }
        return false;
    }

    function test_svgIsAWholeDocument() public view {
        string memory s = art.svg(_r(2, 1, false, 5_310_000));
        assertTrue(_has(s, '<svg xmlns="http://www.w3.org/2000/svg"'));
        bytes memory b = bytes(s);
        assertEq(string(abi.encodePacked(b[b.length - 6], b[b.length - 5], b[b.length - 4], b[b.length - 3], b[b.length - 2], b[b.length - 1])), "</svg>");
    }

    function test_frameShowsTheSqueekHolder() public view {
        assertTrue(_has(art.svg(_r(0, 1, true, 0)), 'stroke="#f5b301" stroke-width="2"'));
        assertTrue(_has(art.svg(_r(0, 1, false, 0)), 'stroke="#3a4150"'));
        assertFalse(_has(art.svg(_r(0, 1, false, 0)), 'stroke="#f5b301" stroke-width="2"'));
    }

    function test_nappingAndZoomiesLook() public view {
        string memory nap = art.svg(_r(1, 0, false, 1_100_000));
        string memory zoom = art.svg(_r(1, 2, false, 1_100_000));
        assertTrue(_has(nap, "#c7d2fe"), "z over a napping hamster");
        assertFalse(_has(nap, "#dbe4ff"));
        assertTrue(_has(zoom, "#dbe4ff"), "speed lines");
        assertFalse(_has(zoom, "#c7d2fe"));
    }

    function test_legendWearsTheCrown() public view {
        assertTrue(_has(art.svg(_r(6, 1, false, 100_000_000)), "#ffd84d"));
        assertFalse(_has(art.svg(_r(5, 1, false, 60_000_000)), "#ffd84d"));
        assertTrue(_has(art.svg(_r(5, 1, false, 60_000_000)), "#e5484d"), "the headband from Jogger on");
        assertFalse(_has(art.svg(_r(1, 1, false, 1_000_000)), "#e5484d"));
    }

    function test_kmText() public view {
        assertEq(art.km(0), "0.00");
        assertEq(art.km(999_999), "0.99");
        assertEq(art.km(12_730_000), "12.73");
        assertEq(art.km(104_660_000), "104.66");
        assertEq(art.km(1_000_536), "1.00");
    }

    function test_jsonHasTheTraits() public view {
        string memory j = art.json(42, _r(3, 2, true, 12_730_000));
        assertTrue(_has(j, '"name":"Squeek Odometer #42"'));
        assertTrue(_has(j, '"image":"data:image/svg+xml;base64,'));
        assertTrue(_has(j, '{"trait_type":"Distance (km)","display_type":"number","value":12.73}'));
        assertTrue(_has(j, '{"trait_type":"Stage","value":"Runner"}'));
        assertTrue(_has(j, '{"trait_type":"Status","value":"Zoomies"}'));
        assertTrue(_has(j, '{"trait_type":"Squeek Holder","value":"Yes"}'));
        assertTrue(_has(j, '{"trait_type":"Start Work","display_type":"number","value":11048}'));
        assertTrue(_has(j, '{"trait_type":"Squeek Block Height","display_type":"number","value":1140}'));
        // balanced braces and brackets
        bytes memory b = bytes(j);
        int256 depth;
        for (uint256 i; i < b.length; i++) {
            if (b[i] == "{" || b[i] == "[") depth++;
            if (b[i] == "}" || b[i] == "]") depth--;
            assertGe(depth, 0);
        }
        assertEq(depth, 0);
    }

    function test_unknownReadsAsUnknown() public view {
        string memory j = art.json(1, _r(0, 3, false, 0));
        assertTrue(_has(j, '{"trait_type":"Status","value":"Unknown"}'));
        assertTrue(_has(art.svg(_r(0, 3, false, 0)), "#0b0e14"), "the panel still draws");
    }

    function test_tokenUriOnTheContract() public {
        MockCore core = new MockCore();
        core.set(10, 11_048, 1_140);
        SqueekOdometer odo = new SqueekOdometer(address(core), address(new MockNFT()), address(new MockStaking()));
        vm.prank(address(0xA11CE));
        odo.mint();
        string memory uri = odo.tokenURI(1);
        assertTrue(_has(uri, "data:application/json;base64,"));
        core.setBroken(true);
        assertTrue(_has(odo.tokenURI(1), "data:application/json;base64,"), "a broken core does not break the token");
        vm.expectRevert();
        odo.tokenURI(2);
        assertTrue(odo.supportsInterface(0x49064906), "ERC-4906");
        assertTrue(odo.supportsInterface(0x80ac58cd), "ERC-721");
    }

    function test_tokenUriGasIsModest() public {
        MockCore core = new MockCore();
        core.set(30, 200_000, 9_000);
        SqueekOdometer odo = new SqueekOdometer(address(core), address(new MockNFT()), address(new MockStaking()));
        vm.prank(address(0xA11CE));
        odo.mint();
        core.set(40, 400_000, 9_500);
        core.setRound(40, 2_000);
        uint256 g = gasleft();
        odo.tokenURI(1);
        assertLt(g - gasleft(), 15_000_000, "an eth_call must stay far below node limits");
    }

    // ---- the living odometer (2026-11-07): animation, fur, wheel tiers, token number, night sky, LCD ghosts

    function test_awakeHamsterIsAnimatedAndZoomiesAreFaster() public view {
        string memory jog = art.svg(_r(2, 1, false, 5_000_000));
        string memory zoom = art.svg(_r(2, 2, false, 5_000_000));
        string memory nap = art.svg(_r(2, 0, false, 5_000_000));
        // pace 600 -> a spoke cycle of 900 - 600/3 = 700 ms, legs two thirds of it; pace 1,800 -> 300 ms and 200 ms
        assertTrue(_has(jog, '<animate attributeName="opacity" values="1;0;0" dur="700ms" calcMode="discrete" repeatCount="indefinite"/>'), "spokes spin");
        assertTrue(_has(jog, 'dur="466ms"'), "legs run");
        assertTrue(_has(zoom, 'dur="300ms"'), "the wheel spins faster");
        assertTrue(_has(zoom, 'dur="200ms"'), "the legs too");
        assertFalse(_has(nap, 'attributeName="opacity"'), "a napping hamster does not run");
        assertTrue(_has(nap, '<animateTransform attributeName="transform" type="translate"'), "but his z float");
    }

    function test_furComesFromTheRollWithRarity() public view {
        assertEq(art.fur(0), 0); assertEq(art.fur(39), 0); // Golden 40%
        assertEq(art.fur(40), 1); assertEq(art.fur(59), 1); // Cream 20%
        assertEq(art.fur(60), 2); assertEq(art.fur(74), 2); // Grey 15%
        assertEq(art.fur(75), 3); assertEq(art.fur(84), 3); // Cinnamon 10%
        assertEq(art.fur(85), 4); assertEq(art.fur(92), 4); // Shadow 8%
        assertEq(art.fur(93), 5); assertEq(art.fur(98), 5); // Ghost 6%
        assertEq(art.fur(99), 6); // Shiny Gold 1%
        assertTrue(_has(art.svg(_rf(0, 1, 0)), "#e89b47"));
        assertTrue(_has(art.svg(_rf(0, 1, 6)), "#ffc93a"));
        assertFalse(_has(art.svg(_rf(0, 1, 6)), "#e89b47"));
        assertTrue(_has(art.json(1, _rf(0, 1, 6)), '{"trait_type":"Fur","value":"Shiny Gold"}'));
        assertTrue(_has(art.json(1, _rf(0, 1, 3)), '{"trait_type":"Fur","value":"Cinnamon"}'));
    }

    function test_theWheelUpgradesWithTheStage() public view {
        assertTrue(_has(art.svg(_r(0, 1, false, 0)), "#8b95a8"), "steel");
        assertTrue(_has(art.svg(_r(3, 1, false, 10_000_000)), "#c98a4b"), "bronze for a Runner");
        assertTrue(_has(art.svg(_r(5, 1, false, 50_000_000)), "#d7dde8"), "silver for a Marathoner");
        assertTrue(_has(art.svg(_r(6, 1, false, 100_000_000)), "#f5c542"), "gold for a Legend");
        assertFalse(_has(art.svg(_r(6, 1, false, 100_000_000)), "#8b95a8"));
    }

    function test_tokenNumberNightSkyAndLcdGhosts() public view {
        assertTrue(_has(art.svgId(42, _r(0, 1, false, 0)), '<path stroke="#454c5c"'), "the token number");
        assertTrue(_has(art.svg(_r(0, 0, false, 0)), "#e8ecff"), "stars when he naps");
        assertFalse(_has(art.svg(_r(0, 1, false, 0)), "#e8ecff"));
        assertTrue(_has(art.svg(_r(0, 1, false, 0)), "#173a22"), "unlit LCD segments under the digits");
    }

    function test_theContractRollsFurFromIdAndStart() public {
        MockCore core = new MockCore();
        core.set(10, 11_048, 1_140);
        SqueekOdometer odo = new SqueekOdometer(address(core), address(new MockNFT()), address(new MockStaking()));
        vm.prank(address(0xA11CE));
        odo.mint();
        uint256 roll = uint256(keccak256(abi.encode(uint256(1), uint256(11_048)))) % 100;
        assertEq(odo.reading(1).fur, art.fur(roll));
    }

    function test_theFastestHeCanGo() public view {
        Reading memory r = _r(2, 2, false, 5_000_000);
        r.pace = 10_000;
        assertTrue(_has(art.svg(r), 'dur="240ms"'), "the wheel never blurs past 240 ms a turn");
    }

    function test_frameColorsByTierAndTraits() public view {
        Reading memory r = _r(0, 1, true, 0);
        r.tier = 1;
        assertTrue(_has(art.svg(r), 'stroke="#c98a4b" stroke-width="2"'), "bronze");
        r.tier = 2;
        assertTrue(_has(art.svg(r), 'stroke="#d7dde8" stroke-width="2"'), "silver");
        r.tier = 3;
        assertTrue(_has(art.svg(r), 'stroke="#f5b301" stroke-width="2"'), "gold");
        r.tier = 4;
        assertTrue(_has(art.svg(r), 'stroke="#7fe7ff" stroke-width="2"'), "diamond");
        assertTrue(_has(art.json(1, r), '{"trait_type":"Frame","value":"Diamond"}'));
        assertTrue(_has(art.json(1, r), '{"trait_type":"Pace (turns / 30 min)","display_type":"number","value":600}'));
        r.tier = 0;
        r.holder = false;
        assertTrue(_has(art.json(1, r), '{"trait_type":"Frame","value":"None"}'));
    }
}
