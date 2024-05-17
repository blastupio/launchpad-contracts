// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {ILaunchpadV2, LaunchpadDataTypes as Types} from "./interfaces/ILaunchpadV2.sol";
import {BLPStaking} from "./BLPStaking.sol";
import {Launchpad} from "./Launchpad.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";

/// @notice Upgrade of Launchpad contract directly using BLPStaking contract for fetching
/// BLP balances instead of relying on off-chain signatures.
///
/// Will be activated once BLP tokens are distributed and BLPStaking is released.
///
/// Previous registration methods are overriden and disabled.
contract LaunchpadV2 is Launchpad {
    address public blpStaking;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _weth, address _usdb, address _oracle, address _yieldStaking)
        Launchpad(_weth, _usdb, _oracle, _yieldStaking)
    {}

    function initializeV2(address _blpStaking) public reinitializer(2) {
        blpStaking = _blpStaking;
    }

    /* ========== FUNCTIONS ========== */

    function registerV2(uint256 id, Types.UserTiers tier) external {
        require(!placedTokens[id].approved, "BlastUP: you need to use register with approve function");
        (uint256 amountOfTokens,,,) = BLPStaking(blpStaking).users(msg.sender);
        _register(amountOfTokens, id, tier);
    }

    function registerV2WithApprove(uint256 id, Types.UserTiers tier, bytes memory signature) external {
        (uint256 amountOfTokens,,,) = BLPStaking(blpStaking).users(msg.sender);
        _validateApproveSignature(msg.sender, id, signature);
        _register(amountOfTokens, id, tier);
    }

    function register(uint256, Types.UserTiers, uint256, bytes memory) external pure override {
        revert("Not implemented");
    }

    function registerWithApprove(uint256, Types.UserTiers, uint256, bytes memory, bytes memory)
        external
        pure
        override
    {
        revert("Not implemented");
    }

    function buyWithRegister(uint256, address, uint256, bytes memory, uint256) external payable override {
        revert("Not implemented");
    }

    function buyWithRegisterV2(uint256 id, address paymentContract, uint256 volume) external payable {
        (uint256 amountOfTokens,,,) = BLPStaking(blpStaking).users(msg.sender);
        require(
            amountOfTokens >= minAmountForTier[placedTokens[id].fcfsRequiredTier],
            "BlastUP: you do not have enough BLP tokens"
        );
        require(getStatus(id) == Types.SaleStatus.FCFS_SALE, "BlastUP: invalid status");
        require(placedTokens[id].fcfsOpened, "BlastUP: fcfs for all holders is not open");
        users[id][msg.sender].registered = true;
        users[id][msg.sender].tier = placedTokens[id].fcfsRequiredTier;
        _buyTokens(id, paymentContract, volume, msg.sender, bytes(""));
    }
}
