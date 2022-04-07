// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "../misc/PendleJoeSwapHelper.sol";
import "../../SuperComposableYield/ISuperComposableYield.sol";
import "../../interfaces/IPYieldToken.sol";

contract PendleRouterSCYAndForge is PendleJoeSwapHelper {
    using SafeERC20 for IERC20;

    constructor(address _joeRouter, address _joeFactory)
        PendleJoeSwapHelper(_joeRouter, _joeFactory)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    /**
     * @notice swap rawToken to baseToken -> baseToken to mint SCY
     * @param path the path to swap from rawToken to baseToken. path = [baseToken] if no swap is needed
     * @dev inner working of this function:
     - if [rawToken == baseToken], rawToken is transferred to SCY contract
       else, it is transferred to the first pair of path, swap is called, and the output token is transferred
            to SCY contract
     - SCY.mint is called, minting SCY directly to recipient
     */
    function mintSCYFromRawToken(
        uint256 netRawTokenIn,
        address SCY,
        uint256 minSCYOut,
        address recipient,
        address[] calldata path,
        bool doPull
    ) public returns (uint256 netSCYOut) {
        if (doPull) {
            if (path.length == 1) {
                IERC20(path[0]).transferFrom(msg.sender, SCY, netRawTokenIn);
            } else {
                IERC20(path[0]).transferFrom(msg.sender, _getFirstPair(path), netRawTokenIn);
                _swapExactIn(path, netRawTokenIn, SCY);
            }
        }

        address baseToken = path[path.length - 1];
        netSCYOut = ISuperComposableYield(SCY).mint(recipient, baseToken, minSCYOut);
    }

    /**
    * @notice redeem SCY to baseToken -> swap baseToken to rawToken
    * @dev path[0] will be the baseToken that SCY is redeemed to, and path[path.length-1] is the
    final rawToken output
    * @param path the path to swap from rawToken to baseToken. path = [baseToken] if no swap is needed
    * @dev inner working of this function:
     - SCY is transferred to SCY contract
     - if [rawToken == baseToken], SCY.redeem is called & directly redeem tokens to the recipient
       else, SCY.redeem is called with recipient = first pair in the path,
        and swap is called, and the output token is transferred to recipient
     */
    function redeemSCYToRawToken(
        address SCY,
        uint256 netSCYIn,
        uint256 minRawTokenOut,
        address recipient,
        address[] memory path,
        bool doPull
    ) public returns (uint256 netRawTokenOut) {
        if (doPull) {
            IERC20(SCY).safeTransferFrom(msg.sender, SCY, netSCYIn);
        }

        address baseToken = path[0];
        if (path.length == 1) {
            netRawTokenOut = ISuperComposableYield(SCY).redeem(
                recipient,
                baseToken,
                minRawTokenOut
            );
        } else {
            uint256 netBaseTokenOut = ISuperComposableYield(SCY).redeem(
                _getFirstPair(path),
                baseToken,
                1
            );
            netRawTokenOut = _swapExactIn(path, netBaseTokenOut, recipient);
            require(netRawTokenOut >= minRawTokenOut, "insufficient out");
        }
    }

    /**
     * @notice swap rawToken to baseToken -> convert to SCY -> convert to OT + YT
     * @param path the path to swap from rawToken to baseToken. path = [baseToken] if no swap is needed
     * @dev inner working of this function:
     - same as mintSCYFromRawToken, except the recipient of SCY will be the YT contract, then mintYO
     will be called, minting OT + YT directly to recipient
     */
    function mintYoFromRawToken(
        uint256 netRawTokenIn,
        address YT,
        uint256 minYoOut,
        address recipient,
        address[] calldata path,
        bool doPull
    ) public returns (uint256 netYoOut) {
        address SCY = IPYieldToken(YT).SCY();
        mintSCYFromRawToken(netRawTokenIn, SCY, 1, YT, path, doPull);
        netYoOut = IPYieldToken(YT).mintYO(recipient, recipient);
        require(netYoOut >= minYoOut, "insufficient YO out");
    }

    /**
     * @notice redeem OT + YT to SCY -> redeem SCY to baseToken -> swap baseToken to rawToken
     * @param path the path to swap from rawToken to baseToken. path = [baseToken] if no swap is needed
     * @dev inner working of this function:
     - OT (+ YT if not expired) is transferred to the YT contract
     - redeemYO is called, redeem all outcome SCY to the SCY contract
     - The rest is the same as redeemSCYToRawToken (except the first SCY transfer is skipped)
     */
    function redeemYoToRawToken(
        address YT,
        uint256 netYoIn,
        uint256 minRawTokenOut,
        address recipient,
        address[] memory path,
        bool doPull
    ) public returns (uint256 netRawTokenOut) {
        address OT = IPYieldToken(YT).OT();
        address SCY = IPYieldToken(YT).SCY();

        if (doPull) {
            bool isNeedToBurnYt = (IPBaseToken(YT).isExpired() == false);
            IERC20(OT).safeTransferFrom(msg.sender, YT, netYoIn);
            if (isNeedToBurnYt) IERC20(YT).safeTransferFrom(msg.sender, YT, netYoIn);
        }

        IPYieldToken(YT).redeemYO(SCY);

        netRawTokenOut = redeemSCYToRawToken(SCY, 0, minRawTokenOut, recipient, path, false);
    }
}