pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract Dai is ERC20 {

constructor() ERC20("USDC TOKEN", "USDC") {

}

function mintF() public {

_mint(msg.sender, 100000000000000000000000000000);
} 
}