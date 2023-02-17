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

    event Approve(address indexed owner, uint indexed txId);
    event Deposit(address indexed sender, uint amount);
    event Execute(uint indexed txId);
    event Revoke(address indexed owner, uint indexed txId);
    event Submit(uint indexed txId);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint _txId) {
        require(_txId < transactions.length, "tx does not exist");
        _;
    }

    modifier notExecuted(uint _txId) {
        require(!transactions[_txId].executed, "tx already executed");
        _;
    }

    constructor(address[] memory _owners, uint _requiredApprovals) {
        require(
            _owners.length >= 2 
            && _owners.length <= 10, 
            "must have 2 <= owners <= 10"
        ); // max of 10 owners 
        require(
            _requiredApprovals > 0 
            && _requiredApprovals < _owners.length, 
            "required approvals out of range"
        ); // required approvals must be less than amount of owners

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

    function approve(uint _txId) 
        public 
        onlyOwner 
        txExists(_txId) 
        notExecuted(_txId) 
    {
        require(!approved[_txId][msg.sender], "tx already approved");
        approved[_txId][msg.sender] = true;
        emit Approve(msg.sender, _txId);
        // IDEA: auto execute option
    }

    function execute(uint _txId) 
        external 
        txExists(_txId) 
        notExecuted(_txId)
    {
        require(_getApprovalCount(_txId) >= requiredApprovals, "more approvals needed");
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
        approve(_txId); //
    }

    function _getApprovalCount(uint _txId) private view returns (uint count) {
        for (uint i; i < owners.length; i++) {
            if (approved[_txId][owners[i]]) {
                count += 1;
            }
        }
    }
}
