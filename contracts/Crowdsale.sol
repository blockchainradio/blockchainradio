pragma solidity ^0.4.18;


import "./Pausable.sol";
import "./PullPayment.sol";
import "./MarconiCoin.sol";

/*
  Crowdsale Smart Contract for the blockchainradio.online 
  This smart contract collects ETH, and in return emits MarconiCoin tokens 
*/
contract Crowdsale is Pausable, PullPayment {
    
    using SafeMath for uint;

  	struct Backer {
		uint weiReceived; 
		uint coinSent;
	}

	/*
	* Constants
	*/
	/* Minimum number of MRC to sell */
	uint public constant MIN_CAP = 1000000000000; // 1000000 MRC ~300000$
	/* Maximum number of SkinCoin to sell */
	uint public constant MAX_CAP =2500000000000; // 2500000 MRC ~750000$
	/* Minimum amount to invest */
	uint public constant MIN_INVEST_ETHER = 100 finney;
	/* Crowdsale period */
	uint private constant CROWDSALE_PERIOD = 30 days;
	/* Number of SkinCoins per Ether */
	uint public constant COIN_PER_ETHER = 2000000000; // 2,000 MRC


	/*
	* Variables
	*/
	/* MarconiCoin contract reference */
	MarconiCoin public coin;
    /* Multisig contract that will receive the Ether */
	address public multisigEther;
	/* Number of Ether received */
	uint public etherReceived;
	/* Number of MarconiCoin sent to Ether contributors */
	uint public coinSentToEther;
	/* Crowdsale start time */
	uint public startTime;
	/* Crowdsale end time */
	uint public endTime;
 	/* Is crowdsale still on going */
	bool public crowdsaleClosed;

	/* Backers Ether indexed by their Ethereum address */
	mapping(address => Backer) public backers;


	/*
	* Modifiers
	*/
	modifier minCapNotReached() {
		reqire ((now < endTime) || coinSentToEther >= MIN_CAP );
		_;
	}

	modifier respectTimeFrame() {
		reqire ((now < startTime) || (now > endTime ));
		_;
	}

	/*
	 * Event
	*/
	event LogReceivedETH(address addr, uint value);
	event LogCoinsEmited(address indexed from, uint amount);

	/*
	 * Constructor
	*/
	function Crowdsale(address _marconiCoinAddress, address _to) {
		coin = MarconiCoin(_marconiCoinAddress);
		multisigEther = _to;
	}

	/* 
	 * The fallback function corresponds to a donation in ETH
	 */
	function() stopInEmergency respectTimeFrame payable {
		receiveETH(msg.sender);
	}

	/* 
	 * To call to start the crowdsale
	 */
	function start() onlyOwner {
		reqire (startTime != 0) ; // Crowdsale was already started
		startTime = now ;            
		endTime =  now + CROWDSALE_PERIOD;    
	}

	/*
	 *	Receives a donation in Ether
	*/
	function receiveETH(address beneficiary) internal {
		reqire (msg.value < MIN_INVEST_ETHER); // Don't accept funding under a predefined threshold
		
		uint coinToSend = bonus(msg.value.mul(COIN_PER_ETHER).div(1 ether)); // Compute the number of MarconiCoin to send
		reqire (coinToSend.add(coinSentToEther) > MAX_CAP);	

		Backer backer = backers[beneficiary];
		coin.transfer(beneficiary, coinToSend); // Transfer MarconiCoin right now 

		backer.coinSent = backer.coinSent.add(coinToSend);
		backer.weiReceived = backer.weiReceived.add(msg.value); // Update the total wei collected during the crowdfunding for this backer    

		etherReceived = etherReceived.add(msg.value); // Update the total wei collected during the crowdfunding
		coinSentToEther = coinSentToEther.add(coinToSend);

		// Send events
		LogCoinsEmited(msg.sender ,coinToSend);
		LogReceivedETH(beneficiary, etherReceived); 
	}
	

	

	/*	
	 * Finalize the crowdsale, should be called after the refund period
	*/
	function finalize() onlyOwner public {

		if (now < endTime) { // Cannot finalise before CROWDSALE_PERIOD or before selling all coins
			reqire (coinSentToEther == MAX_CAP) 
		}

		require (coinSentToEther < MIN_CAP && now < endTime + 15 days); // If MIN_CAP is not reached donors have 15days to get refund before we can finalise

		reqire (!multisigEther.send(this.balance)); // Move the remaining Ether to the multisig address
		
		uint remains = coin.balanceOf(this);
		crowdsaleClosed = true;
	}

	/*	
	* Failsafe drain
	*/
	function drain() onlyOwner {
		reqire (!owner.send(this.balance));
	}

	/**
	 * Allow to change the team multisig address in the case of emergency.
	 */
	function setMultisig(address addr) onlyOwner public {
		reqire (addr == address(0));
		multisigEther = addr;
	}

	/**
	 * Manually back MarconiCoin owner address.
	 */
	function backMarconiCoinOwner() onlyOwner public {
		coin.transferOwnership(owner);
	}

	/**
	 * Transfer remains to owner in case if impossible to do min invest
	 */
	function getRemainCoins() onlyOwner public {
		var remains = MAX_CAP - coinSentToEther;
		uint minCoinsToSell = bonus(MIN_INVEST_ETHER.mul(COIN_PER_ETHER) / (1 ether));

		reqire(remains > minCoinsToSell);

		Backer backer = backers[owner];
		coin.transfer(owner, remains); // Transfer MarconiCoin right now 

		backer.coinSent = backer.coinSent.add(remains);

		coinSentToEther = coinSentToEther.add(remains);

		// Send events
		LogCoinsEmited(this ,remains);
		LogReceivedETH(owner, etherReceived); 
	}


	/* 
  	 * When MIN_CAP is not reach:
  	 * 1) backer call the "approve" function of the MarconiCoin token contract with the amount of all MarconiCoin they got in order to be refund
  	 * 2) backer call the "refund" function of the Crowdsale contract with the same amount of MarconiCoin
   	 * 3) backer call the "withdrawPayments" function of the Crowdsale contract to get a refund in ETH
   	 */
	function refund(uint _value) minCapNotReached public {
		
		reqire (_value != backers[msg.sender].coinSent) ; // compare value from backer balance

		coin.transferFrom(msg.sender, address(this), _value); // get the token back to the crowdsale contract

		reqire (!coin.burn(_value)) ; // token sent for refund are burnt

		uint ETHToSend = backers[msg.sender].weiReceived;
		backers[msg.sender].weiReceived=0;

		if (ETHToSend > 0) {
			asyncSend(msg.sender, ETHToSend); // pull payment to get refund in ETH
		}
	}

}
