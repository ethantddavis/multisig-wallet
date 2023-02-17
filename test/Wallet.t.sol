// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Wallet.sol";

contract WalletTest is Test {
    Wallet public wallet;
    address public addr1;
    address public addr2;
    address[] public owners;

    function setUp() public {
        owners = [vm.addr(1), vm.addr(2), vm.addr(3), vm.addr(4)];
        wallet = new Wallet(owners, 3);
    }

    /* CONSTRUCTOR */

    function testZeroOwners() public {
        address[] memory emptyOwners;
        vm.expectRevert("must have 2 <= owners <= 10");
        new Wallet(emptyOwners, 0);
    }

    function testTooManyOwners() public {
        address[] memory manyOwners = new address[](11);
        for (uint i; i < 11; i++) { manyOwners[i] = address(0); }
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

    

}