// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

// goerli test constructor params ["0x2DD0e7C4EfF32E33f5fcaeE2aadC99C691134bB5", "0xe6BEE98547975b34EE233862549140C4EF679e5C", "0xDC5f40b6fF4195cbFe77803D4bba14A6b9339Cb9"], 2
// goerli deployed address 0xA1bB7806B0E68A1150d5699058744Dc1882233CA on 2/19/22

contract Wallet {

    event AddOwner(address indexed owner);
    event Approve(address indexed owner, uint indexed txId);
    event ChangeRequiredApprovals(uint8 requiredApprovals);
    event Deposit(address indexed sender, uint amount);
    event Execute(uint indexed txId);
    event RemoveOwner(address indexed owner);
    event Revert(bytes data);
    event Revoke(address indexed owner, uint indexed txId);
    event Submit(uint indexed txId);
    event SubmitAddOwner(address indexed owner, uint indexed txId);
    event SubmitChangeRequiredApprovals(uint8 requiredApprovals, uint indexed txId);
    event SubmitRemoveOwner(address indexed owner, uint indexed txId);

    uint8 public constant MAX_OWNERS = 20;

    uint8 public requiredApprovals;
    address[] public owners;
    mapping(address => bool) public isOwner; // address -> owner status

    Transaction[] public transactions; 
    mapping(uint => mapping(address => bool)) public approved; // txId -> owners -> approved

    struct Transaction {
        address to; 
        uint value;
        bytes data;
        bool executed;
        // bool failed;
    }

    modifier maxOwners(uint _numOwners) {
        require(_numOwners <= MAX_OWNERS, "must have owners <= 20");
        _; // because 0 < requiredApprovals < numOwners, 2 <= numOwners <= 20
    }
    
    modifier notExecuted(uint _txId) {
        require(!transactions[_txId].executed, "tx already executed");
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

    modifier validRequiredApprovals(uint _numOwners, uint _requiredApprovals) {
        require(
            _requiredApprovals > 0 
            && _requiredApprovals < _numOwners, 
            "required approvals out of range"
        ); // required approvals must be less than amount of owners
        _;
    }

    constructor(address[] memory _owners, uint8 _requiredApprovals) 
        payable
        validRequiredApprovals(_owners.length, _requiredApprovals) 
        maxOwners(_owners.length)
    {
        for (uint i; i < _owners.length; i++) {
            require(_owners[i] != address(0), "invalid owner");
            require(!isOwner[_owners[i]], "duplicate owner");
            
            isOwner[_owners[i]] = true;
            owners.push(_owners[i]);
        }

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
        emit Approve(msg.sender, _txId);
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
        emit Execute(_txId);
    }

    function revoke(uint _txId) 
        external 
        onlyOwner 
        txExists(_txId) 
        notExecuted(_txId) 
    {
        require(approved[_txId][msg.sender], "tx not approved");
        approved[_txId][msg.sender] = false;
        emit Revoke(msg.sender, _txId);
    }

    function submitTransaction(address _to, uint _value, bytes calldata _data) external onlyOwner returns (uint txId) {
        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false
        }));

        txId = transactions.length - 1;
        emit Submit(txId);
        approve(txId); 
    }

    /* SPECIAL SUBMITS */

    function submitAddOwner(address _newOwner) external onlyOwner returns (uint txId) {
        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: abi.encodeWithSignature("addOwner(address)", _newOwner),
            executed: false
        })); 

        txId = transactions.length - 1;
        emit SubmitAddOwner(_newOwner, txId);
        approve(txId);
    }

    function submitChangeRequiredApprovals(uint8 _requiredApprovals) external onlyOwner returns (uint txId) {
        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: abi.encodeWithSignature("changeRequiredApprovals(uint8)", _requiredApprovals),
            executed: false
        })); 

        txId = transactions.length - 1;
        emit SubmitChangeRequiredApprovals(_requiredApprovals, txId);
        approve(txId);
    }

    function submitRemoveOwner(address _owner) external onlyOwner returns (uint txId) {
        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: abi.encodeWithSignature("removeOwner(address)", _owner),
            executed: false
        })); 

        txId = transactions.length - 1;
        emit SubmitRemoveOwner(_owner, txId);
        approve(txId);
    }

    /* WALLET ACTIONS */

    function addOwner(address _newOwner) 
        external 
        onlyWallet 
        maxOwners(owners.length + 1) 
    { 
        require(_newOwner != address(0), "invalid owner");
        require(!isOwner[_newOwner], "duplicate owner");

        isOwner[_newOwner] = true;
        owners.push(_newOwner);
        emit AddOwner(_newOwner);
    }

    function changeRequiredApprovals(uint8 _requiredApprovals) 
        external 
        onlyWallet
        validRequiredApprovals(owners.length, _requiredApprovals) 
    {
        requiredApprovals = _requiredApprovals;
        emit ChangeRequiredApprovals(requiredApprovals);
    }

    function removeOwner(address _owner) 
        external 
        onlyWallet 
        validRequiredApprovals(owners.length - 1, requiredApprovals) 
            // decrement required approvals instead of revert?
    { 
        require(isOwner[_owner], "not owner");
        
        isOwner[_owner] = false;
        for (uint i; i < owners.length - 1; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        }

        owners.pop(); 
        emit RemoveOwner(_owner);
    }

    /* VIEW */

    function getApprovalCount(uint _txId) public view returns (uint count) {
        for (uint i; i < owners.length; i++) {
            if (approved[_txId][owners[i]]) { 
                // issue: if owner is removed after approving an unexecuted transaction, 
                // approved[tx][removed-owner] = true, but getApprovalCount will not count this.
                // This is fine? potentially malicious past transaction will not be executable 
                // without further approval 
                count += 1;
            }
        }
    }
}
