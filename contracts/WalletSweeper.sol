pragma solidity >=0.5.1 <0.6.0;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./Forwarder.sol";

import "hardhat/console.sol";

/**
 *
 * WalletSweeper
 * ============
 *
 * Determenistic forwarder factory with multisig wallet. Forwarders flush tokens to the parent contract.
 *
 */
contract WalletSweeper {
  using SafeERC20 for IERC20;

  // Events
  event Deposited(address from, uint value, bytes data);
  event SafeModeActivated(address msgSender);
  event SafeModeInActivated(address msgSender);
  event ForwarderCreated(address forwarderAddress);
  event TokensTransfer(address tokenContractAddress, uint value);
  event Transacted(
    address msgSender, // Address of the sender of the message initiating the transaction
    address otherSigner, // Address of the signer (second signature) used to initiate the transaction
    bytes32 operation, // Operation hash (see Data Formats)
    address toAddress, // The address the transaction was sent to
    uint value, // Amount of Wei sent to the address
    bytes data // Data sent when invoking the transaction
  );

  // Public fields
  address[] public signers; // The addresses that can co-sign transactions on the wallet
  address[] public operators; // The addresses that can flush tokens in the wallet
  bool public safeMode = false; // When active, wallet may only send to signer addresses

  // Internal fields
  uint256 constant SEQUENCE_ID_WINDOW_SIZE = 10;
  uint256[10] recentSequenceIds;

  /**
   * Set up a simple multi-sig wallet by specifying the signers allowed to be used on this wallet.
   * 2 signers will be required to send a transaction from this wallet.
   * Note: The sender is NOT automatically added to the list of signers.
   * Signers CANNOT be changed once they are set
   *
   * @param allowedSigners An array of signers on the wallet
   * @param allowedSigners An array of operators who can flush tokens
   */
  constructor(address[] memory allowedSigners, address[] memory allowedOperators) public {
    if (allowedSigners.length != 2) {
      // Invalid number of signers
      revert("WalletSweeper: number of signers must be 2.");
    }
    if (allowedOperators.length == 0) {
      // Invalid number of signers
      revert("WalletSweeper: number of signers must be >0.");
    }
    signers = allowedSigners;
    operators = allowedOperators;
  }

  /**
   * Determine if an address is a signer on this wallet
   * @param signer address to check
   * returns boolean indicating whether address is signer or not
   */
  function isSigner(address signer) public view returns (bool) {
    // Iterate through all signers on the wallet
    for (uint i = 0; i < signers.length; i++) {
      if (signers[i] == signer) {
        return true;
      }
    }
    return false;
  }

  /**
   * Determine if an address is an operator on this wallet
   * @param operator address to check
   * returns boolean indicating whether address is operator or not
   */
  function isOperator(address operator) public view returns (bool) {
    // Iterate through all operators on the wallet
    for (uint i = 0; i < operators.length; i++) {
      if (operators[i] == operator) {
        return true;
      }
    }
    return false;
  }

  /**
   * Modifier that will execute internal code block only if the sender is an authorized signer on this wallet
   */
  modifier onlySigner {
    if (!isSigner(msg.sender)) {
      revert("WalletSweeper: not a signer");
    }
    _;
  }

  /**
   * Modifier that will execute internal code block only if the sender is an authorized operator on this wallet
   */
  modifier onlyOperator {
    if (!isOperator(msg.sender)) {
      revert("WalletSweeper: not an operator");
    }
    _;
  }

  /**
   * Gets called when a transaction is received without calling a method
   */
  function() external payable {
    if (msg.value > 0) {
      // Fire deposited event if we are receiving funds
      emit Deposited(msg.sender, msg.value, msg.data);
    }
  }

  function createForwarder(uint256 userID) external onlyOperator {
    // get wallet init_code
    bytes memory bytecode = type(Forwarder).creationCode;
    address newAddr;
    assembly { // solium-disable-line security/no-inline-assembly
      let codeSize := mload(bytecode) // get size of init_bytecode
      newAddr := create2(
        0, // 0 wei
        add(bytecode, 32), // the bytecode itself starts at the second slot. The first slot contains array length
        codeSize, // size of init_code
        userID // salt from function arguments
      )
      if iszero(extcodesize(newAddr)) {
        revert(0, 0)
      }
    }
    emit ForwarderCreated(newAddr);
  }

  /**
   * Execute a multi-signature transaction from this wallet using 2 signers: one from msg.sender and the other from ecrecover.
   * Sequence IDs are numbers starting from 1. They are used to prevent replay attacks and may not be repeated.
   *
   * @param toAddress the destination address to send an outgoing transaction
   * @param value the amount in Wei to be sent
   * @param data the data to send to the toAddress when invoking the transaction
   * @param expireTime the number of seconds since 1970 for which this transaction is valid
   * @param sequenceId the unique sequence id obtainable from getNextSequenceId
   * @param signature see Data Formats
   */
  function sendMultiSig(
    address payable toAddress,
    uint value,
    bytes calldata data,
    uint expireTime,
    uint sequenceId,
    bytes calldata signature
  ) external onlySigner {
    // Verify the other signer
    bytes32 operationHash = keccak256(abi.encodePacked("ETHER", toAddress, value, data, expireTime, sequenceId));

    address otherSigner = verifyMultiSig(toAddress, operationHash, signature, expireTime, sequenceId);

    // Success, send the transaction
    toAddress.transfer(value);
    emit Transacted(msg.sender, otherSigner, operationHash, toAddress, value, data);
  }

  /**
   * Execute a multi-signature token transfer from this wallet using 2 signers: one from msg.sender and the other from ecrecover.
   * Sequence IDs are numbers starting from 1. They are used to prevent replay attacks and may not be repeated.
   *
   * @param toAddress the destination address to send an outgoing transaction
   * @param value the amount in tokens to be sent
   * @param tokenContractAddress the address of the erc20 token contract
   * @param expireTime the number of seconds since 1970 for which this transaction is valid
   * @param sequenceId the unique sequence id obtainable from getNextSequenceId
   * @param signature see Data Formats
   */
  function sendMultiSigToken(
    address toAddress,
    uint value,
    address tokenContractAddress,
    uint expireTime,
    uint sequenceId,
    bytes calldata signature
  ) external onlySigner {
    bytes32 operationHash = keccak256(abi.encodePacked("ERC20", toAddress, value, tokenContractAddress, expireTime, sequenceId));
    verifyMultiSig(toAddress, operationHash, signature, expireTime, sequenceId);
    IERC20 instance = IERC20(tokenContractAddress);
    require(instance.balanceOf(address(this)) > 0, "non-zero balance");
    require(instance.transfer(toAddress, value), "successful transfer");
    emit TokensTransfer(tokenContractAddress, value);
  }

  /**
   * Execute a token flush from one of the forwarder addresses. This transfer needs only a single signature and can be done by any signer
   *
   * @param forwarderAddress the address of the forwarder address to flush the tokens from
   * @param tokenContractAddress the address of the erc20 token contract
   */
  function flushForwarderTokens(
    address payable forwarderAddress,
    address tokenContractAddress
  ) external onlyOperator {
    Forwarder forwarder = Forwarder(forwarderAddress);
    forwarder.flushTokens(tokenContractAddress);
  }

  function destroyForwarder(address payable forwarderAddress) external onlyOperator {
    // get wallet init_code
    Forwarder instance = Forwarder(forwarderAddress);
    instance.destroy();
  }

  /**
   * Do common multisig verification for both eth sends and erc20token transfers
   *
   * @param toAddress the destination address to send an outgoing transaction
   * @param operationHash see Data Formats
   * @param signature see Data Formats
   * @param expireTime the number of seconds since 1970 for which this transaction is valid
   * @param sequenceId the unique sequence id obtainable from getNextSequenceId
   * returns address that has created the signature
   */
  function verifyMultiSig(
    address toAddress,
    bytes32 operationHash,
    bytes memory signature,
    uint expireTime,
    uint sequenceId
  ) private returns (address) {

    address otherSigner = recoverAddressFromSignature(operationHash, signature);
    if (safeMode && !isSigner(toAddress)) {
      revert("safemode error");
    }
    // https://ethereum.stackexchange.com/questions/72668/avoid-using-now
    require(isSigner(otherSigner) && expireTime > now, "valid multisig"); // solium-disable-line security/no-block-members
    require(otherSigner != msg.sender, "other signer is different");
    tryInsertSequenceId(sequenceId);
    return otherSigner;
  }

  /**
   * Irrevocably puts contract into safe mode. When in this mode, transactions may only be sent to signing addresses.
   */
  function activateSafeMode() external onlySigner {
    safeMode = true;
    emit SafeModeActivated(msg.sender);
  }

  /**
   * Gets signer's address using ecrecover
   * @param operationHash see Data Formats
   * @param signature see Data Formats
   * returns address recovered from the signature
   */
  function recoverAddressFromSignature(
    bytes32 operationHash,
    bytes memory signature
  ) private pure returns (address) {
    if (signature.length != 65) {
      revert("invalid signature");
    }
    // We need to unpack the signature, which is given as an array of 65 bytes (like eth.sign)
    bytes32 r;
    bytes32 s;
    uint8 v;
    assembly { // solium-disable-line security/no-inline-assembly
      r := mload(add(signature, 32))
      s := mload(add(signature, 64))
      v := and(mload(add(signature, 65)), 255)
    }
    if (v < 27) {
      v += 27; // Ethereum versions are 27 or 28 as opposed to 0 or 1 which is submitted by some signing libs
    }
    return ecrecover(operationHash, v, r, s);
  }

  /**
   * Verify that the sequence id has not been used before and inserts it. Throws if the sequence ID was not accepted.
   * We collect a window of up to 10 recent sequence ids, and allow any sequence id that is not in the window and
   * greater than the minimum element in the window.
   * @param sequenceId to insert into array of stored ids
   */
  function tryInsertSequenceId(uint256 sequenceId) private onlySigner {
    // Keep a pointer to the lowest value element in the window
    uint lowestValueIndex = 0;
    for (uint i = 0; i < SEQUENCE_ID_WINDOW_SIZE; i++) {
      if (recentSequenceIds[i] == sequenceId) {
        // This sequence ID has been used before. Disallow!
        revert("WalletSweeper: seqID obsolete");
      }
      if (recentSequenceIds[i] < recentSequenceIds[lowestValueIndex]) {
        lowestValueIndex = i;
      }
    }
    if (sequenceId < recentSequenceIds[lowestValueIndex]) {
      // The sequence ID being used is lower than the lowest value in the window
      // so we cannot accept it as it may have been used before
      revert("WalletSweeper: seqId too low");
    }
    if (sequenceId > (recentSequenceIds[lowestValueIndex] + 10000)) {
      // Block sequence IDs which are much higher than the lowest value
      // This prevents people blocking the contract by using very large sequence IDs quickly
      revert("WalletSweeper: seqId too high");
    }
    recentSequenceIds[lowestValueIndex] = sequenceId;
  }

  /**
   * Gets the next available sequence ID for signing when using executeAndConfirm
   * returns the sequenceId one higher than the highest currently stored
   */
  function getNextSequenceId() external view returns (uint256) {
    uint256 highestSequenceId = 0;
    for (uint i = 0; i < SEQUENCE_ID_WINDOW_SIZE; i++) {
      if (recentSequenceIds[i] > highestSequenceId) {
        highestSequenceId = recentSequenceIds[i];
      }
    }
    return highestSequenceId + 1;
  }
}