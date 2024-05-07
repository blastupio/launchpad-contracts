// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {BLPStaking} from "../../src/BLPStaking.sol";
import {BlastPointsMock} from "../../src/mocks/BlastPointsMock.sol";

contract BaseBLPStaking is Test {
    ERC20Mock blp;

    address internal admin;
    uint256 internal adminPrivateKey;

    BLPStaking stakingBLP;
    BlastPointsMock points;

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
        points = new BlastPointsMock();
        stakingBLP = new BLPStaking(address(blp), admin, address(points), admin);
        vm.stopPrank();
    }
}
