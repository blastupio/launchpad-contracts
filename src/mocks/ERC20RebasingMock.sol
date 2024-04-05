// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {TokenERC20} from "./TokenERC20Mock.sol";
import {YieldMode} from "../interfaces/IERC20Rebasing.sol";

contract ERC20RebasingMock is TokenERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) TokenERC20(name, symbol, decimals) {}

    function configure(YieldMode) external pure returns (uint256) {
        return 0;
    }

    function claim(address recipient, uint256 amount) external returns (uint256) {
        _balanceOf[recipient] = _add(_balanceOf[recipient], amount);
        return amount;
    }

    function getClaimableAmount(address account) public view returns (uint256) {
        return _balanceOf[account] * 0.1e18 / 1e18;
    }
}
