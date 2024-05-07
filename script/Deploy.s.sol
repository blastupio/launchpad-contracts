// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.1;

import {Script, console} from "forge-std/Script.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {YieldStaking} from "../src/YieldStaking.sol";
import {Launchpad, MessageHashUtils, ECDSA} from "../src/Launchpad.sol";
import {ILaunchpad} from "../src/interfaces/ILaunchpad.sol";
import {LaunchpadV2} from "../src/LaunchpadV2.sol";
import {BLPStaking} from "../src/BLPStaking.sol";

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

    function _deploy(address WETH, address USDB, address oracle, address points)
        public
        returns (Launchpad launchpad, YieldStaking staking, address proxyAdmin)
    {
        (, address deployer,) = vm.readCallers();

        uint256 nonce = vm.getNonce(deployer);
        address stakingAddress = vm.computeCreateAddress(deployer, nonce + 3);
        launchpad = Launchpad(
            address(
                new TransparentUpgradeableProxy(
                    address(new Launchpad(address(WETH), address(USDB), address(oracle), stakingAddress)),
                    deployer,
                    abi.encodeCall(Launchpad.initialize, (deployer, deployer, deployer, points, deployer))
                )
            )
        );
        proxyAdmin = vm.computeCreateAddress(address(launchpad), 1);
        staking = YieldStaking(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new YieldStaking(address(launchpad), address(oracle), address(USDB), address(WETH))),
                        deployer,
                        abi.encodeCall(YieldStaking.initialize, (deployer, points, deployer))
                    )
                )
            )
        );

        console.log("launchpad ", address(launchpad));
        console.log("staking: ", address(staking));
        console.log("proxy admin: ", proxyAdmin);
    }

    function deploySepolia() public {
        vm.startBroadcast();

        ERC20RebasingMock USDB = ERC20RebasingTestnetMock(0x66Ed1EEB6CEF5D4aCE858890704Af9c339266276);
        ERC20RebasingMock WETH = WETHRebasingTestnetMock(0x3470769fBA0Aa949ecdAF83CAD069Fa2DC677389);
        address oracle = 0xc447B8cAd2db7a8B0fDde540B038C9e06179c0f7;
        address points = 0x2fc95838c71e76ec69ff817983BFf17c710F34E0;

        console.log("usdb: ", address(USDB));
        console.log("weth: ", address(WETH));

        _deploy(address(WETH), address(USDB), oracle, points);

        vm.stopBroadcast();
    }

    function deploySepoliaV2() public {
        vm.startBroadcast();

        address USDB = 0x66Ed1EEB6CEF5D4aCE858890704Af9c339266276;
        address WETH = 0x3470769fBA0Aa949ecdAF83CAD069Fa2DC677389;
        address oracle = 0xc447B8cAd2db7a8B0fDde540B038C9e06179c0f7;
        address points = 0x2fc95838c71e76ec69ff817983BFf17c710F34E0;

        (Launchpad launchpad, YieldStaking yieldStaking, address proxyAdmin) = _deploy(WETH, USDB, oracle, points);

        (, address deployer,) = vm.readCallers();

        ERC20Mock blp = new ERC20Mock("BlastUP", "BLP", 18);

        BLPStaking blpStaking = new BLPStaking(address(blp), deployer, points, deployer);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(launchpad)),
            address(new LaunchpadV2(address(WETH), address(USDB), address(oracle), address(yieldStaking))),
            abi.encodeCall(LaunchpadV2.initializeV2, (address(blpStaking), points, deployer))
        );

        console.log("BLP: ", address(blp));
        console.log("BLPStaking: ", address(blpStaking));

        vm.stopBroadcast();
    }
}
