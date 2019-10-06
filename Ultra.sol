pragma solidity ^0.5.9;

import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC721/ERC721Full.sol';
import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import 'github.com/OpenZeppelin/openzeppelin-solidity/contracts/lifecycle/Pausable.sol';
import "github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract OwnableDelegateProxy { }

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

contract TradeableERC721Token is ERC721Full, Ownable, Pausable {

    struct SUB {
        uint id;
        uint startBlock;
        uint expBlock;
    }
    
    //Total supply of minted styles
    uint256 _totalSupply = 0;
    //token minimum for subscription updates
    uint256 tokenReSubMin = 10000;
    //blocks per sent token for subscription
    uint256 blocksPerToken = 156;
    //initial blocks for subscription mint
    uint256 baseSubscriptionBlocks = 384000;

    //STYLE objects with ID that can be minted
    mapping (uint256 => SUB) _subs;
    
    //Event for STYLE updates
    event NewSubAdded(uint id, uint startBlock, uint expBlock);
    event SubUpdated(uint id, uint blocks, uint expBlock);
    event SubUpdateFailed(uint id);

    address public proxyRegistryAddress;
    address public blvdAddress = address(0x0);
    address public gatewayAddress = address(0x0);
    
    string activeSubscriptionUri = "";
    string expiedSubscriptionUri = "";
    
    constructor(string memory _name, string memory _symbol) ERC721Full(_name, _symbol) public {
        
    }
 
  /**
    * @dev Mints bulk amount to address (owner)
    * @param _to address of the future owner of the token
    */
  function bulkMintTo(uint256 mintAmount, address _to) public onlyOwner {
    for (uint256 i = 0; i < mintAmount; i++) {
        mintTo(_to);
     }
  }

   /**
    * @dev Mints bulk subscription tokens to given addresses
    */
  function bulkMintArray(address[] memory receivers) public onlyOwner {
     for (uint256 i = 0; i < receivers.length; i++) {
        mintTo(receivers[i]);
     }
  }
  
        /**
    * @dev Mints a token to an address with a tokenURI.
    * @param _to address of the future owner of the token
    */
  function mintTo(address _to) public onlyOwner {
    uint256 _newTokenId = _getNextTokenId();
    uint256 curBlock = block.number;
    uint256 expBlock = SafeMath.add(curBlock, baseSubscriptionBlocks);
    SUB memory _sub = SUB(_newTokenId, curBlock, expBlock);
    _subs[_newTokenId] = _sub;
    _mint(_to, _newTokenId);
    _incrementTokenId();
  }

  function _incrementTokenId() private  {
    _totalSupply++;
  }
  
  function renewSubscription(uint _tokenId, uint256 tokenAmount ) public{
      require(tokenReSubMin < tokenAmount, "You must provide more tokens to update subsccription");
       SUB storage _sub = subscriptionObjectForTokenId(_tokenId);
       
       bool result = ERC20(blvdAddress).transferFrom(msg.sender, owner(), tokenAmount);
        if (result) {
            uint256 blocksToAdd = getBlocksForTokensPaid(tokenAmount);
            //Add to existing if block number is higher than curent
             if (_sub.expBlock > block.number){
                 _subs[_tokenId].expBlock = SafeMath.add(_subs[_tokenId].expBlock, blocksToAdd);
             }else{
                 //Start subscription from current block if already expired
                 _subs[_tokenId].expBlock = SafeMath.add(block.number, blocksToAdd);
             }
            emit SubUpdated(_tokenId, blocksToAdd, _sub.expBlock);
        } else {
            //Maybe not needed?
            emit SubUpdateFailed(_tokenId);
        }
  }
  
  function getBlocksForTokensPaid(uint256 tokenAmount) public returns (uint256) {
      return SafeMath.div(tokenAmount, blocksPerToken);
  }
  
  /**
    * @dev calculates the next token ID based on value of _currentTokenId 
    * @return uint256 for the next token ID
    */
  function _getNextTokenId() private view returns (uint256) {
    return _totalSupply.add(1);
  }

    //Returns the metadata uri for the token
    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        SUB storage _sub = subscriptionObjectForTokenId(_tokenId);
        if (_sub.expBlock < block.number){
            //subscription is valid
            return activeSubscriptionUri;
        }else{
            //subscription is expired
            return expiedSubscriptionUri;
        }
        // return _styles[_tokenIdToStyle[_tokenId]].metaUrl;
    } 

    //Returns SUB object based on the tokenId
    function subscriptionObjectForTokenId(uint256 _tokenId) internal view returns (SUB storage) {
        return _subs[_tokenId];
    }

    //Returns SUB object based on the tokenId
    function subscriptionMetaObjectForTokenId(uint256 _tokenId) public view returns (uint id, uint startBlock, uint expBlock, string memory metaUrl) {
        SUB storage _sub = _subs[_tokenId];
        string memory uri = tokenURI(_tokenId);
        return (_sub.id, _sub.startBlock, _sub.expBlock, uri);
    }
    
    //Update base blocks per initial subscription
    function updateBaseSubscriptionBlocks(uint256 blocks) public onlyOwner {
        baseSubscriptionBlocks = blocks;
    }
    
    //Update base blocks per token paid to renew subscription
    function updateBlocksPerToken(uint256 blocks) public onlyOwner {
        blocksPerToken = blocks;
    }
    
    //Update min tokens to be paid to renew subscription
    function updateTokenResubMin(uint256 tokens) public onlyOwner {
        tokenReSubMin = tokens;
    }
    
    //Update proxy address, mainly used for OpenSea
    function updateProxyAddress(address _proxy) public onlyOwner {
        proxyRegistryAddress = _proxy;
    }
    
    //Update gateway address, for possible sidechain use
    function updateGatewayAddress(address _gateway) public onlyOwner {
        gatewayAddress = _gateway;
    }
    
    function depositToGateway(uint tokenId) public {
        require(gatewayAddress != address(0x0), "Gateway Address has not been set yet!");
        safeTransferFrom(msg.sender, gatewayAddress, tokenId);
    }
    
    function getBalanceThis() view public returns(uint){
        return address(this).balance;
    }

    function withdraw() public onlyOwner returns(bool) {
        msg.sender.transfer(address(this).balance);
        return true;
    }
    
    /**
   * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
   */
  function isApprovedForAll(address owner, address operator) public view returns (bool){
    // Whitelist OpenSea proxy contract for easy trading.
    ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
    if (address(proxyRegistry.proxies(owner)) == operator) {
        return true;
    }
    return super.isApprovedForAll(owner, operator);
  }
}

/**
 * @title BLVD Map Style
 * MapStyle - a contract for ownership of limited edition digital collectible map styles
 * Customize in-app experiences in BULVRD app offerings https://bulvrdapp.com/#app
 */
contract MapStyle is TradeableERC721Token {
  constructor() TradeableERC721Token("BLVD U L T R A", "BLVDU") public {  }
}