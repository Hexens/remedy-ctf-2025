import os
import random

from eth_abi import abi
import requests
from ctf_launchers.launcher import Action, Launcher, ORCHESTRATOR_HOST, CHALLENGE
from ctf_launchers.team_provider import TeamProvider, get_team_provider_v2
from ctf_server.types import UserData, get_privileged_web3
from web3 import Web3

CHALLENGE = os.getenv("CHALLENGE", "challenge")
FLAG = os.getenv("FLAG", "PCTF{flag}")
CHALLENGE_TXT = f'\033[96m{CHALLENGE}\033[92m'

def pprint(text):
    print(f'[{CHALLENGE_TXT}] {text}')

class PwnChallengeLauncher(Launcher):
    def __init__(
        self,
        project_location: str = "challenge/project",
        provider: TeamProvider = get_team_provider_v2(),
    ):
        super().__init__(
            project_location,
            provider,
            [
                Action(name="Get the flag", handler=self.get_flag),
            ],
        )

    def get_flag(self) -> int:
        instance_body = requests.get(f"{ORCHESTRATOR_HOST}/instances/{self.get_instance_id()}").json()
        if not instance_body['ok']:
            print(instance_body['message'])
            return 1

        user_data = instance_body['data']

        if not self.is_solved(
            user_data, user_data['metadata']["challenge_address"]
        ):
            pprint(random.choice([
                "Seems like you didn't solve it, back to debugging!",
                "That does not seem right. Are you sure you solved it?",
                "I'm checking but I don't think you solved it. Rest assured, it's you, not me."
            ]))
            return 1

        pprint(random.choice([
            f"Congratulations! Here is your flag: {FLAG}",
            f"Nicely done! Now don't lose it: {FLAG}",
            f"Oh how the turn tables, you win: {FLAG}"
        ]))
        return 0

    def is_solved(self, user_data: UserData, addr: str) -> bool:
        web3 = get_privileged_web3(user_data, "main")

        (result,) = abi.decode(
            ["bool"],
            web3.eth.call(
                {
                    "to": addr,
                    "data": web3.keccak(text="isSolved()")[:4],
                }
            ),
        )
        return result
