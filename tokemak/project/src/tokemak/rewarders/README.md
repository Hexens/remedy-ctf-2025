# Rewards Contracts Architecture

The rewards architecture consists of a few main contracts:

-   AutopoolMainRewarder,
-   DestinationVaultMainRewarder,
-   MainRewarder,
-   ExtraRewarder

The purpose of these contracts is to distribute rewards to users who stake their tokens.

## AutopoolMainRewarder

The AutopoolMainRewarder contract is responsible for Autopool rewards. This contract takes control of a user's Autopool tokens, and is meant to be interacted with via the AutopoolRouter and directly by the user. This contract inherits the majority of its functionality from the MainRewarder and AbstractRewarder contracts.

## DestinationVaultMainRewarder

The DestinationVaultMainRewarder is responsible for Destination Vault rewards. This contract does not take control of tokens, and can only be interacted with via its paired Destination Vault contract, also known as a stake tracker. Much like the AutopoolMainRewarder, this contract inherits most of its functionality from the MainRewarder and AbstractRewarder contracts.

## MainRewarder

The MainRewarder contract is responsible for distributing the main reward tokens to stakers. This contract is abstract, staking, withdrawing and one of the two `getReward()` functions need to be inherited to be accessible.

The operator can queue new rewards to be distributed to stakers using the queueNewRewards function. The rewards are added to a reward queue, which is then distributed to stakers based on their staked balances.

The addExtraReward function adds the address of the ExtraRewarder contract to a list of ExtraRewarder contracts that can distribute additional rewards to stakers. When a user calls the getReward function, the MainRewarder contract distributes rewards from the main reward queue and all extra reward queues. The amount of rewards distributed from each queue is proportional to the user's staked balance.

The MainRewarder contract also includes a stake and withdraw functions that allow any contract tracking stakes to keep track of liquidity moves like stake or withdraw.
It keeps track of both user balances and the total supply. It acts as a duplicate ledger of the Vault, but ensures that rewards are not mistakenly given to others.
The order in which balances and rewards are updated is important.
Thus, we maintain a balance tracking mechanism within the MainRewarder contract to preserve the order of operations.

## ExtraRewarder

The ExtraRewarder contract is a simpler version of the MainRewarder contract and is responsible for distributing additional reward tokens to stakers.

## Difference between Main and Extra Rewarders

The main distinction between the MainRewarder and the ExtraRewarder lies in their balance tracking mechanisms. The MainRewarder keeps track of both user balances and the total supply internally whereas the ExtraRewarder does not maintain its own balance or total supply records; instead, it retrieves these values from the MainRewarder.
