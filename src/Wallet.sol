// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

contract Wallet {

    struct Transaction {
        address to; 
        uint value;
        bytes data;
        bool executed;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint public requiredApprovals;

    Transaction[] public transactions; // each executed only if enough required approvals
    mapping(uint => mapping(address => bool)) public approved; // txId -> owners -> approved

    event AddOwner(address indexed owner, uint indexed txId);
    event Approve(address indexed owner, uint indexed txId);
    event ChangeRequiredApprovals(uint requiredApprovals);
    event Deposit(address indexed sender, uint amount);
    event Execute(uint indexed txId);
    event RemoveOwner(address indexed owner, uint indexed txId);
    event Revoke(address indexed owner, uint indexed txId);
    event Submit(uint indexed txId);
    event SubmitAddOwner(address indexed owner, uint indexed txId);
    event SubmitChangeRequiredApprovals(uint requiredApprovals);
    event SubmitRemoveOwner(address indexed owner, uint indexed txId);

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

    constructor(address[] memory _owners, uint _requiredApprovals) 
        validRequiredApprovals(_owners.length, _requiredApprovals) 
    {
        require(
            _owners.length >= 2 
            && _owners.length <= 10, 
            "must have 2 <= owners <= 10"
        ); // max of 10 owners 
        

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
        // IDEA: auto execute option after last approve
    }

    function execute(uint _txId) 
        external 
        txExists(_txId) 
        notExecuted(_txId)
    {
        require(getApprovalCount(_txId) >= requiredApprovals, "more approvals needed");
        Transaction storage transaction = transactions[_txId];

        transaction.executed = true;

        (bool success, ) = transaction.to.call{value: transaction.value}(
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

    function submit(address _to, uint _value, bytes calldata _data) external onlyOwner {
        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false
        }));

        uint _txId = transactions.length - 1;
        emit Submit(_txId);
        approve(_txId); 
    }

    /* SPECIAL SUBMITS */

    function submitAddOwner(address _newOwner) external onlyOwner {
        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: abi.encodeWithSignature("addOwner(address)", _newOwner),
            executed: false
        })); 

        uint _txId = transactions.length - 1;
        emit SubmitAddOwner(_newOwner, _txId);
        approve(_txId);
    }

    function submitChangeRequiredApprovals(uint _requiredApprovals) external onlyOwner {
        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: abi.encodeWithSignature("changeRequiredApprovals(uint)", _requiredApprovals),
            executed: false
        })); 

        uint _txId = transactions.length - 1;
        emit SubmitChangeRequiredApprovals(_requiredApprovals);
        approve(_txId);
    }

    function submitRemoveOwner(address _owner) external onlyOwner {
        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: abi.encodeWithSignature("removeOwner(address)", _owner),
            executed: false
        })); 

        uint _txId = transactions.length - 1;
        emit SubmitRemoveOwner(_owner, _txId);
        approve(_txId);
    }

    /* ONLY WALLET */

    function addOwner(address _newOwner) external onlyWallet { 
        require(_newOwner != address(0), "invalid owner");
        require(!isOwner[_newOwner], "duplicate owner");
        require(owners.length + 1 <= 10, "must have owners <= 10"); 

        isOwner[_newOwner] = true;
        owners.push(_newOwner);
    }

    function changeRequiredApprovals(uint _requiredApprovals) 
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
    { 
        require(isOwner[_owner], "not owner");
        require(owners.length - 1 >= 2, "must have owners >= 2"); 

        isOwner[_owner] = false;
        for (uint i; i < owners.length - 1; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        }
        owners.pop();
    }

    /* PRIVATE */

    function getApprovalCount(uint _txId) private view returns (uint count) {
        for (uint i; i < owners.length; i++) {
            if (approved[_txId][owners[i]]) {
                count += 1;
            }
        }
    }
}
