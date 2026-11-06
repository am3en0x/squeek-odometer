// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {OdometerArt} from "../src/art/OdometerArt.sol";
import {Reading} from "../src/Types.sol";

/// @notice Writes previews/gallery.html: the contract's own SVG for every stage, status and holder flag.
contract Gallery is Script {
    function run() external {
        uint256[7] memory mm = [uint256(420_000), 1_070_000, 5_310_000, 12_730_000, 27_900_000, 58_120_000, 104_660_000];
        string memory html = '<!doctype html><meta charset="utf-8"><body style="background:#000;margin:8px">';
        for (uint8 stage; stage < 7; stage++) {
            html = string.concat(html, "<div>");
            for (uint8 k; k < 4; k++) {
                Reading memory r;
                r.stage = stage;
                r.status = k == 3 ? 3 : (k == 0 ? 1 : (k == 1 ? 2 : 0));
                r.holder = stage % 2 == 1;
                r.distanceMm = mm[stage];
                r.live = r.status != 3;
                html = string.concat(html, '<span style="display:inline-block;width:240px;height:240px;margin:4px">',
                    string(OdometerArt.svg(r)), "</span>");
            }
            html = string.concat(html, "</div>");
        }
        vm.writeFile("previews/gallery.html", string.concat(html, "</body>"));
    }
}
