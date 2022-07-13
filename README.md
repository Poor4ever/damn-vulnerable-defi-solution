# Damn Vulnerable Defi 解决方案
[Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) 是由[@tinchoabbate](https://twitter.com/tinchoabbate)创建的学习DeFi智能合约安全攻击的战争游戏.


使用 [Foundry](https://github.com/foundry-rs/foundry)  完成.

# #1 - Unstoppable

合约:

- [DamnValuableToken](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/DamnValuableToken.sol)  Token 合约
-  [UnstoppableLender](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/unstoppable/UnstoppableLender.sol)   借贷池合约
- [ReceiverUnstoppable](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/unstoppable/ReceiverUnstoppable.sol) 调用借贷池闪电贷合约



完成条件:

借贷池里有 100 万 个 DVT 代币,免费提供闪电贷,你初始拥有 100 个 DVT 代币,你需要攻击使借贷池合约 flashlon 失效.



解决方案:

UnstoppableLender 合约 **flashLoan** 函数 在 **transfer** 代币到调用的合约前, 函数中有 assert 检查条件 `poolBalance == balanceBefore`,如果我们通过调用借贷池合约 **depositTokens** 函数存入代币是会正常更新 poolBalance, 能通过 assert 条件检查的 

```sol
uint256 balanceBefore = damnValuableToken.balanceOf(address(this));
assert(poolBalance == balanceBefore);
```

而直接调用 `DVT Token` 合约 **transfer** 直接向借贷池合约发送代币, 不会更新 **poolBalance**,而 **flashLoan** 函数的 assert 检查  **poolBalance == balanceBefore** 无法通过, `ReceiverUnstoppable`合约调用借贷池合约 **flashLoan** 函数将不再正常工作.



使用 foundry 测试:

[Unstoppable.t.sol](https://github.com/Poor4ever/damn-vulnerable-defi-solution/blob/main/src/test/UnstoppableLender.t.sol)

```
forge test --match-contract Unstoppable -vvvv
```

![Unstoppable](./testimage/Unstoppable.png)
