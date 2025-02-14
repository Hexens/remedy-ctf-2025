from typing import Dict
from web3 import Web3

from ctf_launchers.pwn_launcher import PwnChallengeLauncher
from ctf_launchers.utils import deploy
from ctf_server.types import LaunchAnvilInstanceArgs, UserData, get_privileged_web3, get_system_account
from foundry.anvil import check_error

class Challenge(PwnChallengeLauncher):
    def get_anvil_instances(self) -> Dict[str, LaunchAnvilInstanceArgs]:
        return {
            "main": self.get_anvil_instance(fork_url=None, balance=10)
        }

Challenge().run()