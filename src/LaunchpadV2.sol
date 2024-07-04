// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {LaunchpadDataTypes as Types} from "./libraries/LaunchpadDataTypes.sol";
import {BLPBalanceOracle} from "@blastup-token/BLPBalanceOracle.sol";
import {Launchpad} from "./Launchpad.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";

/// @notice Upgrade of Launchpad contract directly using BLPStaking contract for fetching
/// BLP balances instead of relying on off-chain signatures.
///
/// Will be activated once BLP tokens are distributed and BLPStaking is released.
///
/// Previous registration methods are overriden and disabled.
contract LaunchpadV2 is Launchpad {
    address public blpBalanceOracle;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _weth, address _usdb, address _oracle, address _yieldStaking)
        Launchpad(_weth, _usdb, _oracle, _yieldStaking)
    {}

    function initializeV2(address _blpBalanceOracle) public reinitializer(2) {
        blpBalanceOracle = _blpBalanceOracle;
    }

    /* ========== FUNCTIONS ========== */

    function register(uint256 id, Types.UserTiers tier, uint256, bytes memory) public override {
        require(!placedTokens[id].approved, "BlastUP: you need to use register with approve function");
        uint256 amountOfTokens = BLPBalanceOracle(blpBalanceOracle).balanceOf(msg.sender);
        _register(amountOfTokens, id, tier);
    }

    function registerWithApprove(uint256 id, Types.UserTiers tier, uint256, bytes memory, bytes memory approveSignature)
        external
        override
    {
        uint256 amountOfTokens = BLPBalanceOracle(blpBalanceOracle).balanceOf(msg.sender);
        _validateApproveSignature(msg.sender, id, approveSignature);
        _register(amountOfTokens, id, tier);
    }
}
