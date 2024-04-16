// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.1;

import {Script, console2} from "forge-std/Script.sol";
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

contract DeployScript is Script {
    using SafeERC20 for IERC20;

    function _deploy(address WETH, address USDB, address oracle) public {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // address admin = vm.addr(deployerPrivateKey);
        (, address admin,) = vm.readCallers();

        uint256 nonce = vm.getNonce(admin);
        address stakingAddress = vm.computeCreateAddress(admin, nonce + 3);
        Launchpad launchpad = Launchpad(
            address(
                new TransparentUpgradeableProxy(
                    address(new Launchpad(address(WETH), address(USDB), address(oracle), stakingAddress)),
                    admin,
                    abi.encodeCall(Launchpad.initialize, (admin, admin, admin))
                )
            )
        );
        YieldStaking staking = YieldStaking(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStaking(address(launchpad), address(oracle), address(USDB), address(WETH))),
                        admin,
                        abi.encodeCall(YieldStaking.initialize, (admin))
                    )
                )
            )
        );

        console2.log("launchpad ", address(launchpad));
        console2.log("staking: ", address(staking));
    }
    
    // deploy testnet 
    function run() public {
        vm.startBroadcast();

        address USDB = 0x4200000000000000000000000000000000000022;
        address WETH = 	0x4200000000000000000000000000000000000023;
        address oracle = 0xc447B8cAd2db7a8B0fDde540B038C9e06179c0f7;

        _deploy(WETH, USDB, oracle);

        vm.stopBroadcast();
    }
}
