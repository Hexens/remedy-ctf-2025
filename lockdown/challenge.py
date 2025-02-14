from typing import Dict
from web3 import Web3

from ctf_launchers.pwn_launcher import PwnChallengeLauncher
from ctf_launchers.utils import deploy
from ctf_server.types import LaunchAnvilInstanceArgs, UserData, get_privileged_web3, get_system_account
from foundry.anvil import check_error

class Challenge(PwnChallengeLauncher):
    def deploy(self, user_data: UserData, mnemonic: str) -> str:
        web3 = get_privileged_web3(user_data, "main")
        system_addr = get_system_account(mnemonic)

        # Update the USDC balance of the system address to 1,000,520
        check_error(web3.provider.make_request("anvil_setStorageAt", [
            "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 
            Web3.keccak((12 * b'\x00') + bytes.fromhex(system_addr.address[2:]) + (31 * b'\x00') + b'\x09').hex(), 
            "0x000000000000000000000000000000000000000000000000000000e8f3a3a200"
        ]))

        return deploy(
            web3, self.project_location, mnemonic, env=self.get_deployment_args(user_data)
        )

    def get_anvil_instances(self) -> Dict[str, LaunchAnvilInstanceArgs]:
        return {
            "main": self.get_anvil_instance(fork_block_num=21614313,balance=10)
        }

Challenge().run()