# On-Chain Swappers

The SwapRouter defined here is used for swapping assets back to the base asset during a users withdrawal flow. This registry of routes will need to be maintained to ensure optimal results for the user. Each of these swappers take and enforce a "min amount" check, but because of how they are used will always receive 0 for that value. An off-chain users withdrawal flow should always start at the LMPVaultRouter which forces an account for slippage. Any on-chain interaction with the vaults should enforce their own slippage checks as they see fit.
