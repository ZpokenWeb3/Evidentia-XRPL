// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IExternalRewardContract {
    function getRewardAmount() external view returns (uint256);
    function getRewards() external returns (uint256);
}

contract StableCoinsStaking {
    IERC20 public stakingToken;
    IExternalRewardContract public externalRewardContract;

    uint256 internal constant YEAR_IN_SECONDS = 31536000; // 365 days
    uint256 public totalStaked; // Total amount of tokens staked
    uint256 public rewardPerTokenStored; // Cumulative rewards per staked token
    uint256 public lastUpdateTime; // The last time the rewards were updated

    struct StakerInfo {
        uint256 stakedAmount; // Amount of tokens staked by the user
        uint256 rewardPaid; // Rewards already paid to the user
        uint256 userRewardPerTokenPaid; // The last reward per token the user has "seen"
        uint256 rewardsEarned; // Rewards earned by the user, unclaimed
        uint256 stakeTimestamp; // The last time the user updated the stake
    }

    mapping(address => StakerInfo) public stakers;

    constructor(address _stakingToken, address _externalRewardContract) {
        stakingToken = IERC20(_stakingToken);
        externalRewardContract = IExternalRewardContract(_externalRewardContract);
    }
}
