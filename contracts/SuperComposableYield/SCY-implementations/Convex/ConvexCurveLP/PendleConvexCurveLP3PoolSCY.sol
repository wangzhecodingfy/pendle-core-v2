// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import "./PendleConvexCurveLPSCY.sol";

contract PendleConvexCurveLP3PoolSCY is PendleConvexCurveLPSCY {
    address public immutable BASEPOOL_TOKEN_1;
    address public immutable BASEPOOL_TOKEN_2;
    address public immutable BASEPOOL_TOKEN_3;
    uint256 public constant BASEPOOL_TOKEN_LENGTH = 3;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _pid,
        address _convexBooster,
        address _wrappedLpToken,
        address _cvx,
        address _baseCrvPool,
        address[] memory _currentExtraRewards,
        address[3] memory _basePoolTokens
    )
        PendleConvexCurveLPSCY(
            _name,
            _symbol,
            _pid,
            _convexBooster,
            _wrappedLpToken,
            _cvx,
            _baseCrvPool,
            _currentExtraRewards
        )
    {
        BASEPOOL_TOKEN_1 = _basePoolTokens[0];
        BASEPOOL_TOKEN_2 = _basePoolTokens[1];
        BASEPOOL_TOKEN_3 = _basePoolTokens[2];
    }

    function getTokensIn() public view override returns (address[] memory res) {
        res = new address[](5);
        res[0] = CRV_LP_TOKEN;
        res[1] = W_CRV_LP_TOKEN;
        res[2] = BASEPOOL_TOKEN_1;
        res[3] = BASEPOOL_TOKEN_2;
        res[4] = BASEPOOL_TOKEN_3;
    }

    function getTokensOut() public view override returns (address[] memory res) {
        res = new address[](5);
        res[0] = CRV_LP_TOKEN;
        res[1] = W_CRV_LP_TOKEN;
        res[2] = BASEPOOL_TOKEN_1;
        res[3] = BASEPOOL_TOKEN_2;
        res[4] = BASEPOOL_TOKEN_3;
    }

    function isValidTokenIn(address token) public view override returns (bool res) {
        res = (token == CRV_LP_TOKEN ||
            token == W_CRV_LP_TOKEN ||
            token == BASEPOOL_TOKEN_1 ||
            token == BASEPOOL_TOKEN_2 ||
            token == BASEPOOL_TOKEN_3);
    }

    function isValidTokenOut(address token) public view override returns (bool res) {
        res = (token == CRV_LP_TOKEN ||
            token == W_CRV_LP_TOKEN ||
            token == BASEPOOL_TOKEN_1 ||
            token == BASEPOOL_TOKEN_2 ||
            token == BASEPOOL_TOKEN_3);
    }

    /**
     * @dev To be overriden by the pool type variation contract and return the respective index based on the registered Index of the Curve Base Token.
     *
     * This function will only be called once the token has been checked that it is one of the Curve Base Pool Tokens.
     */
    function _getIndexOfCrvBaseToken(address crvBaseToken)
        internal
        view
        override
        returns (uint256 index)
    {
        if (crvBaseToken == BASEPOOL_TOKEN_1) {
            index = 0;
        } else if (crvBaseToken == BASEPOOL_TOKEN_2) {
            index = 1;
        } else {
            index = 2;
        }
    }

    function isCrvBaseToken(address token) public view override returns (bool res) {
        return (token == BASEPOOL_TOKEN_1 ||
            token == BASEPOOL_TOKEN_2 ||
            token == BASEPOOL_TOKEN_3);
    }

    function _assignDepositAmountToCrvBaseTokenIndex(address crvBaseToken, uint256 amountDeposited)
        internal
        view
        override
        returns (uint256[] memory res)
    {
        res = new uint256[](BASEPOOL_TOKEN_LENGTH);
        res[_getIndexOfCrvBaseToken(crvBaseToken)] = amountDeposited;
    }
}
