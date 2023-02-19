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
        owners = [vm.addr(1), vm.addr(2), vm.addr(3), vm.addr(4)];
        wallet = new Wallet(owners, 3);
        executeFlag = false;
    }

    function helperSetExecuteFlag() external {
        executeFlag = true;
    }

    /* CONSTRUCTOR */

    function testZeroOwners() public {
        address[] memory emptyOwners;
        vm.expectRevert("must have 2 <= owners <= 10");
        new Wallet(emptyOwners, 0);
    }

    function testTooManyOwners() public {
        address[] memory manyOwners = new address[](11);
        for (uint i; i < 11; i++) manyOwners[i] = address(0);
        vm.expectRevert("must have 2 <= owners <= 10");
        new Wallet(manyOwners, 0);
    }

    function testZeroApprovals() public {
        vm.expectRevert("required approvals out of range");
        new Wallet(owners, 0);
    }

    function testApprovalOutOfRange() public {
        vm.expectRevert("required approvals out of range");
        new Wallet(owners, 4);
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

    function testOnlyOwner() public {
        vm.expectRevert("not owner");
        wallet.approve(0);
    }

    function testTxExists() public {
        vm.prank(owners[0]);
        vm.expectRevert("tx does not exist");
        wallet.approve(0);
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
        for (uint i = 2; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        vm.startPrank(owners[0]);
        wallet.revoke(txId);
        vm.expectRevert("more approvals needed");
        wallet.execute(txId);
        vm.stopPrank();
    }

    /* APPROVE */

    function testSubmitTransactionRecorded() public {
        vm.prank(owners[0]);
        uint _value = 0;
        bytes memory _data = "";
        wallet.submit(owners[1], _value, _data);
        uint txId = 0;
        (address to, uint value, bytes memory data, bool executed) = wallet.transactions(txId);
        assertEq(to, owners[1]);
        assertEq(value, _value);
        assertEq(data, _data);
        assertEq(executed, false);
    }

    function testSubmitTransactionApprovedBySender() public {
        vm.prank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
        assert(wallet.approved(txId, owners[0]));
    }

    function testSubmitTransactionNotApprovedByNonSender() public {
        vm.prank(owners[0]);
        wallet.submit(owners[1], 0, "");
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) assert(!wallet.approved(txId, owners[i])); 
    }

    /* ADD OWNER */

    function testAddOwner() public {
        vm.prank(owners[0]);
        wallet.submitAddOwner(address(this));
        uint txId = 0;
        for (uint i = 1; i < owners.length; i++) {
            vm.prank(owners[i]);
            wallet.approve(txId);
        }
        

        vm.prank(owners[0]);
        wallet.execute(txId);
        (address to, uint value, bytes memory data, bool executed) = wallet.transactions(txId);
        console.log(to);
        console.log(executed);
        for (uint i; i < 5; i++ ) console.log(wallet.owners(i));
        console.log(address(this));
        assertEq(data, "");
    }

}