pragma solidity ^0.4.18;

import "./StandardToken.sol";
import "./Ownable.sol";


/**
 *  MarconiCoin token contract. Implements
 */
contract MarconiCoin is StandardToken, Ownable {
  string public constant name = "MarconiCoin";
  string public constant symbol = "MRC";
  uint public constant decimals = 6;


  // Constructor
  function MarconiCoin() {
      totalSupply = 31622400;
      balances[msg.sender] = totalSupply; // Send all tokens to owner
  }

  /**
   *  Burn away the specified amount of MarconiCoin tokens
   */
  function burn(uint _value) onlyOwner returns (bool) {
    balances[msg.sender] = balances[msg.sender].sub(_value);
    totalSupply = totalSupply.sub(_value);
    Transfer(msg.sender, 0x0, _value);
    return true;
  }

}
