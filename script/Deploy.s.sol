// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.1;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {YieldStaking} from "../src/YieldStaking.sol";
import {Launchpad, MessageHashUtils, ECDSA} from "../src/Launchpad.sol";
import {ILaunchpad} from "../src/interfaces/ILaunchpad.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {OracleMock} from "../src/mocks/OracleMock.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {WETHRebasingMock} from "../src/mocks/WETHRebasingMock.sol";
import {ERC20RebasingMock} from "../src/mocks/ERC20RebasingMock.sol";
import {ERC20RebasingTestnetMock} from "../src/mocks/ERC20RebasingTestnetMock.sol";
import {WETHRebasingTestnetMock} from "../src/mocks/WETHRebasingTestnetMock.sol";

contract DeployScript is Script {
    using SafeERC20 for IERC20;

    function _deploy(address WETH, address USDB, address oracle, address points) public {
        (, address deployer,) = vm.readCallers();

        uint256 nonce = vm.getNonce(deployer);
        address stakingAddress = vm.computeCreateAddress(deployer, nonce + 3);
        Launchpad launchpad = Launchpad(
            address(
                new TransparentUpgradeableProxy(
                    address(new Launchpad(address(WETH), address(USDB), address(oracle), stakingAddress)),
                    deployer,
                    abi.encodeCall(Launchpad.initialize, (deployer, deployer, deployer, points))
                )
            )
        );
        YieldStaking staking = YieldStaking(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStaking(address(launchpad), address(oracle), address(USDB), address(WETH))),
                        deployer,
                        abi.encodeCall(YieldStaking.initialize, (deployer, points))
                    )
                )
            )
        );

        console.log("launchpad ", address(launchpad));
        console.log("staking: ", address(staking));
    }

    function deploySepolia() public {
        vm.startBroadcast();

        ERC20RebasingMock USDB = new ERC20RebasingTestnetMock("USDB", "USDB", 18);
        ERC20RebasingMock WETH = new WETHRebasingTestnetMock("WETH", "WETH", 18);
        address oracle = 0xc447B8cAd2db7a8B0fDde540B038C9e06179c0f7;
        address points = 0x2fc95838c71e76ec69ff817983BFf17c710F34E0;

        console.log("usdb: ", address(USDB));
        console.log("weth: ", address(WETH));

        _deploy(address(WETH), address(USDB), oracle, points);

        vm.stopBroadcast();
    }
}
