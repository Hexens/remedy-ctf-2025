// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import {VotingERC721} from "./VotingERC721.sol";
import {ERC721} from "./openzeppelin-contracts/token/ERC721/ERC721.sol";



/*        

.     .       .  .   . .   .   . .    +  .
  .     .  :     .    .. :. .___---------___.
       .  .   .    .  :.:. _".^ .^ ^.  '.. :"-_. .
    .  :       .  .  .:../:            . .^  :.:\.
        .   . :: +. :.:/: .   .    .        . . .:\
 .  :    .     . _ :::/:               .  ^ .  . .:\
  .. . .   . - : :.:./.                        .  .:\
  .      .     . :..|:                    .  .  ^. .:|
    .       . : : ..||        .                . . !:|
  .     . . . ::. ::\(                           . :)/
 .   .     : . : .:.|. ######              .#######::|
  :.. .  :-  : .:  ::|.#######           ..########:|
 .  .  .  ..  .  .. :\ ########          :######## :/
  .        .+ :: : -.:\ ########       . ########.:/
    .  .+   . . . . :.:\. #######       #######..:/
      :: . . . . ::.:..:.\           .   .   ..:/
   .   .   .  .. :  -::::.\.       | |     . .:/
      .  :  .  .  .-:.":.::.\             ..:/
 .      -.   . . . .: .:::.:.\.           .:/
.   .   .  :      : ....::_:..:\   ___.  :/
   .   .  .   .:. .. .  .: :.:.:\       :/
     +   .   .   : . ::. :.:. .:.|\  .:/|
     .         +   .  .  ...:: ..|  --.:|
.      . . .   .  .  . ... :..:.."(  ..)"
 .   .       .      :  .   .: ::/  .  .::\
 
        Voting NFTs Challenge
        Players must freeze the super voting power NFT held by the Challenge contract.


*/
contract Challenge {

    uint256 public constant SUPER_POWER = 10_000 ether;
    uint256 public constant SUPER_ID = 0;
    uint256 public constant NORMAL_POWER = 1 ether;
    uint256 public constant NORMAL_ID = 123;

    address public immutable PLAYER;
    address public immutable ADMIN;
    VotingERC721 public votingToken;

    constructor(address player) {
        PLAYER = player;
        ADMIN = msg.sender;
        votingToken = new VotingERC721();
        votingToken.mint(address(this), SUPER_ID, SUPER_POWER);
        votingToken.mint(player, NORMAL_ID, NORMAL_POWER);
        votingToken.delegate(player);
    }


/**   
                          .-""""-.
                         /        \
                        /_        _\
                       // \      / \\
                      |\__\    /__/|
                        \    ||    /
                         \        /
                          \  __  /  \  /          ________________________________
                           '.__.'    \/          /                                 \
                            |  |     /\         |    Think You Can Crack This?     |
                            |  |    O  O        |    I Doubt a Human Can Do It!    |
                            ----    //         O \_________________________________/
                           (    )  //        O
                          (\\     //       o
                         (  \\    )      o
                         (   \\   )   /\
               ___[\______/^^^^^^^\__/) o-)__
              |\__[=======______//________)__\
              \|_______________//____________|
                  |||      || //||     |||
                  |||      || ..||     |||
                   ||      \/  .\/      ||
                              . .
                             '.'.`
*/
    function isSolved() external returns (bool) {        
        
        if (votingToken.ownerOf(SUPER_ID) == ADMIN) return false;
        (bool success1,) =
            address(votingToken).call(abi.encodeWithSelector(VotingERC721.delegate.selector, address(this)));
        (bool success2,) = address(votingToken).call(
            abi.encodeWithSelector(ERC721.transferFrom.selector, address(this), ADMIN, SUPER_ID)
        );
        return (!success1 && !success2);
    }
}


