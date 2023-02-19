// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Wallet.sol";

contract WalletTest is Test {
    Wallet public wallet;
    address public addr1;
    address public addr2;
    address[] public owners;
    bool public executeFlag;

    function setUp() public {
        owners = [vm.addr(1), vm.addr(2), vm.addr(3), vm.addr(4), vm.addr(5)];
        wallet = new Wallet(owners, 3);
        executeFlag = false;
    }

    function helperSetExecuteFlag() external {
        executeFlag = true;
    }

    /* CONSTRUCTOR */
    
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

    function testOwnersRecorded() public {
        for (uint i; i < owners.length; i++) { 
            assertEq(owners[i], wallet.owners(i)); 
            assert(wallet.isOwner(owners[i]));
        }
    }

    function testRequiredApprovalsRecorded() public {
        assertEq(wallet.requiredApprovals(), 3);
    }

    /* MODIFIERS */

    function testMaxOwners() public {
        address[] memory manyOwners = new address[](21);
        for (uint i; i < 21; i++) manyOwners[i] = address(0);
        vm.expectRevert("must have owners <= 20");
        new Wallet(manyOwners, 2);
    }

    function testNotExecuted() public {
        vm.prank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
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

    /* APPROVE */

    function testAlreadyApproved() public {
        vm.startPrank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
        vm.expectRevert("tx already approved");
        wallet.approve(txId);
        vm.stopPrank();
    }

    function testApprovalSet() public {
        vm.prank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
        vm.prank(owners[1]);
        wallet.approve(txId);
        assert(wallet.approved(txId, owners[1]));
    }

    /* EXECUTE */
    
    function testNotEnoughApprovals() public {
        vm.startPrank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
        vm.expectRevert("more approvals needed");
        wallet.execute(txId);
        vm.stopPrank();
    }

    function testTransactionExecuted() public {
        vm.prank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        (,,, bool executed) = wallet.transactions(txId);
        assert(executed);
    }

    function testExecuteCallFails() public {
        vm.prank(owners[0]);
        wallet.submit(address(this), 0, "");
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        vm.expectRevert("tx failed");
        wallet.execute(txId);
    }

    function testExecuteEtherSent() public {
        payable(wallet).transfer(1 ether);
        vm.prank(owners[0]);
        wallet.submit(owners[1], 1 ether, "");
        uint txId = 0;
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
        wallet.submit(address(this), 0, abi.encodeWithSignature("helperSetExecuteFlag()"));
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assert(executeFlag);
    }

    /* REVOKE */

    function testRevokeNotApproved() public {
        vm.prank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
        vm.prank(owners[1]);
        vm.expectRevert("tx not approved");
        wallet.revoke(txId);
    }

    function testRevokeApproveSetFalse() public {
        vm.prank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
        vm.prank(owners[0]);
        wallet.revoke(txId);
        assert(!wallet.approved(txId, owners[0]));
    }

    function testRevokeExecuteFails() public {
        vm.prank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
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

    /* ADD OWNER */

    function testSubmitAddOwnerTransactionRecorded() public {
        vm.prank(owners[0]);
        wallet.submitAddOwner(address(this));
        uint txId = 0;
        (address to, uint value, bytes memory data, bool executed) = wallet.transactions(txId);
        assertEq(to, address(wallet));
        assertEq(value, 0);
        assertEq(data, abi.encodeWithSignature("addOwner(address)", address(this)));
        assertEq(executed, false);
    }

    function testAddOwnerZeroAddress() public {
        vm.prank(owners[0]);
        wallet.submitAddOwner(address(0));
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        vm.expectRevert("tx failed");
        wallet.execute(txId);
    }

    function testAddOwnerDuplicateOwner() public {
        vm.prank(owners[0]);
        wallet.submitAddOwner(owners[0]);
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        vm.expectRevert("tx failed");
        wallet.execute(txId);
    }

    function testAddOwnerRecorded() public {
        vm.prank(owners[0]);
        wallet.submitAddOwner(address(this));
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assertEq(wallet.owners(owners.length), address(this)); 
        assert(wallet.isOwner(address(this)));
    }

    /* CHANGE REQUIRED APPROVALS */

    function testSubmitChangeRequiredApprovalsTransactionRecorded() public {
        vm.prank(owners[0]);
        wallet.submitChangeRequiredApprovals(2);
        uint txId = 0;
        (address to, uint value, bytes memory data, bool executed) = wallet.transactions(txId);
        assertEq(to, address(wallet));
        assertEq(value, 0);
        assertEq(data, abi.encodeWithSignature("changeRequiredApprovals(uint8)", 2));
        assertEq(executed, false);
    }

    function testRequiredApprovalsChanged() public {
        vm.prank(owners[0]);
        wallet.submitChangeRequiredApprovals(4);
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assertEq(wallet.requiredApprovals(), 4);
    }

    /* REMOVE OWNER */

    function testSubmitRemoveOwnerTransactionRecorded() public {
        vm.prank(owners[0]);
        wallet.submitRemoveOwner(owners[3]);
        uint txId = 0;
        (address to, uint value, bytes memory data, bool executed) = wallet.transactions(txId);
        assertEq(to, address(wallet));
        assertEq(value, 0);
        assertEq(data, abi.encodeWithSignature("removeOwner(address)", owners[3]));
        assertEq(executed, false);
    }

    function testRemoveOwnerDoesNotExist() public {
        vm.prank(owners[0]);
        wallet.submitRemoveOwner(address(this));
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        vm.expectRevert("tx failed");
        wallet.execute(txId);
    }

    function testRemoveTooManyOwners() public {
        vm.startPrank(owners[0]);
        wallet.submitRemoveOwner(owners[2]);
        wallet.submitRemoveOwner(owners[3]);
        vm.stopPrank();
        uint tx1 = 0;
        uint tx2 = 1;
        for (uint i = 1; i < owners.length; i++) {
            vm.startPrank(owners[i]);
            wallet.approve(tx1);
            wallet.approve(tx2);
            vm.stopPrank();
        }
        vm.startPrank(owners[0]);
        wallet.execute(tx1);
        vm.expectRevert("tx failed");
        wallet.execute(tx2);
        vm.stopPrank();
    }

    function testRemoveOwnerSuccess() public {
        vm.prank(owners[0]);
        wallet.submitRemoveOwner(owners[1]);
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.prank(owners[0]);
        wallet.execute(txId);
        assert(!wallet.isOwner(owners[1]));
    }
}