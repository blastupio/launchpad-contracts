// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ERC20RebasingMock} from "./ERC20RebasingMock.sol";

contract WETHRebasingMock is ERC20RebasingMock {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20RebasingMock(name, symbol, decimals) {}

    function deposit() external payable {
        _balanceOf[msg.sender] = _add(_balanceOf[msg.sender], msg.value);
    }

    function withdraw(uint256 wad) external {
        _balanceOf[msg.sender] = _sub(_balanceOf[msg.sender], wad);

        (bool success,) = payable(msg.sender).call{value: wad}("");
        require(success);
    }
}
