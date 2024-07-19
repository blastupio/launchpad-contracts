// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.1;

import {Script, console} from "forge-std/Script.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin,
    ITransparentUpgradeableProxy,
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {YieldStaking} from "../src/YieldStaking.sol";
import {Launchpad, MessageHashUtils, ECDSA} from "../src/Launchpad.sol";
import {ILaunchpad} from "../src/interfaces/ILaunchpad.sol";
import {LaunchpadV2} from "../src/LaunchpadV2.sol";

import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {OracleMock} from "../src/mocks/OracleMock.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {WETHRebasingMock} from "../src/mocks/WETHRebasingMock.sol";
import {ERC20RebasingMock} from "../src/mocks/ERC20RebasingMock.sol";
import {ERC20RebasingTestnetMock} from "../src/mocks/ERC20RebasingTestnetMock.sol";
import {WETHRebasingTestnetMock} from "../src/mocks/WETHRebasingTestnetMock.sol";

import {Deposit} from "../src/Deposit.sol";

contract DeployScript is Script {
    using SafeERC20 for IERC20;

    function deploy(
        address weth,
        address usdb,
        address oracle,
        address points,
        address dao,
        address operator,
        address signer,
        address pointsOperator
    ) public {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        uint256 nonce = vm.getNonce(deployer);
        address stakingAddress = vm.computeCreateAddress(deployer, nonce + 3);
        Launchpad launchpad = Launchpad(
            address(
                new TransparentUpgradeableProxy(
                    address(new Launchpad(weth, usdb, oracle, stakingAddress)),
                    dao,
                    abi.encodeCall(Launchpad.initialize, (dao, signer, operator, points, pointsOperator))
                )
            )
        );
        YieldStaking staking = YieldStaking(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStaking(address(launchpad), oracle, usdb, weth)),
                        dao,
                        abi.encodeCall(YieldStaking.initialize, (dao, points, pointsOperator))
                    )
                )
            )
        );

        console.log("Launchpad:", address(launchpad));
        console.log("Staking:", address(staking));
        console.log("Launchpad proxy admin:", vm.computeCreateAddress(address(launchpad), 1));
        console.log("Staking proxy admin:", vm.computeCreateAddress(address(staking), 1));
    }

    function deployAndUpgradeV2(Launchpad launchpad, address blpBalanceOracle) public {
        ProxyAdmin proxyAdmin =
            ProxyAdmin(address(uint160(uint256(vm.load(address(launchpad), ERC1967Utils.ADMIN_SLOT)))));

        vm.startBroadcast();

        LaunchpadV2 launchpadV2 = new LaunchpadV2(
            address(launchpad.WETH()), address(launchpad.USDB()), address(launchpad.oracle()), launchpad.yieldStaking()
        );

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(launchpad)),
            address(launchpadV2),
            abi.encodeCall(LaunchpadV2.initializeV2, (blpBalanceOracle))
        );
    }

    function deployDeposit(address admin, address signer, address depositReceiver) public {
        vm.startBroadcast();
        Deposit deposit = new Deposit(admin, signer, depositReceiver);

        console.log("Deposit:", address(deposit)); 
    }
}
