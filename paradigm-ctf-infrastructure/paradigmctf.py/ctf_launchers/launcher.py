import abc
import os
import traceback
import random
from dataclasses import dataclass
from typing import Callable, Dict, List

import requests
from ctf_launchers.team_provider import TeamProvider
from ctf_launchers.utils import deploy, http_url_to_ws
from ctf_server.types import (
    CreateInstanceRequest,
    DaemonInstanceArgs,
    LaunchAnvilInstanceArgs,
    UserData,
    get_player_account,
    get_privileged_web3,
)
from eth_account.hdaccount import generate_mnemonic

CHALLENGE = os.getenv("CHALLENGE", "challenge")
ORCHESTRATOR_HOST = os.getenv("ORCHESTRATOR_HOST", "http://orchestrator:7283")
PUBLIC_HOST = os.getenv("PUBLIC_HOST", f"http://{requests.get('https://ifconfig.me/').text}:8545")

ETH_RPC_URL = os.getenv("ETH_RPC_URL", "https://eth.llamarpc.com")
TIMEOUT = int(os.getenv("TIMEOUT", "900"))

RCTF_TXT = '''\033[91m
██████╗ ███████╗███╗   ███╗███████╗██████╗ ██╗   ██╗     ██████╗████████╗███████╗
██╔══██╗██╔════╝████╗ ████║██╔════╝██╔══██╗╚██╗ ██╔╝    ██╔════╝╚══██╔══╝██╔════╝
██████╔╝█████╗  ██╔████╔██║█████╗  ██║  ██║ ╚████╔╝     ██║        ██║   █████╗  
██╔══██╗██╔══╝  ██║╚██╔╝██║██╔══╝  ██║  ██║  ╚██╔╝      ██║        ██║   ██╔══╝  
██║  ██║███████╗██║ ╚═╝ ██║███████╗██████╔╝   ██║       ╚██████╗   ██║   ██║     
╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚══════╝╚═════╝    ╚═╝        ╚═════╝   ╚═╝   ╚═╝     
\033[92m'''
CHALLENGE_TXT = f'\033[96m{CHALLENGE}\033[92m'

def pprint(text):
    print(f'[{CHALLENGE_TXT}] {text}')

@dataclass
class Action:
    name: str
    handler: Callable[[], int]

class Launcher(abc.ABC):
    def __init__(
        self, project_location: str, provider: TeamProvider, actions: List[Action] = []
    ):
        self.project_location = project_location
        self.__team_provider = provider

        self._actions = [
            Action(name="Launch a new instance", handler=self.launch_instance),
            Action(name="Kill your instance", handler=self.kill_instance),
        ] + actions

        self.after_init()

    def after_init(self):
        pass

    def run(self):
        print(RCTF_TXT)
        pprint(random.choice([
            "Welcome anon!",
            "A random degen has appeared!",
            "You dare challenge me?"
        ]))

        self.mnemonic = generate_mnemonic(12, lang="english")

        for i, action in enumerate(self._actions):
            pprint(f"{i+1} - {action.name}")

        action = int(input(f"[{CHALLENGE_TXT}] Action? ")) - 1
        self.team = self.__team_provider.get_team(True if action == 0 else False)
        if not self.team:
            exit(1)

        try:
            handler = self._actions[action]
        except:
            pprint("That was not a valid action.")
            exit(1)

        try:
            exit(handler.handler())
        except Exception as e:
            traceback.print_exc()
            pprint(f"An error occurred: {e}")
            exit(1)

    def get_anvil_instances(self) -> Dict[str, LaunchAnvilInstanceArgs]:
        return {
            "main": self.get_anvil_instance(),
        }

    def get_daemon_instances(self) -> Dict[str, DaemonInstanceArgs]:
        return {}

    def get_anvil_instance(self, **kwargs) -> LaunchAnvilInstanceArgs:
        if not "balance" in kwargs:
            kwargs["balance"] = 1000
        if not "accounts" in kwargs:
            kwargs["accounts"] = 2
        if not "fork_url" in kwargs:
            kwargs["fork_url"] = ETH_RPC_URL
        if not "mnemonic" in kwargs:
            kwargs["mnemonic"] = self.mnemonic
        return LaunchAnvilInstanceArgs(
            **kwargs,
        )

    def get_instance_id(self) -> str:
        return f"chal-{CHALLENGE}-{self.team}".lower()
    
    def get_user_data(self):
        instance_body = requests.get(f"{ORCHESTRATOR_HOST}/instances/{self.get_instance_id()}").json()
        if not instance_body['ok']:
            print(instance_body['message'])
            exit(1)
        return instance_body['data']

    def update_metadata(self, new_metadata: Dict[str, str]):
        resp = requests.post(
            f"{ORCHESTRATOR_HOST}/instances/{self.get_instance_id()}/metadata",
            json=new_metadata,
        )
        body = resp.json()
        if not body["ok"]:
            pprint(body["message"])
            return 1

    def launch_instance(self) -> int:
        print()
        pprint("Creating private blockchain...")
        body = requests.post(
            f"{ORCHESTRATOR_HOST}/instances",
            json=CreateInstanceRequest(
                instance_id=self.get_instance_id(),
                timeout=TIMEOUT,
                anvil_instances=self.get_anvil_instances(),
                daemon_instances=self.get_daemon_instances(),
            ),
        ).json()
        if body["ok"] == False:
            raise Exception(body["message"])

        user_data = body["data"]

        pprint("Deploying challenge.. (please be patient, this can take a while)")
        self.challenge_addr = self.deploy(user_data, self.mnemonic)

        self.update_metadata(
            {"mnemonic": self.mnemonic, "challenge_address": self.challenge_addr}
        )

        PUBLIC_WEBSOCKET_HOST = http_url_to_ws(PUBLIC_HOST)

        print()
        pprint("Your private blockchain has been set up,")
        pprint(f"it will automatically terminate in {TIMEOUT/60} minutes!")
        print()
        pprint("RPC Endpoints:")
        for id in user_data["anvil_instances"]:
            pprint(f"    - {PUBLIC_HOST}/{user_data['external_id']}/{id}")
            pprint(f"    - {PUBLIC_WEBSOCKET_HOST}/{user_data['external_id']}/{id}/ws")
        print()
        pprint(f"The Player private key:         {get_player_account(self.mnemonic).key.hex()}")
        pprint(f"The Challenge contract address: {self.challenge_addr}")

        anvil_instance = user_data["anvil_instances"]["main"]
        self.post_launch_hook(
            f"{PUBLIC_HOST}/{user_data['external_id']}/{id}",
            f"http://{anvil_instance['ip']}:{anvil_instance['port']}"
        )

        return 0

    def kill_instance(self) -> int:
        resp = requests.delete(f"{ORCHESTRATOR_HOST}/instances/{self.get_instance_id()}")
        body = resp.json()

        pprint(body["message"])
        return 1

    def deploy(self, user_data: UserData, mnemonic: str) -> str:
        web3 = get_privileged_web3(user_data, "main")

        return deploy(
            web3, self.project_location, mnemonic, env=self.get_deployment_args(user_data)
        )

    def get_deployment_args(self, user_data: UserData) -> Dict[str, str]:
        return {}
    
    def post_launch_hook(self, normal_rpc_url, privileged_rpc_url):
        pass
