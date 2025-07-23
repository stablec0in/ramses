// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface INonfungiblePositionManager {
    function positions(uint256 tokenId)
        external
        view
        returns (
            address token0,
            address token1,
            int24 tickSpacing,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external returns (uint256, uint256);
    function collect(CollectParams calldata params) external returns (uint256, uint256);
    function mint(MintParams calldata params) external returns (uint256 tokenId, uint128 liquidity, uint256, uint256);
    function burn(uint256 tokenId) external;
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tickSpacing() external view returns (int24);
}

contract Manager is Ownable {
    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Pool public immutable pool;
    address public immutable token0;
    address public immutable token1;
    int24 public immutable tickSpacing;

    address public bot;
    address public router;

    uint256 public currentTokenId;
    int24 public currentTickLower;
    int24 public currentTickUpper;
    uint128 public currentLiquidity;

    event Initialized(uint256 tokenId, int24 tickLower, int24 tickUpper, uint128 liquidity);
    event Rebalanced(uint256 oldTokenId, uint256 newTokenId);
    event BotSet(address newBot);

    modifier onlyBot() {
        require(msg.sender == bot, "only bot");
        _;
    }

    constructor(
        address _pool,
        address _positionManager,
        address _router,
        address _initialOwner
    ) Ownable(_initialOwner) {
        pool = IUniswapV3Pool(_pool);
        positionManager = INonfungiblePositionManager(_positionManager);
        router = _router;

        token0 = pool.token0();
        token1 = pool.token1();
        tickSpacing = pool.tickSpacing();
    }

    function setBot(address _bot) external onlyOwner {
        bot = _bot;
        emit BotSet(_bot);
    }

    function initialize(uint256 tokenId) external onlyOwner {
        (
            , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , 
        ) = positionManager.positions(tokenId);

        currentTokenId = tokenId;
        currentTickLower = tickLower;
        currentTickUpper = tickUpper;
        currentLiquidity = liquidity;

        emit Initialized(tokenId, tickLower, tickUpper, liquidity);
    }

    function getNftData() external view returns (uint256, int24, int24, uint128) {
        return (currentTokenId, currentTickLower, currentTickUpper, currentLiquidity);
    }

    function rebalance(
        uint256 tokenId,
        int24 newTickLower,
        int24 newTickUpper,
        address swapAsset,
        uint256 swapAmount,
        bytes calldata swapCallData,
        bool shouldBurnOld
    ) external onlyBot {
        require(IERC721(address(positionManager)).ownerOf(tokenId) == owner(), "Not NFT owner");

        IERC721(address(positionManager)).safeTransferFrom(owner(), address(this), tokenId);

        _withdrawAndMaybeBurn(tokenId, shouldBurnOld);

        if (swapAmount > 0) {
            _swap(swapAsset, swapAmount, swapCallData);
        }

        _mintNewPosition(newTickLower, newTickUpper);

        emit Rebalanced(tokenId, currentTokenId);
    }

    function _withdrawAndMaybeBurn(uint256 tokenId, bool shouldBurn) internal {
        (
            , , , , , uint128 liquidity, , , , 
        ) = positionManager.positions(tokenId);

        INonfungiblePositionManager.DecreaseLiquidityParams memory dParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        positionManager.decreaseLiquidity(dParams);

        INonfungiblePositionManager.CollectParams memory cParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        positionManager.collect(cParams);

        if (shouldBurn) {
            positionManager.burn(tokenId);
        }
    }

    function _swap(address asset, uint256 amount, bytes memory data) internal {
        require(amount > 0, "amount must be > 0");

        IERC20(asset).approve(router, 0);
        IERC20(asset).approve(router, amount);

        (bool success, ) = router.call(data);
        require(success, "swap failed");
    }

    function _mintNewPosition(int24 tickLower, int24 tickUpper) internal {
        uint256 amount0 = IERC20(token0).balanceOf(address(this));
        uint256 amount1 = IERC20(token1).balanceOf(address(this));

        IERC20(token0).approve(address(positionManager), 0);
        IERC20(token1).approve(address(positionManager), 0);
        IERC20(token0).approve(address(positionManager), amount0);
        IERC20(token1).approve(address(positionManager), amount1);

        INonfungiblePositionManager.MintParams memory mParams = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            tickSpacing: tickSpacing,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner(),
            deadline: block.timestamp
        });

        (uint256 newTokenId, uint128 liquidity, , ) = positionManager.mint(mParams);

        currentTokenId = newTokenId;
        currentTickLower = tickLower;
        currentTickUpper = tickUpper;
        currentLiquidity = liquidity;

        // Return leftovers
        uint256 remaining0 = IERC20(token0).balanceOf(address(this));
        uint256 remaining1 = IERC20(token1).balanceOf(address(this));
        if (remaining0 > 0) IERC20(token0).transfer(owner(), remaining0);
        if (remaining1 > 0) IERC20(token1).transfer(owner(), remaining1);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function rescue(address target, uint256 value, bytes calldata data) external onlyOwner returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "Call failed");
        return result;
    }
}
