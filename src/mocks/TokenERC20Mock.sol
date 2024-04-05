// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract TokenERC20 is MockERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) {
        initialize(name, symbol, decimals);
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}
