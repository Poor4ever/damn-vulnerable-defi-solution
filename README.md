# Damn Vulnerable Defi 解决方案
[Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) 是由[@tinchoabbate](https://twitter.com/tinchoabbate)创建的学习DeFi智能合约安全攻击的战争游戏.


使用 [Foundry](https://github.com/foundry-rs/foundry)  完成.



# #1 - Unstoppable

合约:

- [DamnValuableToken](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/DamnValuableToken.sol)  Token 合约
-  [UnstoppableLender](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/unstoppable/UnstoppableLender.sol)   借贷池合约
- [ReceiverUnstoppable](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/unstoppable/ReceiverUnstoppable.sol) 调用借贷池的闪电贷合约



完成条件:

借贷池里有 100 万 个 DVT 代币,免费提供闪电贷,你初始拥有 100 个 DVT 代币,你需要攻击使借贷池合约 flashlaon 失效.



解决方案:

UnstoppableLender 合约 **flashLoan** 函数 在 **transfer** 代币到调用的合约前, 函数中有 assert 检查条件 `poolBalance == balanceBefore`,如果我们通过调用借贷池合约 **depositTokens** 函数存入代币是会正常更新 poolBalance, 能通过 assert 条件检查的 

```solidity
uint256 balanceBefore = damnValuableToken.balanceOf(address(this));
assert(poolBalance == balanceBefore);
```

而直接调用 `DVT Token` 合约 **transfer** 直接向借贷池合约发送代币, 不会更新 **poolBalance**,而 **flashLoan** 函数的 assert 检查  **poolBalance == balanceBefore** 无法通过, `ReceiverUnstoppable`合约调用借贷池合约 **flashLoan** 函数将不再正常工作.



使用 foundry 测试:

[Unstoppable.t.sol](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/test/Unstoppable.t.sol)

```
forge test --match-contract Unstoppable -vvvv
```

![Unstoppable](./testimage/Unstoppable.png)



# #2 - Naive receiver

合约:

- [NaiveReceiverLenderPool](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/NaiveReceiverLenderPool.sol)  借贷池合约
- [FlashLoanReceiver](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/unstoppable/FlashLoanReceiver.sol)   调用借贷池的闪电贷合约

完成条件:

有一个 `NaiveReceiverLenderPool` 借贷池合约提供了相当昂贵手续费的 ETH 闪电贷,余额为 1000 ETH,用户部署的 余额为 10 ETH 的 FlashLoanReceiver 合约与借贷池合约 **flashLoan** 函数交互接收 ETH.需要耗尽用户合约中的所有 ETH 资金.



解决方案:

 `NaiveReceiverLenderPool`合约 **flashLoan** 函数两个参数, borrower 为借款的合约的地址, borrowAmount 为借款的 ETH数.函数里functionCallWithValue 发送借款 ETH 金额到借款的合约并调用借款合约的 `receiveEther` ,最后 require 检查借贷池的合约里余额得为借款前余额+ `FIXED_FEE` ,也就是说每笔闪电贷调用,用户合约需要支付 1 ETH  的手续费.

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

使用 foundry 测试:

```
forge test --match-contract NaiveReceiver -vvvv
```

![NaiveReceiver](./testimage/NaiveReceiver.png)
