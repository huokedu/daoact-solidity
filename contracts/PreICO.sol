pragma solidity 0.4.13;

import "./SafeMath.sol";

/**
 * PreICO is designed to hold funds of pre ico. Account is controlled by four administratos. To trigger a payout
 * three out of four administrators will must agree on same amount of ethers to be transferred. During the signing
 * process if one administrator sends different targetted address or amount of ethers, process will abort and they
 * need to start again.
 * Administrator can be replaced but three out of four must agree upon replacement of fourth administrator. Three
 * admins will send address of fourth administrator along with address of new one administrator. If a single one
 * sends different address the updating process will abort and they need to start again. 
 */

contract PreICO{
  
  using SafeMath for uint256;
  
  // Maintain state funds transfer signing process
  struct Transaction{
    address[3] signer;
    uint confirmations;
    uint256 eth;
  }
  
  // count and record signers with ethers they agree to transfer
  Transaction private  pending;
    
  // the number of administrator that must confirm the same operation before it is run.
  uint256 constant public required = 3;

  mapping(address => bool) private administrators;
 
  // Funds has arrived into the contract (record how much).
  event Deposit(address _from, uint256 value);
  
  // Funds transfer to other contract
  event Transfer(address indexed fristSigner, address indexed secondSigner, address indexed thirdSigner, address to,uint256 eth,bool success);
  
  // Administrator successfully signs a fund transfer
  event TransferConfirmed(address signer,uint256 amount,uint256 remainingConfirmations);
  
  // Administrator successfully signs a key update transaction
  event UpdateConfirmed(address indexed signer,address indexed newAddress,uint256 remainingConfirmations);
  
  
  // Administrator violated consensus
  event Violated(string action, address sender); 
  
  // Administrator key updated (administrator replaced)
  event KeyReplaced(address oldKey,address newKey);
  
  
  function PreICO(address admin1,address admin2,address admin3,address admin4){
    administrators[admin1] = true;
    
    // all admins must have unique public keys
    if (isAdministrator(admin2)) revert();
    administrators[admin2] = true;
    
    if (isAdministrator(admin3)) revert();
    administrators[admin3] = true;
    
    if (isAdministrator(admin4)) revert();
    administrators[admin4] = true;

  }
  
  /**
   * @dev  To trigger payout three out of four administrators call this
   * function, funds will be transferred right after verification of
   * third signer call.
   * @param recipient The address of recipient
   * @param amount Amount of wei to be transferred
   */
  function transfer(address recipient, uint256 amount) external onlyAdmin {
    
    // input validations
    require( recipient != 0x00 );
    require( amount > 0 );
    require( this.balance >= amount);
    
    // Start of signing process, first signer will finalize inputs for remaining two
    if(pending.confirmations == 0){
        
        pending.signer[pending.confirmations] = msg.sender;
        pending.eth = amount;
        pending.confirmations = pending.confirmations.add(1);
        uint256 remaining = required.sub(pending.confirmations);
        TransferConfirmed(msg.sender,amount,remaining);
        return;
    
    }
    
    // Compare amount of wei with previous confirmtaion
    if( pending.eth != amount){
        transferViolated();
        return;
    }
    
    // make sure signer is not trying to spam
    if(msg.sender == pending.signer[0]){
        transferViolated();
        return;
    }
    
    pending.signer[pending.confirmations] = msg.sender;
    pending.confirmations = pending.confirmations.add(1);
    remaining = required.sub(pending.confirmations);
    
    // make sure signer is not trying to spam
    if( remaining == 0){
        if(msg.sender == pending.signer[1]){
            transferViolated();
            return;
        }
    }
    
    TransferConfirmed(msg.sender,amount,remaining);
    
    // If three confirmation are done, trigger payout
    if (pending.confirmations == 3){
        if(recipient.send(amount)){
            Transfer(pending.signer[0],pending.signer[1], pending.signer[2], recipient,amount,true);
        }else{
            Transfer(pending.signer[0],pending.signer[1], pending.signer[2], recipient,amount,false);
        }
        delete pending;
    }
    
  }
  
  function transferViolated() private {
    Violated("Funds Transfer",msg.sender);
    delete pending;
  }
  
  /**
   * @dev Reset values of pending (Transaction object)
   */
  function abortTransaction() external onlyAdmin{
       delete pending;
  }
  
  
  /** 
   * @dev Fallback function, receives value and emits a deposit event. 
   */
  function() payable {
    // just being sent some cash?
    if (msg.value > 0)
      Deposit(msg.sender, msg.value);
  }
  
  /**
   * @dev Checks if given address is an administrator.
   * @param _addr address The address which you want to check.
   * @return True if the address is an administrator and fase otherwise.
   */
  function isAdministrator(address _addr) public constant returns (bool) {
    return administrators[_addr];
  }

  
  // Maintian state of administrator key update process
  struct KeyUpdate{
    address[3] signer;
    uint confirmations;
    address oldAddress;
    address newAddress;
  }
  
  KeyUpdate private updating;
  
  /**
   * @dev Three admnistrator can replace key of fourth administrator. 
   * @param _oldAddress Address of adminisrator needs to be replaced
   * @param _newAddress Address of new administrator
   */
  function updateAdministratorKey(address _oldAddress, address _newAddress) external onlyAdmin {
    
    // input verifications
    require(isAdministrator(_oldAddress));
    require( _newAddress != 0x00 );
    require(!isAdministrator(_newAddress));
    require( msg.sender != _oldAddress );
    
    // count confirmation 
    uint256 remaining;
    
    // start of updating process, first signer will finalize address to be replaced
    // and new address to be registered, remaining two must confirm
    if( updating.confirmations == 0){
        
        updating.signer[updating.confirmations] = msg.sender;
        updating.oldAddress = _oldAddress;
        updating.newAddress = _newAddress;
        updating.confirmations = updating.confirmations.add(1);
        remaining = required.sub(updating.confirmations);
        UpdateConfirmed(msg.sender,_newAddress,remaining);
        return;
        
    }
    
    // violated consensus
    if(updating.oldAddress != _oldAddress){
        Violated("Administrator key Update",msg.sender);
        delete updating;
        return;
    }
    
    if(updating.newAddress != _newAddress){
        Violated("Administrator key Update",msg.sender);
        delete updating;
        return;
    }
    
    // make sure admin is not trying to spam
    if(msg.sender == updating.signer[0]){
        Violated("Funds Transfer",msg.sender);
        delete updating;
        return;
    }
    
    if( remaining == 1){
        if(msg.sender != updating.signer[1]){
            Violated("Funds Transfer",msg.sender);
            delete updating;
            return;
        }
    }
    
    updating.signer[updating.confirmations] = msg.sender;
    updating.confirmations = updating.confirmations.add(1);
    UpdateConfirmed(msg.sender,_newAddress,remaining);
    
    // if three confirmation are done, register new admin and remove old one
    if( updating.confirmations == 3 ){
        KeyReplaced(_oldAddress, _newAddress);
        delete updating;
        delete administrators[_oldAddress];
        administrators[_newAddress] = true;
        return;
    }
  }

  /**
   * @dev Reset values of updating (KeyUpdate object)
   */
  function abortUpdate() external onlyAdmin{
      delete updating;
  }
  
  /**
   * @dev modifier allow only if function is called by administrator
   */
  modifier onlyAdmin(){
      if( !administrators[msg.sender] ){
          revert();
      }
      _;
  }
}