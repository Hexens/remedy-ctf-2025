from typing import Dict
from web3 import Web3
import json

from ctf_launchers.pwn_launcher import PwnChallengeLauncher
from ctf_launchers.utils import deploy
from ctf_server.types import LaunchAnvilInstanceArgs, UserData, get_privileged_web3, get_system_account
from foundry.anvil import check_error
from foundry.anvil import anvil_setCode

class Challenge(PwnChallengeLauncher):
    def deploy(self, user_data: UserData, mnemonic: str) -> str:
        web3 = get_privileged_web3(user_data, "main")
        system_addr = get_system_account(mnemonic)

        # Deploy the new routers to mainnet!
        with open('challenge/project/src/tokemak/vault/AutopilotRouter.bytecode', 'r') as f:
            anvil_setCode(web3, '0xC45e939ca8C43822A2A233404Ecf420712084c30', f.read())
        with open('challenge/project/src/tokemak/swapper/SwapRouterV2.bytecode', 'r') as f:
            anvil_setCode(web3, '0x6201523176dC66CCd249248b9c422Aac725eA3f2', f.read())

        return deploy(
            web3, self.project_location, mnemonic, env=self.get_deployment_args(user_data)
        )

    def get_anvil_instances(self) -> Dict[str, LaunchAnvilInstanceArgs]:
        return {
            "main": self.get_anvil_instance(fork_block_num=21691704, balance=1)
        }

Challenge().run()