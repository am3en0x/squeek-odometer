// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Everything an odometer token shows, derived from Squeekchain on every read.
struct Reading {
    uint256 startWork; // SqueekCore cumulativeWork when the token was minted
    uint256 work; // settled work since then (one unit = one wheel turn)
    uint256 distanceMm; // work * MM_PER_WORK
    uint8 stage; // 0 Newbie .. 6 Legend
    uint8 status; // 0 napping, 1 jogging, 2 zoomies, 3 unknown
    bool holder; // the token's owner holds a Squeek, in the wallet or deposited in staking
    uint64 blockHeight; // Squeek block height
    bool live; // SqueekCore answered
}
