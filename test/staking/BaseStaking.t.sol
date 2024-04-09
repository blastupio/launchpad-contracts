// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Staking} from "../../src/YieldStaking.sol";
import {Launchpad} from "../../src/Launchpad.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {OracleMock} from "../../src/mocks/OracleMock.sol";
import {WETHRebasingMock} from "../../src/mocks/WETHRebasingMock.sol";
import {ERC20RebasingMock} from "../../src/mocks/ERC20RebasingMock.sol";

import {WadMath} from "../../src/libraries/WadMath.sol";

contract BaseStakingTest is Test {
    Staking staking;
    Launchpad launchpad;

    ERC20Mock blp;
    ERC20Mock testToken;

    OracleMock oracle;

    address internal admin;
    uint256 internal adminPrivateKey;
    address user;
    address user2;
    address user3;

    ERC20RebasingMock constant USDB = ERC20RebasingMock(0x4300000000000000000000000000000000000003);
    WETHRebasingMock constant WETH = WETHRebasingMock(0x4300000000000000000000000000000000000004);

    function setUp() public virtual {
        adminPrivateKey = 0xa11ce;
        admin = vm.addr(adminPrivateKey);
        user = address(10);
        user2 = address(11);
        user3 = address(12);

        ERC20RebasingMock usdb = new ERC20RebasingMock("USDB", "USDB", 18);
        bytes memory code = address(usdb).code;
        vm.etch(0x4300000000000000000000000000000000000003, code);

        WETHRebasingMock weth = new WETHRebasingMock("WETH", "WETH", 18);
        bytes memory code2 = address(weth).code;
        vm.etch(0x4300000000000000000000000000000000000004, code2);

        blp = new ERC20Mock("BlastUp", "BLP", 18);
        testToken = new ERC20Mock("Token", "TKN", 18);
        oracle = new OracleMock();

        uint256 nonce = vm.getNonce(admin);
        address launchpadAddress = vm.computeCreateAddress(admin, nonce);
        address stakingAddress = vm.computeCreateAddress(admin, nonce + 1);

        launchpad =
            new Launchpad(address(blp), stakingAddress, address(oracle), admin, admin, address(USDB), address(WETH));
        staking = new Staking(launchpadAddress, address(blp), admin, address(oracle), address(USDB), address(WETH));
    }
}
