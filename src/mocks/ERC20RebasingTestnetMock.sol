// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ERC20RebasingMock} from "./ERC20RebasingMock.sol";

contract ERC20RebasingTestnetMock is ERC20RebasingMock {
    mapping(address => uint256) lastClaim;

    constructor(string memory name, string memory symbol, uint8 decimals) ERC20RebasingMock(name, symbol, decimals) {}

    function claim(address recipient, uint256 amount) external override returns (uint256) {
        _mint(recipient, amount);
        uint256 slope = balanceOf(msg.sender) / 365 days;
        rewards[msg.sender] = rewards[msg.sender] + slope * (block.timestamp - lastClaim[msg.sender]) - amount;
        lastClaim[msg.sender] = block.timestamp;
        return amount;
    }

    function getClaimableAmount(address account) public view override returns (uint256) {
        return rewards[account] + balanceOf(account) / 365 days * (block.timestamp - lastClaim[account]);
    }

    function mint(address to, uint256 value) public virtual override {
        lastClaim[msg.sender] = block.timestamp;
        _mint(to, value);
    }
}
