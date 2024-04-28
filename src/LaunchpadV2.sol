// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {ILaunchpadV2, LaunchpadDataTypes as Types} from "./interfaces/ILaunchpadV2.sol";
import {BLPStaking} from "./BLPStaking.sol";
import {Launchpad} from "./Launchpad.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";

contract LaunchpadV2 is Launchpad {
    address public blpStaking;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _weth, address _usdb, address _oracle, address _yieldStaking)
        Launchpad(_weth, _usdb, _oracle, _yieldStaking)
    {}

    function initializeV2(address _blpStaking, address _points, address _pointsOperator) public reinitializer(2) {
        blpStaking = _blpStaking;
        IBlastPoints(_points).configurePointsOperator(_pointsOperator);
    }

    /* ========== FUNCTIONS ========== */

    function registerV2(address token, Types.UserTiers tier) external {
        require(!placedTokens[token].approved, "BlastUP: you need to use register with approve function");
        (uint256 amountOfTokens,,,) = BLPStaking(blpStaking).users(msg.sender);
        _register(amountOfTokens, token, tier);
    }

    function registerV2WithApprove(address token, Types.UserTiers tier, bytes memory signature) external {
        (uint256 amountOfTokens,,,) = BLPStaking(blpStaking).users(msg.sender);
        _validateApproveSignature(msg.sender, token, signature);
        _register(amountOfTokens, token, tier);
    }

    function register(address, Types.UserTiers, uint256, bytes memory) external pure override {
        revert("Not implemented");
    }

    function registerWithApprove(address, Types.UserTiers, uint256, bytes memory, bytes memory)
        external
        pure
        override
    {
        revert("Not implemented");
    }
}
