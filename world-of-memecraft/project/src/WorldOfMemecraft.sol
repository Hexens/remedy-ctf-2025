// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/interfaces/IWorldOfMemecraft.sol";
import "src/libraries/BackupLogic.sol";

/**


             .-""-.
          _.->    <-._
       .-"   '-__-'   "-.
     ,"                  ",
   .'                      ',
  /    ___...------...___    \
 /_.-*"__...--------...__"*-._\
:_.-*"'  .*"*-.  .-*"*.  '"*-._;
;       /      ;:      \       :
;      ;    *  !!  *    :      :         We can't get to a higher level 
:      :     .'  '.     ;      ;         because that dude doesn't let us finish quests!
 \      '-.-'      '-.-'      /
  \                          /
   '.                      .'
     *,      '-__-'      ,*
     /.'-_            _-'.'\                                              _.-**-._
    /  "-_"*-.____.-*"_-"   \                                          _,(        )
   /      '"*-.___.-*'       \                                      .-"   '-^----'   "-.
  :    :        |        ;    ;                                  .-'                    '-.
  |.--.;       *|        :.--.|                               .'                          '.
  (   ()        |        ()   )                             .'    __.--**'""""""'**--.__    '.
   '--^_       *|        _^--'                             /_.-*"'__.--**'""""""'**--.__'"*-._\
      | "'*--.._I_..--*'" |                               /_..-*"'   .-*"*-.  .-*"*-.   '"*-.._\
      | __..._  | _..._   |                               :          /       ;:       \         ;
     .'"      `"'"     ''"'.                              :         :     *  !!  *     :        ;
     """""""""""""""""""""""                               \        '.     .'  '.     .'       /  
                                                            \         '-.-'      '-.-'        /             
    That guy can kill us so easily                       .-*''.                              .'-.            
    because he's a super-highlevel, right?            .-'      '.                          .'    '.           
    But if we were super-highlevel, too...?          :           '-.        _.._        .-'        '._ 
                                                    ;"*-._          '-._  --___ `   _.-'        _.*'  '*.
                                                    :      '.            `"*-.__.-*"`           (        :
                                                    ;      ;                 *|                 '-.     ;
                                                    '---*'                   |                    ""--'
                                                      :                      *|                      :
                                                      '.                      |                     .'
                                                        '.._                 *|        ____----.._-'
                                                            \  """----_____------'-----"""         /
                                                             \  __..-------.._        ___..---._  /
                                                             :'"              '-..--''          "';
                                                            '""""""""""""""""' '"""""""""""""""'
        .*""""""""""""""""""""""*.
       :                          ;
       :                          ;
       :  ......................  ;
       : :                      ; ;
       :_:                      ;_;
      /  :  __...--------...__  ;  \
    /   :"'  .*"*-.  .-*"*.  '";    \
    :    ;   /      ;:      \   :    ;
    !    !  ;    *  !!  *    :  !    !   Dude! Boars are only worth two experience points a piece. 
    ;   ;   :     .'  '.     ;   ;   :   Do you know how many we would have to kill to get up 30 levels?
    :  .'    '-.-'      '-.-'    '.  ;
    '-"\                          /"-'
        '.                      .'
          *,      '-__-'      ,*                                                               
          /.'-_            _-' .\                                                              _.-**-._
         /  "-_"*-.____.-*" _-"  \                                                          _,(        ),_
        /      '-_  /'\  _-'      \                                                      .-"   '-^----'     "-.
       :    :   __'" | "'__   ;    ;                                                  .-'                      '-.
       |.--.;  |\/|  |  |\/|  :.--.|                                                .'                            '.
       (   ()  |__|  |  |__|  ()   )                                               /_.-*"'__.--**'""""""'**--.__'"*-._\
        '--^_        |        _^--'                                               /_..-*"'   .-*"*-.  .-*"*-.   '"*-.._\
           | "'*--.._I_..--*'" |                                                 :          /       ;:       \          ;
           | __..._  | _..._   |                                                 :         :     *  !!  *     :         ;
          .'"      `"'"     ''"'.                                                 \        '.     .'  '.     .'        / 
                                                                                   \         '-.-'      '-.-'         / 
    Yes. 65,340,285, which should take us 7 weeks,                              .-*''.                              .'-.   
    5 days, 13 hours and 20 minutes,                                         .-'      '.                          .'    '.           
    giving ourselves 3 hours a night to sleep.                              :           '-.        _.._        .-'        '._ 
    What do you say, guys?                                                ;"*-._          '-._  --___ `   _.-'        _.*'  '*.
    You can jus...                                                       :      '.            `"*-.__.-*"`           (        :
    you can just hang outside in the sun all day tossing a ball around   ;      ;                 *|                 '-.     ;
    Or you can sit at your computer and do something that matters...      '---*'                   |                    ""--'
                                                                           :                      *|                      :
                                                                           '.                      |                     .'
                                                                             '.._                 *|        ____----.._-'
                                                                              \  """----_____------'-----"""         /
                                                                                \  __..-------.._        ___..---._  /
                                                                                 :'"              '-..--''          "';
                                                                                '""""""""""""""""' '"""""""""""""""'



 */
 
contract WorldOfMemecraft is IWorldOfMemecraft {
    using BackupLogic for World;
    using BackupLogic for Character;

    uint256 public constant BOAR_XP = 2;
    uint256 public constant XP_PER_LEVEL = 2_178_010;
    uint256 public constant MAX_LEVEL_XP = 65_340_285;

    World private world;
    bytes32[] public backups;

    constructor() {
        world.servername = "Draenor";
        _addMonster("Jenkins", 60, 10_000_000, 31337);
        _addMonster("Stonetusk Boar", 1, 1, BOAR_XP);
                        /**
            c~~p ,---------.
        ,---'oo  )           \
        ( O O                  )/
        `=^='                 /
            \    ,     .   /
            \\  |-----'|  /
            ||__|    |_|__|
                */
    }

    modifier isCharacterOwner(uint id) {
        require(world.characterOwner[id] == msg.sender, "ACCESS_DENIED");
        _;
    }

    modifier oneActionPerBlock {
        require(world.lastActionBlock[msg.sender] < block.number, "ONE_ACTION_PER_BLOCK");
        _;
        world.lastActionBlock[msg.sender] = block.number;
    }


    function getServername() external view returns (string memory) {
        return world.servername;
    }
    
    function getNumPlayers() external view returns (uint) {
        return world.numPlayers;
    }

    function getCharacter(uint id) external view returns (Character memory) {
        return world.characters[id];
    }

    function getMonster(uint id) external view returns (Monster memory) {
        return world.monsters[id];
    }

    function createCharacter() 
        external 
        oneActionPerBlock
        returns (uint id) 
    {
        id = world.characters.length;
        world.characters.push(Character(
            id,
            1,
            100,
            0
        ));
        world.characterOwner[id] = msg.sender;
        world.numPlayers++;
    }

    function createBackup() 
        external 
        oneActionPerBlock
    {
        backups.push(world.merkleizeWorld());
    }

    function restoreCharacter(Character calldata character, bytes32[] calldata proof) 
        external 
        isCharacterOwner(character.id)
        oneActionPerBlock
    {
        require(character.proofCharacter(backups[backups.length - 1], proof), "INVALID_CHARACTER_PROOF");
        Character storage _character = world.characters[character.id];
        _character.level = character.level;
        _character.health = character.health;
        _character.xp = character.xp;
    }

    function fightMonster(uint characterId, uint monsterId) 
        external
        isCharacterOwner(characterId)
        oneActionPerBlock
    {
        Monster storage monster = world.monsters[monsterId];
        require(monster.alive, "Stop! Stop! He's already dead!");

        Character storage character = world.characters[characterId];
        require(character.health > 0, "GAME_OVER");

        uint random = uint256(keccak256(abi.encodePacked(characterId, monsterId, gasleft(), msg.sender, blockhash(block.number - 1)))) % 2;
        if (character.level > monster.level || (character.level == monster.level && random == 1)) {
            // you won
            character.xp += monster.xpDrop;
            monster.alive = false;
            if (character.xp >= XP_PER_LEVEL && character.level < 60) {
                character.level++;
                character.xp = 0;
            }
        } else { 
            // you lost
            character.health = 0;
            monster.kills++;
        }
    }

    function spawnBoar() 
        external 
        oneActionPerBlock
    {
        _addMonster("Stonetusk Boar", 1, 1, BOAR_XP);
    }
  
    function _addMonster(string memory name, uint256 level, uint256 health, uint256 xpDrop) internal {
        uint256 id = world.monsters.length;
        world.monsters.push(Monster({
            id: id,
            name: name,
            level: level,
            health: health,
            kills: 0,
            xpDrop: xpDrop,
            alive: true
        }));
    }
}
