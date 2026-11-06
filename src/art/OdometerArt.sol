// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Reading} from "../Types.sol";
import {Sprites} from "./Sprites.sol";

/// @title OdometerArt
/// @notice Renders a reading as a 40x40 pixel SVG and as ERC-721 metadata JSON. Layers are run data from
/// tools/sprites.py; each color group becomes one SVG path of 1-pixel strokes. Output is written into a buffer
/// allocated once, so a render costs linear gas.
library OdometerArt {
    using Strings for uint256;

    uint8 internal constant NAPPING = 0;
    uint8 internal constant ZOOMIES = 2;
    uint8 internal constant UNKNOWN = 3;

    // ---------------------------------------------------------------- public pieces

    function svg(Reading memory r) internal pure returns (bytes memory) {
        Buf memory b = _buf(16_384);
        bool awake = r.status == 1 || r.status == ZOOMIES;
        _add(b, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40" width="480" height="480" shape-rendering="crispEdges">');
        _add(b, abi.encodePacked('<rect width="40" height="40" fill="', _stageBg(r.stage), '"/>'));
        if (r.status == NAPPING) _layer(b, Sprites.MOON);
        _layer(b, Sprites.WHEEL);
        if (r.status == ZOOMIES) _layer(b, Sprites.ZOOMIES);
        if (r.stage == 6) _layer(b, awake ? Sprites.CAPE_RUN : Sprites.CAPE_NAP);
        _layer(b, awake ? Sprites.HAMSTER_RUN : Sprites.HAMSTER_NAP);
        _gear(b, r.stage, awake);
        if (r.status == NAPPING) _layer(b, Sprites.ZZZ);
        _add(b, '<rect x="3" y="31" width="34" height="7" fill="#0b0e14"/>');
        _text(b, r.live ? kmText(r.distanceMm) : bytes("?"));
        _add(b, r.holder
            ? bytes('<rect x="1" y="1" width="38" height="38" fill="none" stroke="#f5b301" stroke-width="2"/>')
            : bytes('<rect x=".5" y=".5" width="39" height="39" fill="none" stroke="#3a4150"/>'));
        _add(b, "</svg>");
        return _done(b);
    }

    function json(uint256 id, Reading memory r) internal pure returns (bytes memory) {
        bytes memory image = bytes(Base64.encode(svg(r)));
        Buf memory b = _buf(image.length + 2_048);
        _add(b, abi.encodePacked('{"name":"Squeek Odometer #', id.toString(), '",'));
        _add(b, '"description":"How far Squeektoshi has run on his wheel since this odometer was minted, read live from SqueekCore on Sepolia (887 mm a wheel turn). It naps when he naps, gets the zoomies when he does, and earns gear at 1, 5, 10, 25, 50 and 100 km. Free, fully on-chain, no owner.",');
        _add(b, '"image":"data:image/svg+xml;base64,');
        _add(b, image);
        _add(b, '","attributes":[');
        _add(b, abi.encodePacked('{"trait_type":"Distance (km)","display_type":"number","value":', kmText(r.distanceMm), "},"));
        _add(b, abi.encodePacked('{"trait_type":"Stage","value":"', stageName(r.stage), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Status","value":"', statusName(r.status), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Squeek Holder","value":"', r.holder ? "Yes" : "No", '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Start Work","display_type":"number","value":', r.startWork.toString(), "},"));
        _add(b, abi.encodePacked('{"trait_type":"Squeek Block Height","display_type":"number","value":', uint256(r.blockHeight).toString(), "}"));
        _add(b, "]}");
        return _done(b);
    }

    /// @notice Kilometres with two decimals, rounded down: 12,730,000 mm is "12.73".
    function kmText(uint256 mm) internal pure returns (bytes memory) {
        uint256 frac = (mm % 1_000_000) / 10_000;
        return abi.encodePacked((mm / 1_000_000).toString(), ".", frac < 10 ? "0" : "", frac.toString());
    }

    function stageName(uint8 s) internal pure returns (string memory) {
        if (s == 0) return "Newbie";
        if (s == 1) return "Warm-up";
        if (s == 2) return "Jogger";
        if (s == 3) return "Runner";
        if (s == 4) return "Racer";
        if (s == 5) return "Marathoner";
        return "Legend";
    }

    function statusName(uint8 s) internal pure returns (string memory) {
        if (s == NAPPING) return "Napping";
        if (s == 1) return "Jogging";
        if (s == ZOOMIES) return "Zoomies";
        return "Unknown";
    }

    // ---------------------------------------------------------------- scene parts

    function _stageBg(uint8 s) private pure returns (bytes memory) {
        bytes memory all = "#1b2232#1c2a38#1b3530#273520#3a2c1c#3a1c2a#2a1c3a";
        return _slice(all, uint256(s > 6 ? 6 : s) * 7, 7);
    }

    /// @dev Gear earned by distance; earlier stages' gear stays on (the sweat drop goes once he is a Legend).
    function _gear(Buf memory b, uint8 stage, bool awake) private pure {
        if (stage >= 1 && stage < 6) _layer(b, awake ? Sprites.SWEAT_RUN : Sprites.SWEAT_NAP);
        if (stage >= 2) _layer(b, awake ? Sprites.HEADBAND_RUN : Sprites.HEADBAND_NAP);
        if (stage >= 3 && awake) _layer(b, Sprites.SHOES_RUN);
        if (stage >= 4) _layer(b, awake ? Sprites.BIB_RUN : Sprites.BIB_NAP);
        if (stage >= 5) _layer(b, awake ? Sprites.MEDAL_RUN : Sprites.MEDAL_NAP);
        if (stage == 6) _layer(b, awake ? Sprites.CROWN_RUN : Sprites.CROWN_NAP);
    }

    /// @dev Groups of [color, runs, (x, y, length) * runs] -> one path per group.
    function _layer(Buf memory b, bytes memory data) private pure {
        uint256 i;
        while (i < data.length) {
            uint8 c = uint8(data[i]);
            uint256 runs = uint8(data[i + 1]);
            i += 2;
            _add(b, abi.encodePacked('<path stroke="', _color(c), '" d="'));
            for (uint256 k; k < runs; k++) {
                _add(b, _run(uint8(data[i]), uint8(data[i + 1]), uint8(data[i + 2])));
                i += 3;
            }
            _add(b, '"/>');
        }
    }

    /// @dev The odometer digits in green and the unit in grey, 3x5 glyphs (M is 5 wide) on the panel.
    function _text(Buf memory b, bytes memory digits) private pure {
        uint256 x = 5;
        _add(b, '<path stroke="#7dff9b" d="');
        for (uint256 i; i < digits.length; i++) x = _glyph(b, digits[i], x);
        _add(b, '"/><path stroke="#8a93a6" d="');
        x = _glyph(b, "K", x);
        _glyph(b, "M", x);
        _add(b, '"/>');
    }

    function _glyph(Buf memory b, bytes1 ch, uint256 x) private pure returns (uint256) {
        bytes memory g = Sprites.glyph(ch);
        if (g.length == 0) return x;
        uint256 runs = uint8(g[1]);
        for (uint256 k; k < runs; k++) {
            uint256 o = 2 + k * 3;
            _add(b, _run(x + uint8(g[o]), 32 + uint8(g[o + 1]), uint8(g[o + 2])));
        }
        return x + uint8(g[0]) + 1;
    }

    function _run(uint256 x, uint256 y, uint256 n) private pure returns (bytes memory) {
        return abi.encodePacked("M", x.toString(), " ", y.toString(), ".5h", n.toString());
    }

    function _color(uint8 c) private pure returns (bytes memory) {
        return _slice(Sprites.PALETTE, uint256(c) * 7, 7);
    }

    function _slice(bytes memory s, uint256 from, uint256 len) private pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i; i < len; i++) out[i] = s[from + i];
    }

    // ---------------------------------------------------------------- a write-once buffer

    struct Buf {
        bytes data;
        uint256 len;
    }

    function _buf(uint256 cap) private pure returns (Buf memory b) {
        b.data = new bytes(cap);
    }

    function _add(Buf memory b, bytes memory s) private pure {
        uint256 n = b.len;
        uint256 l = s.length;
        bytes memory d = b.data;
        require(n + l <= d.length, "OdometerArt: buffer");
        assembly ("memory-safe") {
            mcopy(add(add(d, 0x20), n), add(s, 0x20), l)
        }
        b.len = n + l;
    }

    function _done(Buf memory b) private pure returns (bytes memory d) {
        d = b.data;
        uint256 n = b.len;
        assembly ("memory-safe") {
            mstore(d, n)
        }
    }
}
