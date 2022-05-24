// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "../../interfaces/IPGauge.sol";
import "../../interfaces/IPMarket.sol";
import "../../interfaces/IPGaugeController.sol";
import "../../interfaces/IPVeToken.sol";
import "../../SuperComposableYield/ISuperComposableYield.sol";
import "../../SuperComposableYield/implementations/RewardManager.sol";
import "../../libraries/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev this contract will have the rewardTokens property a little different from its original meaning
 * The first N-1 reward tokens will be market's scy reward tokens
 * The N-th reward token will be pendle, but represented by address(0)
 * This design aims to avoid the case when pendle is actually one of the rewardTokens in SCY
 */
contract PendleGauge is IPGauge, RewardManager {
    using Math for uint256;
    using SafeERC20 for IERC20;

    struct UserBalance {
        uint256 lpBalance;
        uint256 activeBalance;
    }

    uint256 public constant TOKENLESS_PRODUCTION = 40;

    address public immutable SCY;
    address public immutable market;
    address public immutable pendle;
    IPVeToken public immutable vePendle;
    address public immutable gaugeController;

    uint256 public totalLp;
    uint256 public totalActiveLp;
    mapping(address => UserBalance) public balance;

    constructor(
        address _market,
        address _gaugeController,
        address _vePendle
    ) {
        market = _market;
        gaugeController = _gaugeController;
        pendle = IPGaugeController(gaugeController).pendle();
        vePendle = IPVeToken(_vePendle);
        SCY = IPMarket(market).SCY();
    }

    function stake(address receiver) external {
        _updateUserReward(receiver);
        uint256 amount = _afterReceiveLp();
        require(amount > 0, "zero amount");
        balance[receiver].lpBalance += amount;
        _updateUserActiveBalance(receiver);
    }

    function withdraw(address receiver, uint256 amount) external {
        require(amount > 0, "zero amount");
        address user = msg.sender;
        _updateUserReward(user);
        balance[user].lpBalance -= amount;
        _updateUserActiveBalance(user);
        _transferOutLp(receiver, amount);
    }

    /**
     * @dev It is intended to have msg.sender active balance updated when they try to redeem
     */
    function redeemReward(address receiver) external returns (uint256[] memory) {
        address user = msg.sender;
        _updateUserReward(user);
        _updateUserActiveBalance(user);
        return _doTransferOutRewardsForUser(user, receiver);
    }

    /**
     * @dev Complex logic in this function to saves 2x (1-2) storage read every call
     * @dev this only saves gas in case SCYRewards is immutable
     */
    function getRewardTokens()
        public
        view
        virtual
        override
        returns (address[] memory rewardTokens)
    {
        address[] memory SCYRewards = ISuperComposableYield(SCY).getRewardTokens();
        rewardTokens = new address[](SCYRewards.length + 1);
        rewardTokens[SCYRewards.length] = pendle;
        for (uint256 i = 0; i < SCYRewards.length; ++i) {
            rewardTokens[i] = SCYRewards[i];
        }
    }

    /**
     * @dev since rewardShares will be modified after this function, it should update user reward beforehand
     */
    function _updateUserActiveBalance(address user) internal {
        uint256 lpBalance = balance[user].lpBalance;
        uint256 vePendleBalance = vePendle.balanceOf(user);
        uint256 vePendleSupply = vePendle.updateAndGetTotalSupply();

        // Inspired by Curve's Gauge
        uint256 newActiveBalance = (lpBalance * TOKENLESS_PRODUCTION) / 100;
        if (vePendleSupply > 0) {
            newActiveBalance +=
                (((totalLp * vePendleBalance) / vePendleSupply) * (100 - TOKENLESS_PRODUCTION)) /
                100;
        }
        newActiveBalance = Math.min(newActiveBalance, lpBalance);

        totalActiveLp = totalActiveLp - balance[user].activeBalance + newActiveBalance;
        balance[user].activeBalance = newActiveBalance;
    }

    function _redeemExternalReward() internal virtual override {
        IPMarket(market).redeemScyReward();
        IPGaugeController(gaugeController).redeemLpStakerReward();
    }

    function _rewardSharesTotal() internal virtual override returns (uint256) {
        return totalActiveLp;
    }

    function _rewardSharesUser(address user) internal virtual override returns (uint256) {
        return balance[user].activeBalance;
    }

    function _afterReceiveLp() internal returns (uint256 amount) {
        uint256 newTotalLp = IERC20(market).balanceOf(address(this));
        amount = newTotalLp - totalLp;
        totalLp = newTotalLp;
    }

    function _transferOutLp(address to, uint256 amount) internal {
        IERC20(market).safeTransfer(to, amount);
        totalLp -= amount;
    }
}
