// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {BondNFT} from "../src/BondNFT.sol";

contract StakingStablesTest is Test {
    NFTStakingAndBorrowing public nftStaking;
    BondNFT public bondNFT;
    StableBondCoins public stableBondCoins;
    StableCoinsStaking public stakingStables;
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
        nftStaking.whitelistNFT(address(bondNFT), true);

        stakingStables = new StableCoinsStaking(address(stableBondCoins), address(nftStaking));
        nftStaking.setStablesStakingAddress(address(stakingStables));
        vm.stopPrank();
    }

    function test_stake_stables() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 300);
        bondNFT.setAllowedMints(client2, 2, 100);
        bondNFT.setAllowedMints(client3, 3, 200);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 300, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 300);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 100, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 100);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        (uint256 staked,,,,) = stakingStables.stakers(client2);
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));

        vm.startPrank(client3);
        bondNFT.mint(3, 200, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 200);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 3 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));
        console.log("Client3 APY    : ", stakingStables.expectedAPY(client3));

        vm.warp(180 days);
        vm.roll(4);

        console.log("After 180 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));
        console.log("Client3 APY    : ", stakingStables.expectedAPY(client3));

        vm.warp(270 days);
        vm.roll(5);

        console.log("After 270 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));
        console.log("Client3 APY    : ", stakingStables.expectedAPY(client3));

        assertEq(stakingStables.pendingRewards(client2), 608_303265);
        assertEq(stakingStables.pendingRewards(client3), 978_837167);
    }

    function test_withdraw() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 300);
        bondNFT.setAllowedMints(client2, 2, 100);
        bondNFT.setAllowedMints(client3, 3, 200);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 300, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 300);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 100, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 100);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        (uint256 staked,,,,) = stakingStables.stakers(client2);
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));

        vm.startPrank(client3);
        bondNFT.mint(3, 200, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 200);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 3 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));
        console.log("Client3 APY    : ", stakingStables.expectedAPY(client3));

        vm.prank(client2);
        stakingStables.withdraw(staked / 2);

        vm.warp(180 days);
        vm.roll(4);

        console.log("After 180 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));
        console.log("Client3 APY    : ", stakingStables.expectedAPY(client3));

        vm.prank(client2);
        stakingStables.withdraw(staked / 2);

        vm.warp(270 days);
        vm.roll(5);

        console.log("After 270 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));
        console.log("Client3 APY    : ", stakingStables.expectedAPY(client3));

        (staked,,,,) = stakingStables.stakers(client2);
        assertEq(staked, 0);
    }

    function test_rewards() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 300);
        bondNFT.setAllowedMints(client2, 2, 100);
        bondNFT.setAllowedMints(client3, 3, 200);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 300, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 300);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 100, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 100);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        (uint256 staked,,,,) = stakingStables.stakers(client2);
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        uint256 client2Rewards = stakingStables.pendingRewards(client2);
        console.log("Client2 rewards: ", client2Rewards);
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));

        vm.prank(client2);
        stakingStables.claimRewards();

        assertEq(stableBondCoins.balanceOf(client2), client2Rewards);

        vm.startPrank(client3);
        bondNFT.mint(3, 200, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 200);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 3 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client3 staked : ", amount);
        uint256 client2Rewards2 = stakingStables.pendingRewards(client2);
        console.log("Client2 rewards: ", client2Rewards2);
        uint256 client3Rewards = stakingStables.pendingRewards(client3);
        console.log("Client3 rewards: ", client3Rewards);
        console.log("Client2 APY    : ", stakingStables.expectedAPY(client2));
        console.log("Client3 APY    : ", stakingStables.expectedAPY(client3));

        vm.prank(client2);
        stakingStables.claimRewards();
        vm.prank(client3);
        stakingStables.claimRewards();

        assertEq(stableBondCoins.balanceOf(client2), client2Rewards + client2Rewards2);
        assertEq(stableBondCoins.balanceOf(client3), client3Rewards);
    }
}
