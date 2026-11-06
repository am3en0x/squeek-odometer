// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Reading} from "../Types.sol";
import {Sprites} from "./Sprites.sol";

/// @title OdometerArt
/// @notice Renders a reading as an animated 40x40 pixel SVG and as ERC-721 metadata JSON. Layers are run data from
/// tools/sprites.py; each color group becomes one SVG path of 1-pixel strokes. Motion is frame by frame (discrete SMIL
/// opacity), so pixels stay crisp; a viewer without SMIL shows the first frame. Output goes into a buffer allocated
/// once, so a render costs linear gas.
library OdometerArt {
    using Strings for uint256;

    uint8 internal constant NAPPING = 0;
    uint8 internal constant JOGGING = 1;
    uint8 internal constant ZOOMIES = 2;

    /// @dev Palette slots the token recolors: fur and its cream (by fur), wheel ring and spokes (by stage).
    uint8 private constant FUR = 2;
    uint8 private constant CREAM = 3;
    uint8 private constant RING = 7;
    uint8 private constant SPOKE = 8;

    /// @dev Colors that change per token while drawing: [fur, cream, ring, spoke].
    struct Look {
        bytes fur;
        bytes cream;
        bytes ring;
        bytes spoke;
    }

    // ---------------------------------------------------------------- public pieces

    function svg(uint256 id, Reading memory r) internal pure returns (bytes memory) {
        Buf memory b = _buf(24_576);
        Look memory look = _look(r);
        bool awake = r.status == JOGGING || r.status == ZOOMIES;
        bool zoom = r.status == ZOOMIES;
        _add(b, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40" width="480" height="480" shape-rendering="crispEdges">');
        _add(b, abi.encodePacked('<rect width="40" height="40" fill="', _stageBg(r.stage), '"/>'));
        if (r.status == NAPPING) {
            _layer(b, Sprites.STARS, look);
            _layer(b, Sprites.MOON, look);
        }
        _layer(b, Sprites.STAND, look);
        _layer(b, Sprites.RING, look);
        if (awake) {
            bytes[] memory spokes = new bytes[](3);
            (spokes[0], spokes[1], spokes[2]) = (Sprites.SPOKES_0, Sprites.SPOKES_1, Sprites.SPOKES_2);
            _frames(b, spokes, zoom ? ".3s" : ".6s", look);
        } else {
            _layer(b, Sprites.SPOKES_0, look);
        }
        _layer(b, Sprites.HUB, look);
        if (zoom) {
            bytes[] memory lines = new bytes[](2);
            (lines[0], lines[1]) = (Sprites.ZOOMIES_0, Sprites.ZOOMIES_1);
            _frames(b, lines, ".2s", look);
        }
        if (r.stage == 6) _layer(b, awake ? Sprites.CAPE_RUN : Sprites.CAPE_NAP, look);
        _layer(b, awake ? Sprites.HAMSTER_RUN : Sprites.HAMSTER_NAP, look);
        if (awake) {
            // legs (and the Runner's shoes on them) in two frames, in step with the wheel
            bytes[] memory legs = new bytes[](2);
            bool shod = r.stage >= 3;
            legs[0] = shod ? bytes.concat(Sprites.LEGS_0, Sprites.SHOES_0) : Sprites.LEGS_0;
            legs[1] = shod ? bytes.concat(Sprites.LEGS_1, Sprites.SHOES_1) : Sprites.LEGS_1;
            _frames(b, legs, zoom ? ".2s" : ".4s", look);
        }
        _gear(b, r.stage, awake, look);
        if (r.status == NAPPING) {
            _add(b, '<g><animateTransform attributeName="transform" type="translate" values="0 0;0 -1;0 -2" dur="2.4s" calcMode="discrete" repeatCount="indefinite"/>');
            _layer(b, Sprites.ZZZ, look);
            _add(b, "</g>");
        }
        _number(b, id);
        _add(b, '<rect x="3" y="31" width="34" height="7" fill="#0b0e14"/>');
        _text(b, r.live ? kmText(r.distanceMm) : bytes("?"));
        _add(b, r.holder
            ? bytes('<rect x="1" y="1" width="38" height="38" fill="none" stroke="#f5b301" stroke-width="2"/>')
            : bytes('<rect x=".5" y=".5" width="39" height="39" fill="none" stroke="#3a4150"/>'));
        _add(b, "</svg>");
        return _done(b);
    }

    function json(uint256 id, Reading memory r) internal pure returns (bytes memory) {
        bytes memory image = bytes(Base64.encode(svg(id, r)));
        Buf memory b = _buf(image.length + 2_048);
        _add(b, abi.encodePacked('{"name":"Squeek Odometer #', id.toString(), '",'));
        _add(b, '"description":"How far Squeektoshi has run on his wheel since this odometer was minted, read live from SqueekCore on Sepolia (887 mm a wheel turn). It naps when he naps, gets the zoomies when he does, and earns gear at 1, 5, 10, 25, 50 and 100 km. Free, fully on-chain, no owner.",');
        _add(b, '"image":"data:image/svg+xml;base64,');
        _add(b, image);
        _add(b, '","attributes":[');
        _add(b, abi.encodePacked('{"trait_type":"Distance (km)","display_type":"number","value":', kmText(r.distanceMm), "},"));
        _add(b, abi.encodePacked('{"trait_type":"Stage","value":"', stageName(r.stage), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Status","value":"', statusName(r.status), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Fur","value":"', furName(r.fur), '"},'));
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

    /// @notice Fur from a roll of 0..99: Golden 40%, Cream 20%, Grey 15%, Cinnamon 10%, Shadow 8%, Ghost 6%,
    /// Shiny Gold 1%.
    function furOf(uint256 roll) internal pure returns (uint8) {
        uint8[6] memory upTo = [40, 60, 75, 85, 93, 99];
        for (uint8 i; i < 6; i++) {
            if (roll < upTo[i]) return i;
        }
        return 6;
    }

    function furName(uint8 f) internal pure returns (string memory) {
        if (f == 0) return "Golden";
        if (f == 1) return "Cream";
        if (f == 2) return "Grey";
        if (f == 3) return "Cinnamon";
        if (f == 4) return "Shadow";
        if (f == 5) return "Ghost";
        return "Shiny Gold";
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
        if (s == JOGGING) return "Jogging";
        if (s == ZOOMIES) return "Zoomies";
        return "Unknown";
    }

    // ---------------------------------------------------------------- scene parts

    function _stageBg(uint8 s) private pure returns (bytes memory) {
        return _slice("#1b2232#1c2a38#1b3530#273520#3a2c1c#3a1c2a#2a1c3a", uint256(s > 6 ? 6 : s) * 7, 7);
    }

    /// @dev Fur and cream by the token's fur; the wheel is steel, then bronze for a Runner, silver for a
    /// Marathoner, gold for a Legend.
    function _look(Reading memory r) private pure returns (Look memory l) {
        uint256 f = r.fur > 6 ? 6 : r.fur;
        l.fur = _slice("#e89b47#f0cf96#9ea4b1#b9652f#4a403d#eef0f6#ffc93a", f * 7, 7);
        l.cream = _slice("#fde4b8#fff4dc#e4e7ee#f2c39a#a8968c#ffffff#fff0a8", f * 7, 7);
        uint256 tier = r.stage >= 6 ? 3 : r.stage >= 5 ? 2 : r.stage >= 3 ? 1 : 0;
        l.ring = _slice("#8b95a8#c98a4b#d7dde8#f5c542", tier * 7, 7);
        l.spoke = _slice("#566074#7a5230#8c95a6#a8801c", tier * 7, 7);
    }

    /// @dev Gear earned by distance; earlier stages' gear stays on (the sweat drop goes once he is a Legend).
    /// The Runner's shoes are drawn with the legs.
    function _gear(Buf memory b, uint8 stage, bool awake, Look memory look) private pure {
        if (stage >= 1 && stage < 6) _layer(b, awake ? Sprites.SWEAT_RUN : Sprites.SWEAT_NAP, look);
        if (stage >= 2) _layer(b, awake ? Sprites.HEADBAND_RUN : Sprites.HEADBAND_NAP, look);
        if (stage >= 4) _layer(b, awake ? Sprites.BIB_RUN : Sprites.BIB_NAP, look);
        if (stage >= 5) _layer(b, awake ? Sprites.MEDAL_RUN : Sprites.MEDAL_NAP, look);
        if (stage == 6) _layer(b, awake ? Sprites.CROWN_RUN : Sprites.CROWN_NAP, look);
    }

    /// @dev Frames shown one after another: frame i is opaque in step i of `dur` and transparent otherwise. The first
    /// frame starts opaque, so a still render shows it.
    function _frames(Buf memory b, bytes[] memory frames, string memory dur, Look memory look) private pure {
        uint256 n = frames.length;
        for (uint256 i; i < n; i++) {
            bytes memory seq;
            for (uint256 k; k < n; k++) seq = abi.encodePacked(seq, k == 0 ? "" : ";", k == i ? "1" : "0");
            _add(b, abi.encodePacked('<g opacity="', i == 0 ? "1" : "0", '"><animate attributeName="opacity" values="', seq,
                '" dur="', dur, '" calcMode="discrete" repeatCount="indefinite"/>'));
            _layer(b, frames[i], look);
            _add(b, "</g>");
        }
    }

    /// @dev Groups of [color, runs, (x, y, length) * runs] -> one path per group.
    function _layer(Buf memory b, bytes memory data, Look memory look) private pure {
        uint256 i;
        while (i < data.length) {
            uint8 c = uint8(data[i]);
            uint256 runs = uint8(data[i + 1]);
            i += 2;
            _add(b, abi.encodePacked('<path stroke="', _color(c, look), '" d="'));
            for (uint256 k; k < runs; k++) {
                _add(b, _run(uint8(data[i]), uint8(data[i + 1]), uint8(data[i + 2])));
                i += 3;
            }
            _add(b, '"/>');
        }
    }

    /// @dev The odometer: unlit "8" segments under every digit, the digits in green, the unit in grey.
    function _text(Buf memory b, bytes memory digits) private pure {
        _add(b, '<path stroke="#173a22" d="');
        uint256 x = 5;
        for (uint256 i; i < digits.length; i++) x = _glyph(b, digits[i] == "." ? bytes1(".") : bytes1("8"), x, 32);
        _add(b, '"/><path stroke="#7dff9b" d="');
        x = 5;
        for (uint256 i; i < digits.length; i++) x = _glyph(b, digits[i], x, 32);
        _add(b, '"/><path stroke="#8a93a6" d="');
        x = _glyph(b, "K", x, 32);
        _glyph(b, "M", x, 32);
        _add(b, '"/>');
    }

    /// @dev The token number, small and dim in the top right corner.
    function _number(Buf memory b, uint256 id) private pure {
        bytes memory n = bytes(id.toString());
        uint256 x = 37 - (n.length * 4 - 1);
        _add(b, '<path stroke="#454c5c" d="');
        for (uint256 i; i < n.length; i++) x = _glyph(b, n[i], x, 3);
        _add(b, '"/>');
    }

    function _glyph(Buf memory b, bytes1 ch, uint256 x, uint256 y) private pure returns (uint256) {
        bytes memory g = Sprites.glyph(ch);
        if (g.length == 0) return x;
        uint256 runs = uint8(g[1]);
        for (uint256 k; k < runs; k++) {
            uint256 o = 2 + k * 3;
            _add(b, _run(x + uint8(g[o]), y + uint8(g[o + 1]), uint8(g[o + 2])));
        }
        return x + uint8(g[0]) + 1;
    }

    function _run(uint256 x, uint256 y, uint256 n) private pure returns (bytes memory) {
        return abi.encodePacked("M", x.toString(), " ", y.toString(), ".5h", n.toString());
    }

    function _color(uint8 c, Look memory look) private pure returns (bytes memory) {
        if (c == FUR) return look.fur;
        if (c == CREAM) return look.cream;
        if (c == RING) return look.ring;
        if (c == SPOKE) return look.spoke;
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
