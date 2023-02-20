// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

contract Wallet {

    event Approval(address indexed owner, uint indexed txId);
    event Deposit(address indexed sender, uint amount);
    event Execution(uint indexed txId);
    event Flag(address indexed owner, uint indexed txId);
    event OwnerAddition(address indexed owner);
    event OwnerAdditionRequest(address indexed owner, uint indexed txId);
    event OwnerRemoval(address indexed owner);
    event OwnerRemovalRequest(address indexed owner, uint indexed txId);
    event RequirementChange(uint8 requiredApprovals);
    event RequirementChangeRequest(uint8 requiredApprovals, uint indexed txId);
    event Revocation(address indexed owner, uint indexed txId);
    event TransactionRequest(uint indexed txId);

    uint8 public constant MAX_OWNERS = 20;

    uint8 public requiredApprovals;
    mapping(uint => mapping(address => bool)) public approved; // txId -> owners -> is approved
    
    mapping(address => bool) public isOwner; // address -> is owner 
    address[] public owners;
    
    Transaction[] public transactions; 
    
    struct Transaction {
        address to; 
        uint value;
        bytes data;
        bool executed;
        bool flagged;
    }

    modifier maxOwners(uint _numOwners) {
        require(_numOwners <= MAX_OWNERS, "cannot exceed 20 owners");
        _; // because 0 < requiredApprovals < numOwners, numOwners >= 2
    }
    
    modifier notExecuted(uint _txId) {
        require(!transactions[_txId].executed, "tx already executed");
        _;
    }

    modifier alreadyOwner(address _owner) {
        require(isOwner[_owner], "not owner");
        _;
    }
    
    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier onlyWallet() {
        require(msg.sender == address(this), "must be called internaly");
        _;
    }

    modifier txExists(uint _txId) {
        require(_txId < transactions.length, "tx does not exist");
        _;
    }

    modifier validOwner(address _owner) {
        require(_owner != address(0), "invalid owner");
        require(!isOwner[_owner], "duplicate owner");
        _;
    }

    modifier validRequiredApprovals(uint _numOwners, uint8 _requiredApprovals) {
        require(
            _requiredApprovals > 0 
            && _requiredApprovals < _numOwners, 
            "required approvals out of range"
        ); 
        _;
    }

    constructor(address[] memory _owners, uint8 _requiredApprovals) 
        payable
        validRequiredApprovals(_owners.length, _requiredApprovals) 
    {
        for (uint i; i < _owners.length; i++) _addOwner(_owners[i]);
        requiredApprovals = _requiredApprovals;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /* OWNER ACTIONS */

    function approve(uint _txId) 
        public 
        onlyOwner 
        txExists(_txId) 
        notExecuted(_txId) 
    {
        require(!approved[_txId][msg.sender], "tx already approved");
        approved[_txId][msg.sender] = true;
        emit Approval(msg.sender, _txId);
    }

    function execute(uint _txId) 
        external
        onlyOwner
        txExists(_txId) 
        notExecuted(_txId)
    {
        require(getApprovalCount(_txId) >= requiredApprovals, "more approvals needed");

        Transaction storage transaction = transactions[_txId];
        transaction.executed = true;
        (bool success,) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        
        require(success, "tx failed");
        emit Execution(_txId);
    }

    function flag(uint _txId) 
        external 
        onlyOwner 
        txExists(_txId) 
        notExecuted(_txId)
    {
        require(!transactions[_txId].flagged, "tx already flagged");
        transactions[_txId].flagged = true;
        emit Flag(msg.sender, _txId);
    }

    function revoke(uint _txId) 
        external 
        onlyOwner 
        txExists(_txId) 
        notExecuted(_txId) 
    {
        require(approved[_txId][msg.sender], "tx not approved");
        approved[_txId][msg.sender] = false;
        emit Revocation(msg.sender, _txId);
    }

    function submitTransaction(address _to, uint _value, bytes calldata _data) 
        external 
        onlyOwner 
        returns (uint txId) 
    {
        _constructTransaction(_to, _value, _data);
        txId = transactions.length - 1;

        emit TransactionRequest(txId);
        approve(txId); 
    }

    /* SPECIAL SUBMITS */ 

    function submitAddOwner(address _newOwner) 
        external 
        onlyOwner 
        maxOwners(owners.length + 1) 
        validOwner(_newOwner) 
        returns (uint txId) 
    {
        _constructTransaction(
            address(this), 
            0, 
            abi.encodeWithSignature("addOwner(address)", _newOwner)
        );
        txId = transactions.length - 1;

        emit OwnerAdditionRequest(_newOwner, txId);
        approve(txId);
    }

    function submitChangeRequiredApprovals(uint8 _requiredApprovals) 
        external 
        onlyOwner 
        validRequiredApprovals(owners.length, _requiredApprovals) 
        returns (uint txId) 
    {
        _constructTransaction(
            address(this), 
            0, 
            abi.encodeWithSignature("changeRequiredApprovals(uint8)", _requiredApprovals)
        );
        txId = transactions.length - 1;

        emit RequirementChangeRequest(_requiredApprovals, txId);
        approve(txId);
    }

    function submitRemoveOwner(address _owner) 
        external 
        onlyOwner 
        alreadyOwner(_owner)
        validRequiredApprovals(owners.length - 1, requiredApprovals - 1) 
        returns (uint txId) 
    {
        _constructTransaction(
            address(this), 
            0,
            abi.encodeWithSignature("removeOwner(address)", _owner)
        );
        txId = transactions.length - 1;
        
        emit OwnerRemovalRequest(_owner, txId);
        approve(txId);
    }

    /* WALLET ACTIONS */

    function addOwner(address _newOwner) 
        external
        onlyWallet 
        // checks performed in _addOwner() to remove duplicate code. bad style? 
    { 
        _addOwner(_newOwner);
        emit OwnerAddition(_newOwner);
    }

    function changeRequiredApprovals(uint8 _requiredApprovals) 
        external 
        onlyWallet
        validRequiredApprovals(owners.length, _requiredApprovals) 
    {
        requiredApprovals = _requiredApprovals;
        emit RequirementChange(requiredApprovals);
    }

    function removeOwner(address _owner) 
        external 
        onlyWallet 
        alreadyOwner(_owner)
        validRequiredApprovals(owners.length - 1, requiredApprovals - 1) 
    {   
        isOwner[_owner] = false;
        for (uint i; i < owners.length - 1; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        }

        owners.pop(); 
        if (requiredApprovals == owners.length) {
            // decrement required approvals if necesssary
            requiredApprovals -= 1; 
            emit RequirementChange(requiredApprovals);
        }
        emit OwnerRemoval(_owner);
    }

    /* VIEW */

    function getApprovalCount(uint _txId) public view returns (uint count) {
        // inconsistency: if owner is removed after approving an unexecuted transaction, 
        // approved[tx][removed owner] = true, but getApprovalCount will not count this.
        // This is acceptable, potentially malicious past transaction will not be 
        // executable without further approval
        for (uint i; i < owners.length; i++) {
            if (approved[_txId][owners[i]]) { 
                count += 1;
            }
        }
    }

    /* INTERNAL HELPER */

    function _addOwner(address _newOwner) 
        private 
        maxOwners(owners.length + 1) 
        validOwner(_newOwner)
    {
        isOwner[_newOwner] = true;
        owners.push(_newOwner);
    }

    function _constructTransaction(address _to, uint _value, bytes memory _data) private {
        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            flagged: false
        }));
    }
}
