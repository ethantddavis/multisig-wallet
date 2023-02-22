// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Wallet.sol";

contract WalletTest is Test {
    Wallet public wallet;
    address public addr1;
    address public addr2;
    address[] public owners;
    bool public executeFlag;

    event Approval(address indexed owner, uint indexed txId);
    event Deposit(address indexed sender, uint amount);
    event Execution(uint indexed txId);
    event Flag(address indexed owner, uint indexed txId);
    event OwnerAddition(address indexed owner);
    event OwnerAdditionRequest(address indexed owner, uint indexed txId);
    event OwnerRemoval(address indexed owner);
    event OwnerRemovalRequest(address indexed owner, uint indexed txId);
    event RequirementChange(uint requiredApprovals);
    event RequirementChangeRequest(uint requiredApprovals, uint indexed txId);
    event Revocation(address indexed owner, uint indexed txId);
    event TransactionRequest(address indexed to, uint value, uint indexed txId);

    function setUp() public {
        owners = [vm.addr(1), vm.addr(2), vm.addr(3), vm.addr(4), vm.addr(5)];
        wallet = new Wallet(owners, 3);
        executeFlag = false;
    }

    function helperSetExecuteFlag() external {
        executeFlag = true;
    }

    /* CONSTRUCTOR */

    function testOneOwner() public {
        address[] memory owner = new address[](1);
        owner[0] = address(this);
        vm.expectRevert();
        new Wallet(owner, 1);
    }

    function testOwnersRecorded() public {
        for (uint i; i < owners.length; i++) { 
            assertEq(owners[i], wallet.owners(i)); 
            assert(wallet.isOwner(owners[i]));
        }
    }

    function testRequiredApprovalsRecorded() public {
        assertEq(wallet.requiredApprovals(), 3);
    }

    function testDepositEmits() public {
        vm.expectEmit(true, false, false, true, address(wallet));
        emit Deposit(address(this), 1);
        payable(wallet).transfer(1);
    }

    /* MODIFIERS */

    function testMaxOwners() public {
        address[] memory manyOwners = new address[](21);
        for (uint i; i < 21; i++) manyOwners[i] = address(0);
        vm.expectRevert("cannot exceed 20 owners");
        new Wallet(manyOwners, 2);
    }

    function testNotExecuted() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.startPrank(owners[0]);
        wallet.execute(txId);
        
        vm.expectRevert("tx already executed");
        wallet.approve(0);
        vm.stopPrank();
    }

    function testOwnerExists() public {
        vm.expectRevert("not owner");
        vm.prank(owners[0]);
        wallet.submitRemoveOwner(address(this));
    }
    
    function testOnlyOwner() public {
        vm.expectRevert("not owner");
        wallet.approve(0);
    }

    function testOnlyWallet() public {
        vm.expectRevert("must be called internaly");
        wallet.addOwner(address(this));
    }

    function testTxExists() public {
        vm.prank(owners[0]);
        vm.expectRevert("tx does not exist");
        wallet.approve(0);
    }

    function testZeroApprovals() public {
        vm.expectRevert("required approvals out of range");
        new Wallet(owners, 0);
    }

    function testApprovalOutOfRange() public {
        vm.expectRevert("required approvals out of range");
        new Wallet(owners, 5);
    }

    function testZeroAddressOwner() public {
        owners.push(address(0));
        vm.expectRevert("invalid owner");
        new Wallet(owners, 2);
    }

    function testDuplicateOwner() public {
        owners.push(vm.addr(1));
        vm.expectRevert("duplicate owner");
        new Wallet(owners, 2);
    }

    function testWalletOwner() public {
        vm.expectRevert("wallet cannot be owner");
        vm.prank(owners[0]);
        wallet.submitAddOwner(address(wallet));
    }

    /* APPROVE */

    function testAlreadyApproved() public {
        vm.startPrank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        vm.expectRevert("tx already approved");
        wallet.approve(txId);
        vm.stopPrank();
    }

    function testApprovalSet() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        vm.prank(owners[1]);
        wallet.approve(txId);
        assert(wallet.approved(txId, owners[1]));
    }

    function testApprovalEmits() public {
        vm.expectEmit(true, true, false, false, address(wallet));
        emit Approval(owners[0], 0);
        vm.prank(owners[0]);
        wallet.submitTransaction(owners[1], 0, "");
    }

    /* EXECUTE */
    
    function testNotEnoughApprovals() public {
        vm.startPrank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        vm.expectRevert("more approvals needed");
        wallet.execute(txId);
        vm.stopPrank();
    }

    function testTransactionExecuted() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        (,,,bool executed,) = wallet.transactions(txId);
        assert(executed);
    }

    function testExecuteCallFails() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(address(this), 0, "");
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        vm.expectRevert();
        wallet.execute(txId);
    }

    function testExecuteCalls() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.expectCall(owners[1], 0, "");
        vm.prank(owners[0]);
        wallet.execute(txId);
    }

    function testExecuteEtherSent() public {
        payable(wallet).transfer(1 ether);
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 1 ether, "");
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assertEq(owners[1].balance, 1 ether);
    }

    function testExecuteCallWithData() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(
            address(this), 
            0, 
            abi.encodeWithSignature("helperSetExecuteFlag()")
        );
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assert(executeFlag);
    }

    function testExecuteEmits() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.expectEmit(true, false, false, false, address(wallet));
        emit Execution(txId);
        vm.prank(owners[0]);
        wallet.execute(txId);
    }

    /* FLAG */

    function testFlagAlreadyFlagged() public {
        vm.startPrank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        wallet.flag(txId);
        vm.expectRevert("tx already flagged");
        wallet.flag(txId);
        vm.stopPrank();
    }

    function testFlagRecorded() public {
        vm.startPrank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        wallet.flag(txId);
        vm.stopPrank();
        (,,,,bool flagged) = wallet.transactions(txId);
        assert(flagged);
    }

    function testFlagEmits() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        vm.expectEmit(true, true, false, false, address(wallet));
        emit Flag(owners[0], txId);
        vm.prank(owners[0]);
        wallet.flag(txId);
    }

    /* REVOKE */

    function testRevokeNotApproved() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        vm.prank(owners[1]);
        vm.expectRevert("tx not approved");
        wallet.revoke(txId);
    }

    function testRevokeApproveSetFalse() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        vm.prank(owners[0]);
        wallet.revoke(txId);
        assert(!wallet.approved(txId, owners[0]));
    }

    function testRevokeExecuteFails() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        for (uint i = 3; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.startPrank(owners[0]);
        wallet.revoke(txId);
        vm.expectRevert("more approvals needed");
        wallet.execute(txId);
        vm.stopPrank();
    }

    function testRevokeEmits() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        vm.expectEmit(true, true, false, false, address(wallet));
        emit Revocation(owners[0], txId);
        vm.prank(owners[0]);
        wallet.revoke(txId);
    }

    /* SUBMIT TRANSACTION */

    function testSubmitTransactionCorrectId() public {
        vm.startPrank(owners[0]);
        assertEq(wallet.submitTransaction(owners[1], 0, ""), 0);
        assertEq(wallet.submitTransaction(owners[1], 0, ""), 1);
        assertEq(wallet.submitTransaction(owners[1], 0, ""), 2);
    }

    function testSubmitTransactionRecorded() public {
        vm.startPrank(owners[0]);
        uint txId = wallet.submitTransaction(owners[1], 0, "");
        (address to, uint value, bytes memory data, bool executed, bool flagged) = wallet.transactions(txId);
        assertEq(to, owners[1]);
        assertEq(value, 0);
        assertEq(data, "");
        assertEq(executed, false);
        assertEq(flagged, false);
    }

    function testSubmitEmits() public {
        vm.expectEmit(true, true, false, true, address(wallet));
        emit TransactionRequest(owners[1], 0, 0);
        vm.prank(owners[0]);
        wallet.submitTransaction(owners[1], 0, "");
    }

    /* ADD OWNER */

    function testSubmitAddOwnerTransactionRecorded() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitAddOwner(address(this));
        (address to, uint value, bytes memory data, bool executed, bool flagged) = wallet.transactions(txId);
        //console.log(data);
        assertEq(to, address(wallet));
        assertEq(value, 0);
        assertEq(data, abi.encodeWithSignature("addOwner(address)", address(this)));
        assertEq(executed, false);
        assertEq(flagged, false);
    }

    function testAddOwnerZeroAddress() public {
        vm.prank(owners[0]);
        vm.expectRevert("invalid owner");
        wallet.submitAddOwner(address(0));
    }

    function testAddOwnerDuplicateOwner() public {
        vm.prank(owners[0]);
        vm.expectRevert("duplicate owner");
        wallet.submitAddOwner(owners[0]);
    }

    function testAddOwnerRecorded() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitAddOwner(address(this));
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assertEq(wallet.owners(owners.length), address(this)); 
        assert(wallet.isOwner(address(this)));
    }

    function testSubmitAddOwnerEmits() public {
        vm.expectEmit(true, true, false, false, address(wallet));
        emit OwnerAdditionRequest(address(this), 0);
        vm.prank(owners[0]);
        wallet.submitAddOwner(address(this));
    }

    function testAddOwnerEmits() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitAddOwner(address(this));
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.expectEmit(true, false, false, false, address(wallet));
        emit OwnerAddition(address(this));
        vm.prank(owners[0]);
        wallet.execute(txId);
    }

    /* CHANGE REQUIRED APPROVALS */

    function testSubmitChangeRequiredApprovalsTransactionRecorded() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitChangeRequiredApprovals(2);
        (address to, uint value, bytes memory data, bool executed, bool flagged) = wallet.transactions(txId);
        //console.log(string(data));
        assertEq(to, address(wallet));
        assertEq(value, 0);
        assertEq(data, abi.encodeWithSignature("changeRequiredApprovals(uint256)", 2));
        assertEq(executed, false);
        assertEq(flagged, false);
    }

    function testRequiredApprovalsChanged() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitChangeRequiredApprovals(4);
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assertEq(wallet.requiredApprovals(), 4);
    }

    function testSubmitRequiredApprovalsChangeEmits() public {
        vm.expectEmit(true, true, false, false, address(wallet));
        emit RequirementChangeRequest(3, 0);
        vm.prank(owners[0]);
        wallet.submitChangeRequiredApprovals(2);
    }

    function testRequiredApprovalsChangeEmits() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitChangeRequiredApprovals(4);
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.expectEmit(true, false, false, false, address(wallet));
        emit RequirementChange(5);
        vm.prank(owners[0]);
        wallet.execute(txId);
    }

    /* REMOVE OWNER */

    function testSubmitRemoveOwnerTransactionRecorded() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitRemoveOwner(owners[3]);
        (address to, uint value, bytes memory data, bool executed, bool flagged) = wallet.transactions(txId);
        //console.log(string(data));
        assertEq(to, address(wallet));
        assertEq(value, 0);
        assertEq(data, abi.encodeWithSignature("removeOwner(address)", owners[3]));
        assertEq(executed, false);
        assertEq(flagged, false);
    }

    function testRemoveOwnerDoesNotExist() public {
        vm.prank(owners[0]);
        vm.expectRevert("not owner");
        wallet.submitRemoveOwner(address(this));
    }

    function testRemoveOwnerSuccess() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitRemoveOwner(owners[1]);
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assert(!wallet.isOwner(owners[1]));
    }

    function testRemoveLastOwner() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitRemoveOwner(owners[owners.length - 1]);
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assert(!wallet.isOwner(owners[owners.length - 1]));
    }

    function testSubmitRemoveOwnerEmits() public {
        vm.expectEmit(true, true, false, false, address(wallet));
        emit OwnerRemovalRequest(owners[1], 0);
        vm.prank(owners[0]);
        wallet.submitRemoveOwner(owners[1]);
    }

    function testRemoveOwnerEmits() public {
        vm.prank(owners[0]);
        uint txId = wallet.submitRemoveOwner(owners[1]);
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.expectEmit(true, false, false, false, address(wallet));
        emit OwnerRemoval(owners[1]);
        vm.prank(owners[0]);
        wallet.execute(txId);
    }
}