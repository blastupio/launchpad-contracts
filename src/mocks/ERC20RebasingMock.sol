// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ERC20Mock} from "./ERC20Mock.sol";
import {YieldMode} from "../interfaces/IERC20Rebasing.sol";

contract ERC20RebasingMock is ERC20Mock {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20Mock(name, symbol, decimals) {}

    mapping(address => uint256) rewards;

    function configure(YieldMode) external pure returns (uint256) {
        return 0;
    }

    function claim(address recipient, uint256 amount) external returns (uint256) {
        _mint(recipient, amount);
        rewards[msg.sender] -= amount;
        return amount;
    }

    function getClaimableAmount(address account) public view returns (uint256) {
        return rewards[account];
    }

    function addRewards(address account, uint256 amount) public {
        rewards[account] += amount;
    }
}
