// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {ERC20Mock} from "../../BaseLaunchpad.t.sol";

struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}

library LibAddressSet {
    function add(AddressSet storage s, address addr) internal {
        if (!s.saved[addr]) {
            s.addrs.push(addr);
            s.saved[addr] = true;
        }
    }

    function contains(AddressSet storage s, address addr) internal view returns (bool) {
        return s.saved[addr];
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return s.addrs.length;
    }

    function randActor(AddressSet storage s, uint256 seed) internal returns (address) {
        if (s.addrs.length > 0) {
            return s.addrs[seed % s.addrs.length];
        } else {
            add(s, address(153));
            add(s, address(1532));
            add(s, address(15342));
            add(s, address(153421));
            return address(153);
        }
    }

    function randToken(AddressSet storage s, uint256 seed) internal view returns (address, uint256) {
        if (s.addrs.length > 0) {
            return (s.addrs[seed % s.addrs.length], seed % s.addrs.length);
        } else {
            return (address(0), 0);
        }
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function forEachPlusArgument(AddressSet storage s, uint256 id, function(address, uint) external func)
        internal
    {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i], id);
        }
    }

    function reduce(AddressSet storage s, uint256 acc, function(uint256,address) external returns (uint256) func)
        internal
        returns (uint256)
    {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }
}
