// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ILaunchpadV2} from "./interfaces/ILaunchpadV2.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {BLPStaking} from "./BLPStaking.sol";
import {Launchpad} from "./Launchpad.sol";

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

    function registerV2(address token, UserTiers tier) external {
        PlacedToken storage placedToken = placedTokens[token];
        User storage user = users[token][msg.sender];

        (uint256 amountOfTokens,,,) = BLPStaking(blpStaking).users(msg.sender);

        require(getStatus(token) == SaleStatus.REGISTRATION, "BlastUP: invalid status");
        require(!user.registered, "BlastUP: you are already registered");
        require(minAmountForTier[tier] <= amountOfTokens, "BlastUP: you do not have enough BLP tokens for that tier");

        if (tier < UserTiers.TITANIUM) {
            placedToken.lowTiersWeightsSum += weightForTier[tier];
        } else {
            placedToken.highTiersWeightsSum += weightForTier[tier];
        }

        user.tier = tier;
        user.registered = true;

        emit UserRegistered(msg.sender, token, tier);
    }

    function register(address, UserTiers, uint256, bytes memory) external pure override {
        revert("Not implemented");
    }
}
