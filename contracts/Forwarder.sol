pragma solidity >=0.5.1 <0.6.0;

import "./IERC20.sol";
import "./SafeERC20.sol";


/**
 * Contract that will forward any incoming Ether to the creator of the contract
 */
contract Forwarder {
  using SafeERC20 for IERC20;

  // Address that is allowed to execute actions on this contract and 
  // to which any funds sent to this contract will be forwarded
  address payable public parentAddress;

  event ForwarderDeposited(address from, uint value, bytes data);
  event TokensFlushed(address forwarderAddress, uint value, address tokenContractAddress);

  /**
   * Create the contract, and sets the destination address to that of the creator
   */
  constructor() public {
    parentAddress = msg.sender;
    if (address(this).balance > 0) {
      parentAddress.transfer(address(this).balance);
    }
  }

  /**
   * Modifier that will execute internal code block only if the sender is the parent address
   */
  modifier onlyParent {
    require(msg.sender == parentAddress, "Forwarder: caller is not the main wallet");
    _;
  }

  /**
   * Default function; Gets called when Ether is deposited, and forwards it to the parent address
   */
  function() external payable {
    parentAddress.transfer(msg.value);
    emit ForwarderDeposited(msg.sender, msg.value, msg.data);
  }

  /**
   * Execute a token transfer of the full balance from the forwarder token to the parent address
   * @param tokenContractAddress the address of the erc20 token contract
   */
  function flushTokens(address tokenContractAddress) external onlyParent {
    IERC20 instance = IERC20(tokenContractAddress);
    uint forwarderBalance = instance.balanceOf(address(this));
    instance.safeTransfer(parentAddress, forwarderBalance);
    emit TokensFlushed(address(this), forwarderBalance, tokenContractAddress);
  }

  /**
  * @dev Execute a specified token transfer from the forwarder token to the parent address.
  * @param _from the address of the erc20 token contract.
  * @param _value the amount of token.
  */
  function flushToken(address _from, uint _value) external{
    IERC20(_from).transfer(parentAddress, _value);
  }

  /**
  * @dev It is possible that funds were sent to this address before the contract was deployed.
  *      We can flush those funds to the parent address.
  */
  function flush() external {
    parentAddress.transfer(address(this).balance);
  }

  function destroy() external {
    require(msg.sender == parentAddress, "Forwarder: not an owner");
    selfdestruct(msg.sender);
  }
}