// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {YieldStaking} from "../../src/YieldStaking.sol";
import {Launchpad, MessageHashUtils, ECDSA} from "../../src/Launchpad.sol";
import {ILaunchpad} from "../../src/interfaces/ILaunchpad.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BLPStaking} from "../../src/BLPStaking.sol";

contract BaseBLPStaking is Test {
    ERC20Mock blp;

    address internal admin;
    uint256 internal adminPrivateKey;

    uint256 initialBalanceOfStaking;
    BLPStaking stakingBLP;

    address user;
    address user2;
    address user3;

    function setUp() public virtual {
        adminPrivateKey = 0xa11ce;
        admin = vm.addr(adminPrivateKey);
        user = address(10);
        user2 = address(11);
        user3 = address(12);

        vm.startPrank(admin);
        blp = new ERC20Mock("BlastUp", "BLP", 18);
        stakingBLP = new BLPStaking(address(blp), admin);
        initialBalanceOfStaking = 1e50;
        blp.mint(address(stakingBLP), initialBalanceOfStaking);
        vm.stopPrank();
    }
}
