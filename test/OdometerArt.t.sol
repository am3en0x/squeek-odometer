// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OdometerArt} from "../src/art/OdometerArt.sol";
import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {Reading} from "../src/Types.sol";
import {MockCore, MockNFT, MockStaking} from "./mocks/Mocks.sol";

contract ArtHarness {
    function svg(Reading memory r) external pure returns (string memory) { return string(OdometerArt.svg(r)); }
    function json(uint256 id, Reading memory r) external pure returns (string memory) { return string(OdometerArt.json(id, r)); }
    function km(uint256 mm) external pure returns (string memory) { return string(OdometerArt.kmText(mm)); }
}

contract OdometerArtTest is Test {
    ArtHarness art = new ArtHarness();

    function _r(uint8 stage, uint8 status, bool holder, uint256 mm) internal pure returns (Reading memory r) {
        r.stage = stage;
        r.status = status;
        r.holder = holder;
        r.distanceMm = mm;
        r.work = mm / 887;
        r.startWork = 11_048;
        r.blockHeight = 1_140;
        r.live = status != 3;
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
}
