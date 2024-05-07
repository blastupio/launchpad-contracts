// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ERC20RebasingTestnetMock} from "./ERC20RebasingTestnetMock.sol";
import {WETHRebasingMock} from "./WETHRebasingMock.sol";

contract WETHRebasingTestnetMock is ERC20RebasingTestnetMock {
    constructor(string memory name, string memory symbol, uint8 decimals)
        ERC20RebasingTestnetMock(name, symbol, decimals)
    {}

    function deposit() external payable {
        mint(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        _burn(msg.sender, wad);

        (bool success,) = payable(msg.sender).call{value: wad}("");
        require(success);
    }
}
