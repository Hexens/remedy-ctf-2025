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

        # Update the LPT balance of system address to 5,000
        check_error(web3.provider.make_request("anvil_setStorageAt", [
            "0x289ba1701C2F088cf0faf8B3705246331cB8A839", 
            Web3.keccak((12 * b'\x00') + bytes.fromhex(system_addr.address[2:]) + (31 * b'\x00') + b'\x01').hex(), 
            "0x00000000000000000000000000000000000000000000010F0CF064DD59200000"
        ]))
        # Update the roundLength in RoundsManager to 10
        check_error(web3.provider.make_request("anvil_setStorageAt", [
            "0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f", 
            "0x0000000000000000000000000000000000000000000000000000000000000002",
            "0x000000000000000000000000000000000000000000000000000000000000000a"
        ]))
        # Update the lastRoundLengthUpdateRound in RoundsManager to 267164264
        check_error(web3.provider.make_request("anvil_setStorageAt", [
            "0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f", 
            "0x0000000000000000000000000000000000000000000000000000000000000005",
            "0x000000000000000000000000000000000000000000000000000000000fec9a68"
        ]))
        # Update the lastRoundLengthUpdateStartBlock in RoundsManager to 267164264
        check_error(web3.provider.make_request("anvil_setStorageAt", [
            "0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f", 
            "0x0000000000000000000000000000000000000000000000000000000000000006",
            "0x000000000000000000000000000000000000000000000000000000000fec9a68"
        ]))
        
        return deploy(
            web3, self.project_location, mnemonic, env=self.get_deployment_args(user_data)
        )
    
    def get_anvil_instances(self) -> Dict[str, LaunchAnvilInstanceArgs]:
        return {
            "main": self.get_anvil_instance(
                fork_url='https://arb.llamarpc.com', 
                fork_block_num=267164264
            )
        }

Challenge().run()