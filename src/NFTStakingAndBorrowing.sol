// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {IBondNFT} from "./Interfaces/IBondNFT.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

interface IMintableERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

contract NFTStakingAndBorrowing is ERC1155Holder, Ownable {
    struct TotalStats {
        uint256 staked;
        uint256 borrowed;
        uint256 debt;
        uint256 debtUpdateTimestamp;
    }

    struct UserStats {
        uint256 staked;
        uint256 nominalAvailable;
        uint256 borrowed;
        uint256 debt;
        uint256 debtUpdateTimestamp;
    }

    TotalStats internal totalStats;

    mapping(address => bool) public whitelistedNFTs;
    mapping(address => UserStats) internal userStats;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public userNFTs;

    uint256 internal constant YEAR_IN_SECONDS = 31536000; // 365 days
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant BPS = 1e4;
    uint256 public PROTOCOL_YIELD = 400 * UNIT / BPS;
    uint256 public SAFETY_FEE = 300 * UNIT / BPS;
    uint256 public LIQUIDATION_TIME_WINDOW = 45 * 24 * 60 * 60; // 45 days
    uint256 public RewardsTransfered;
    address public STABLES_STAKING_ADDRESS;

    IMintableERC20 public stableToken;

    event NFTStaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event NFTUnstaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user, address liquidator, address indexed nftAddress, uint256 tokenId, uint256 amount
    );

    error NFTNotWhitelisted();
    error InsufficientNFTBalance();
    error BorrowAmountExceedsLimit(uint256);
    error InsufficientBalanceToRepay();
    error NotEnoughCollateral(uint256);
    error TooEarlyToLiquidate();

    constructor(address _stableToken) ERC1155Holder() Ownable(msg.sender) {
        stableToken = IMintableERC20(_stableToken);
    }

    modifier onlyStablesStaking() {
        require(msg.sender == STABLES_STAKING_ADDRESS, "Only Stables Staking contract");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function whitelistNFT(address nftAddress, bool status) external onlyOwner {
        whitelistedNFTs[nftAddress] = status;
    }

    function setProtocolYield(uint256 _protocolYieldInBPS) external onlyOwner {
        PROTOCOL_YIELD = _protocolYieldInBPS * UNIT / BPS;
    }

    function setSafetyFee(uint256 _safetyFeeInBPS) external onlyOwner {
        SAFETY_FEE = _safetyFeeInBPS * UNIT / BPS;
    }

    function setLiquidationTimeWindow(uint256 _timeWindowInSeconds) external onlyOwner {
        LIQUIDATION_TIME_WINDOW = _timeWindowInSeconds;
    }

    function setStablesStakingAddress(address _address) external onlyOwner {
        STABLES_STAKING_ADDRESS = _address;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getUserStats(address userAddress) public view returns (UserStats memory) {
        if (userStats[userAddress].debtUpdateTimestamp == block.timestamp) {
            return userStats[userAddress];
        }
        uint256 updatedDebt = 0;
        if (userStats[userAddress].debt != 0) {
            updatedDebt =
                calculateDebt(userStats[userAddress].debt, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
        }
        uint256 updatedNominalAvailable = calculateDebt(
            userStats[userAddress].nominalAvailable, userStats[userAddress].debtUpdateTimestamp, block.timestamp
        );
        UserStats memory updatedUserStats = UserStats(
            userStats[userAddress].staked,
            updatedNominalAvailable,
            userStats[userAddress].borrowed,
            updatedDebt,
            block.timestamp
        );
        return updatedUserStats;
    }

    function getTotalStats() public view returns (TotalStats memory) {
        if (totalStats.debtUpdateTimestamp == block.timestamp) {
            return totalStats;
        }
        uint256 updatedDebt = 0;
        if (totalStats.debt != 0) {
            updatedDebt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
        }

        TotalStats memory updatedTotalStats =
            TotalStats(totalStats.staked, totalStats.borrowed, updatedDebt, block.timestamp);
        return updatedTotalStats;
    }

    function calculateDebt(uint256 borrowedAmount, uint256 fromTime, uint256 toTime) internal view returns (uint256) {
        borrowedAmount = borrowedAmount * 1e18;
        UD60x18 timeDelta = ud(toTime - fromTime);
        UD60x18 debtLog2 =
            (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(UNIT + PROTOCOL_YIELD)).log2() + ud(borrowedAmount).log2();
        return debtLog2.exp2().intoUint256() / 1e18;
    }

    function calculateMaxBorrow(uint256 totalAmount, uint256 fromTime, uint256 toTime) public view returns (uint256) {
        totalAmount = totalAmount * 1e18;
        UD60x18 timeDelta = ud(toTime - fromTime);
        UD60x18 maxBorrowLog2 =
            ud(totalAmount).log2() - (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(UNIT + PROTOCOL_YIELD)).log2();

        return maxBorrowLog2.exp2().intoUint256() / 1e18;
    }

    function userAvailableToBorrow(address userAddress) public view returns (uint256) {
        if (userStats[userAddress].nominalAvailable == 0) return 0;

        uint256 nominalAvailable = calculateDebt(
            userStats[userAddress].nominalAvailable, userStats[userAddress].debtUpdateTimestamp, block.timestamp
        );
        if (userStats[userAddress].debt == 0) {
            return nominalAvailable;
        } else {
            uint256 debt =
                calculateDebt(userStats[userAddress].debt, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
            return nominalAvailable - debt;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function stakeNFT(address nftAddress, uint256 tokenId, uint256 amount) public {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if (IBondNFT(nftAddress).balanceOf(msg.sender, tokenId) < amount) revert InsufficientNFTBalance();

        IBondNFT(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        userNFTs[msg.sender][nftAddress][tokenId] = amount;

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);

        uint256 totalValue = (metadata.value + metadata.couponValue) * amount * (UNIT - SAFETY_FEE) / UNIT;

        totalStats.staked += totalValue;

        userStats[msg.sender].staked += totalValue;
        userStats[msg.sender].nominalAvailable +=
            calculateMaxBorrow(totalValue, block.timestamp, metadata.expirationTimestamp);
        userStats[msg.sender].debtUpdateTimestamp = block.timestamp;

        stableToken.mint(address(this), totalValue);

        emit NFTStaked(msg.sender, nftAddress, tokenId, amount);
    }

    function unstakeNFT(address nftAddress, uint256 tokenId, uint256 amount) external {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        // Only NFT owner can unstake anytime
        if (userNFTs[msg.sender][nftAddress][tokenId] < amount) revert InsufficientNFTBalance();

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        uint256 totalUnstakeValue = (metadata.value + metadata.couponValue) * amount * (UNIT - SAFETY_FEE) / UNIT;

        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        // Check if user has enough collateral
        if (
            calculateMaxBorrow(totalUnstakeValue, block.timestamp, metadata.expirationTimestamp)
                > userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt
        ) {
            revert NotEnoughCollateral(userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt);
        }

        userNFTs[msg.sender][nftAddress][tokenId] -= amount;

        userStats[msg.sender].staked -= totalUnstakeValue;
        userStats[msg.sender].nominalAvailable -=
            calculateMaxBorrow(totalUnstakeValue, block.timestamp, metadata.expirationTimestamp);
        totalStats.staked -= totalUnstakeValue;

        IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");

        stableToken.burn(address(this), totalUnstakeValue);

        emit NFTUnstaked(msg.sender, nftAddress, tokenId, amount);
    }

    function borrow(uint256 amount) public {
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();
        uint256 max_borrow = userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt;
        if (amount == 0) {
            amount = max_borrow;
        }

        if (amount > max_borrow) {
            revert BorrowAmountExceedsLimit(max_borrow);
        }

        _borrow(amount, msg.sender);

        stableToken.transfer(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        if (amount == 0) amount = userStats[msg.sender].debt;

        if (stableToken.balanceOf(msg.sender) < amount) revert InsufficientBalanceToRepay();

        stableToken.transferFrom(msg.sender, address(this), amount);
        userStats[msg.sender].debt -= amount;
        userStats[msg.sender].borrowed -= amount;

        totalStats.borrowed -= amount;
        totalStats.debt -= amount;

        emit Repaid(msg.sender, amount);
    }

    function liquidate(address nftAddress, uint256 tokenId, address positionOwner) external {
        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        if (block.timestamp < metadata.expirationTimestamp - LIQUIDATION_TIME_WINDOW) revert TooEarlyToLiquidate();
        // Work in progress...
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _borrow(uint256 amount, address user_address) internal {
        userStats[user_address].debt += amount;
        userStats[user_address].borrowed += amount;
        totalStats.borrowed += amount;
        totalStats.debt += amount;

        emit Borrowed(user_address, amount);
    }

    function updateUserDebtAndAvailable(address userAddress) internal {
        if (userStats[userAddress].debtUpdateTimestamp == block.timestamp) return;

        if (userStats[userAddress].debt != 0) {
            userStats[userAddress].debt =
                calculateDebt(userStats[userAddress].debt, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
        }
        if (userStats[userAddress].nominalAvailable != 0) {
            userStats[userAddress].nominalAvailable = calculateDebt(
                userStats[userAddress].nominalAvailable, userStats[userAddress].debtUpdateTimestamp, block.timestamp
            );
        }
        userStats[userAddress].debtUpdateTimestamp = block.timestamp;
    }

    function updateTotalDebt() internal {
        if (totalStats.debtUpdateTimestamp == block.timestamp) return;

        if (totalStats.debt != 0) {
            totalStats.debt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
        }
        totalStats.debtUpdateTimestamp = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                    STABLE COINS STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getRewardAmount() external view returns (uint256) {
        uint256 currentDebt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
        uint256 rewardAmount = currentDebt - totalStats.borrowed - RewardsTransfered;
        return rewardAmount;
    }

    function getRewards() external onlyStablesStaking returns (uint256) {
        uint256 currentDebt;
        if (totalStats.debtUpdateTimestamp == block.timestamp) {
            currentDebt = totalStats.debt;
        } else {
            currentDebt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
        }

        uint256 rewardAmount = currentDebt - totalStats.borrowed - RewardsTransfered;
        if (rewardAmount > 0) {
            stableToken.transfer(msg.sender, rewardAmount);
        }
        RewardsTransfered += rewardAmount;
        return rewardAmount;
    }
}
