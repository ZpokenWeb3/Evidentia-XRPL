// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {BondNFT} from "../src/BondNFT.sol";

contract NFTStakingAndBorrowingTest is Test {
    NFTStakingAndBorrowing public nftStaking;
    BondNFT public bondNFT;
    StableBondCoins public stableBondCoins;
    address public owner;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public {
        owner = address(1);
        vm.startPrank(owner);
        bondNFT = new BondNFT(owner, "https://example.com/{id}.json");
        stableBondCoins = new StableBondCoins(owner, owner);

        nftStaking = new NFTStakingAndBorrowing(address(stableBondCoins));

        stableBondCoins.grantRole(MINTER_ROLE, address(nftStaking));
        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 100_000000,
            couponValue: 0,
            issueTimestamp: 1,
            expirationTimestamp: 1 + 31536000,
            CUSIP: "912797LX3"
        });

        bondNFT.setMetaData(1, metadata);
        bondNFT.setMetaData(2, metadata);
        bondNFT.setMetaData(3, metadata);
        bondNFT.setAllowedMints(owner, 1, 100);
        bondNFT.setAllowedMints(owner, 2, 100);
        bondNFT.setAllowedMints(owner, 3, 100);
        bondNFT.mint(1, 100, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.whitelistNFT(address(bondNFT), true);
        vm.stopPrank();
    }

    function test_stakeNFT() public {
        owner = address(1);
        vm.prank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 100);
        console.log(address(this));
        assertEq(stableBondCoins.balanceOf(address(nftStaking)), 9700_000000);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();

        assertEq(totalStats.staked, 9700_000000);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 9700_000000);
    }

    function test_borrow() public {
        owner = address(1);

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 970_000000);
        assertEq(nftStaking.userAvailableToBorrow(owner), 932_692306);

        nftStaking.borrow(500_000000);
        vm.stopPrank();

        userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.borrowed, 500_000000);
        assertEq(nftStaking.userAvailableToBorrow(owner), 432_692307);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();
        assertEq(totalStats.borrowed, 500_000000);

        vm.roll(12345);
        vm.warp(1 + 30 days);

        userStats = nftStaking.getUserStats(owner);
        totalStats = nftStaking.getTotalStats();
        assertEq(nftStaking.userAvailableToBorrow(owner), 434_089394);
        assertEq(userStats.debtUpdateTimestamp, 2592001);
        assertEq(totalStats.debt, 501_614410);
        assertEq(userStats.debt, 501_614410);
    }

    function test_unstake() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 3, 10);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(3, 10, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.warp(30 days);
        vm.roll(3);
        // Client1 makes some staking
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);

        vm.warp(35 days);
        vm.roll(4);
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.staked, 970_000000);

        // Client borrows less than a half of available
        uint256 borrow_amount = nftStaking.userAvailableToBorrow(client1) / 2;
        vm.prank(client1);
        nftStaking.borrow(borrow_amount);

        // User unstakes
        vm.prank(client1);
        nftStaking.unstakeNFT(address(bondNFT), 2, 4);

        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.staked, 6 * 970_000000 / 10);
        assertLe(nftStaking.userAvailableToBorrow(client1), borrow_amount);
    }

    function test_repay() public {
        owner = address(1);

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 970_000000);
        assertEq(nftStaking.userAvailableToBorrow(owner), 932_692306);

        nftStaking.borrow(500_000000);

        userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.borrowed, 500_000000);
        assertEq(nftStaking.userAvailableToBorrow(owner), 432_692307);

        stableBondCoins.approve(address(nftStaking), 500_000000);
        nftStaking.repay(500_000000);

        vm.stopPrank();

        userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.borrowed, 0);
        assertEq(nftStaking.userAvailableToBorrow(owner), 932_692306);
    }
}
