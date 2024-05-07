// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {YieldStaking} from "../../src/YieldStaking.sol";
import {Launchpad, MessageHashUtils, ECDSA, Types} from "../../src/Launchpad.sol";
import {ILaunchpad} from "../../src/interfaces/ILaunchpad.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {OracleMock} from "../../src/mocks/OracleMock.sol";
import {WETHRebasingMock} from "../../src/mocks/WETHRebasingMock.sol";
import {ERC20RebasingMock} from "../../src/mocks/ERC20RebasingMock.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BlastPointsMock} from "../../src/mocks/BlastPointsMock.sol";

contract BaseLaunchpadTest is Test {
    YieldStaking staking;
    Launchpad launchpad;
    ProxyAdmin proxyAdmin;

    ERC20Mock blp;
    ERC20Mock testToken;
    ERC20Mock testToken2;

    OracleMock oracle;
    BlastPointsMock points;

    address internal admin;
    uint256 internal adminPrivateKey;
    address signer;
    uint256 internal signerPrivateKey;
    address user;
    address user2;
    address user3;
    address user4;
    address user5;
    address user6;

    ERC20RebasingMock constant USDB = ERC20RebasingMock(0x4300000000000000000000000000000000000003);
    WETHRebasingMock constant WETH = WETHRebasingMock(0x4300000000000000000000000000000000000004);

    function setUp() public virtual {
        adminPrivateKey = 0xa11ce;
        signerPrivateKey = 0xa3f9a14bc;
        admin = vm.addr(adminPrivateKey);
        signer = vm.addr(signerPrivateKey);
        user = address(10);
        user2 = address(11);
        user3 = address(12);
        user4 = address(13);
        user5 = address(14);
        user6 = address(15);

        ERC20RebasingMock usdb = new ERC20RebasingMock("USDB", "USDB", 18);
        bytes memory code = address(usdb).code;
        vm.etch(0x4300000000000000000000000000000000000003, code);

        WETHRebasingMock weth = new WETHRebasingMock("WETH", "WETH", 18);
        bytes memory code2 = address(weth).code;
        vm.etch(0x4300000000000000000000000000000000000004, code2);

        blp = new ERC20Mock("BlastUp", "BLP", 18);
        testToken = new ERC20Mock("Token", "TKN", 18);
        testToken2 = new ERC20Mock("Token", "TKN", 18);
        oracle = new OracleMock();
        points = new BlastPointsMock();

        uint256 nonce = vm.getNonce(admin);
        address stakingAddress = vm.computeCreateAddress(admin, nonce + 3);
        vm.startPrank(admin);
        launchpad = Launchpad(
            address(
                new TransparentUpgradeableProxy(
                    address(new Launchpad(address(WETH), address(USDB), address(oracle), stakingAddress)),
                    admin,
                    abi.encodeCall(Launchpad.initialize, (admin, admin, admin, address(points), admin))
                )
            )
        );
        proxyAdmin = ProxyAdmin(vm.computeCreateAddress(address(launchpad), 1));
        staking = YieldStaking(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStaking(address(launchpad), address(oracle), address(USDB), address(WETH))),
                        admin,
                        abi.encodeCall(YieldStaking.initialize, (admin, address(points), admin))
                    )
                )
            )
        );
        assert(address(staking) == launchpad.yieldStaking());
        assert(address(launchpad) == address(staking.launchpad()));
        vm.stopPrank();
    }
}
