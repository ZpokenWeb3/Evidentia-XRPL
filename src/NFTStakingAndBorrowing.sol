// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

contract NFTStakingAndBorrowing {
    uint256 internal constant YEAR_IN_SECONDS = 31536000; // 365 days
    uint256 internal constant DECIMALS_MULTIPLIER = 1e18;
    uint256 internal constant BPS = 1e4;
    uint256 internal lastUpdateTimestamp;

    uint256 public constant PROTOCOL_YIELD = 1200 * DECIMALS_MULTIPLIER / BPS;

    function calculateDebt(uint256 borrowedAmount, uint256 currentTime, uint256 expirationTime)
        public
        pure
        returns (uint256)
    {
        UD60x18 timeDelta = ud(expirationTime) - ud(currentTime);

        UD60x18 debtLog2 = (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(DECIMALS_MULTIPLIER) + ud(PROTOCOL_YIELD)).log2()
            + ud(borrowedAmount).log2();

        return debtLog2.exp2().intoUint256();
    }

    function calculateMaxBorrow(uint256 totalAmount, uint256 currentTime, uint256 expirationTime)
        public
        pure
        returns (uint256)
    {
        UD60x18 timeDelta = ud(expirationTime) - ud(currentTime);

        UD60x18 maxBorrow = ud(totalAmount).log2()
            - (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(DECIMALS_MULTIPLIER) + ud(PROTOCOL_YIELD)).log2();

        return maxBorrow.exp2().intoUint256();
    }
}
