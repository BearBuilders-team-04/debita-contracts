pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";


contract NFT is ERC721 {

uint id;
address owner;
address availableContract;
constructor() ERC721("Nft Test", "NFT") {
owner = msg.sender;
}

modifier onlyOwner {
    if(msg.sender != owner) {
        revert();
    }
    _;
}

modifier onlyContract {
    if(msg.sender != availableContract) {
        revert();
    }
    _;
}

function mint() public onlyContract {
    _mint(msg.sender, id);
    id++;
}

function setContract(address newContract) public onlyOwner {
     availableContract = newContract;
}
}