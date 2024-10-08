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

    IMintableERC20 public stableToken;

    constructor(address _stableToken) ERC1155Holder() Ownable(msg.sender) {
        stableToken = IMintableERC20(_stableToken);
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

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function stakeNFT(address nftAddress, uint256 tokenId, uint256 amount) public {
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
    }
}
