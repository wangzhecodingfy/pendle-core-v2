// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IPLiquidYieldToken.sol";

contract PendleRouter01 {
    using SafeERC20 for IERC20;

    function swapExactBaseTokenForLYT(
        address baseToken,
        uint256 amountBaseToken,
        address LYT,
        uint256 minAmountLYTOut,
        address to,
        bytes calldata data
    ) public returns (uint256 amountLYTOut) {
        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), amountBaseToken);
        amountLYTOut = IPLiquidYieldToken(LYT).mintFromBaseToken(
            to,
            baseToken,
            amountBaseToken,
            minAmountLYTOut,
            data
        );
    }

    function swapExactLYTforBaseToken(
        address LYT,
        uint256 amountLYTIn,
        address baseToken,
        uint256 minBaseTokenOut,
        address to,
        bytes calldata data
    ) public returns (uint256 amountBaseTokenOut) {
        IERC20(LYT).safeTransferFrom(msg.sender, address(this), amountLYTIn);
        amountBaseTokenOut = IPLiquidYieldToken(LYT).burnToBaseToken(
            to,
            baseToken,
            amountLYTIn,
            minBaseTokenOut,
            data
        );
    }
}
