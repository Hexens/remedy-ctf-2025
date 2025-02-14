from typing import Dict
from web3 import Web3
from base64 import b64decode
import requests
import secrets

from eth_abi import abi
from ctf_launchers.launcher import Action, pprint
from ctf_launchers.pwn_launcher import PwnChallengeLauncher
from ctf_launchers.utils import deploy
from ctf_server.types import LaunchAnvilInstanceArgs, UserData, get_privileged_web3, get_system_account
from foundry.anvil import check_error
from foundry.anvil import anvil_autoImpersonateAccount, anvil_setCode

class Challenge(PwnChallengeLauncher):
    def after_init(self):
        self._actions.append(Action(
            name="Upgrade the CTF contract", handler=self.upgrade_contract
        ))

    def get_anvil_instances(self) -> Dict[str, LaunchAnvilInstanceArgs]:
        return {
            "main": self.get_anvil_instance(fork_url=None, balance=1)
        }
    
    def upgrade_contract(self):
        user_data = self.get_user_data()
        pprint('Please input the new full source code in Base64.')
        pprint('Terminal has a 1024 character limit on copy paste, so you can paste it in batches and finish with an empty one.')
        total_txt = ''
        next_txt = '1337'
        while next_txt != '':
            next_txt = input('Input:\n')
            total_txt += next_txt
        try:
            upgrade_contract = b64decode(total_txt).decode()
        except Exception as e:
            return
        with open('challenge/project/src/CTF.sol', 'r') as f:
            original_contract = f.read()
        try:
            res = requests.post('http://restricted-proxy-backend:3000/api/compare', json={
                'originalContract': original_contract,
                'upgradeContract': upgrade_contract
            }).json()
        except Exception as e:
            return
        
        if 'error' in res or not res['areEqual']:
            pprint('Nope, sorry, that contract violates the upgrade rules.')
            return
        web3 = get_privileged_web3(user_data, "main")
        (ctf_addr,) = abi.decode(
            ["address"],
            web3.eth.call(
                {
                    "to": user_data['metadata']["challenge_address"],
                    "data": web3.keccak(text="ctf()")[:4],
                }
            ),
        )
        anvil_setCode(web3, ctf_addr, res['bytecode'])

        pprint('All okay! The CTF contract has been upgraded.')

Challenge().run()