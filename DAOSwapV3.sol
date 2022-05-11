// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract DAOSwap {
  IUniswapV3Factory private immutable UniswapV3Fatory;
  ISwapRouter private immutable UniswapRouter;

  //UNISWAP Router
  address private constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  //Uniswap Factory
  address private constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  //WETH address
  address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  uint24 private constant baseFee = 3000;

  event CreatedLiquidityPair(address token0, address token1);
  event SwapComplete(address token0, address token1, address indexed user, uint amount1Out, bool usedWETH);

  constructor() {
      UniswapV3Fatory = IUniswapV3Factory(FACTORY);
      UniswapRouter =  ISwapRouter(ROUTER);
  }

  function getTotalLiquidity(address _token0, address _token1) internal returns (uint){
    //get LP, address(0) returned if it does not exist
    address pair = UniswapV3Fatory.getPool(_token0, _token1, baseFee);
    if(pair != address(0)){
      IUniswapV3Pool UniswapPool = IUniswapV3Pool(pair);
      //get reserves if existing pairs
      //return amount of token1(ie token to swap to) to ensure it meets min out req. 
      return UniswapPool.token0() == _token0 ? IERC20(_token1).balanceOf(pair) 
                                                        : IERC20(_token0).balanceOf(pair); 
    }
    else{
      //create Pool if not existing
      UniswapV3Fatory.createPool(_token0, _token1, baseFee);
      emit CreatedLiquidityPair(_token0, _token1);
      //No Liquidity upon creation so return 0
      return 0;
    }
  }

  function swapUserToken(address tokenA,
                         address tokenB,
                         uint amountA, uint amountBOutMin, bool secondaryRouting) public returns(uint){
    //check  liquidity to ensure there is enough to fullfill min Out request
    //returns 0 if there is not LP for token combo as well, creates
    uint totalABLiq = getTotalLiquidity(tokenA, tokenB);

    bool useWETH = false;
    if(!secondaryRouting){
      require(totalABLiq > amountBOutMin, "Not enough Liquidity/Pair available");
    }
    else if(totalABLiq == 0){
      require(getTotalLiquidity(tokenA, WETH) > 0
             && getTotalLiquidity(WETH, tokenB) > amountBOutMin, "No secondary Liquidity available");
      useWETH = true;
    }
    //Approve User tokens for transfer to Uniswap 
    IERC20 tokA = IERC20(tokenA);
    require(tokA.transferFrom(msg.sender, address(this), amountA), "User does not have suffiecient balance or allowance");
    //Approve router to move funds
    tokA.approve(ROUTER, amountA);
    //create Uniswap path + input params from A -> B if Liq, otherwise A -> WETH -> B
    if (!useWETH){
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenA,
                tokenOut: tokenB,
                fee: baseFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountA,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        return UniswapRouter.exactInputSingle(params);
    }
    else{
        ISwapRouter.ExactOutputParams memory params =
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(tokenA, baseFee, WETH, baseFee, tokenB),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amountBOutMin,
                amountInMaximum: amountA
            });

        // Executes the swap, returning the amountIn actually spent.
        uint amountIn = UniswapRouter.exactOutput(params);

        // If the swap did not require the full amountInMaximum to achieve the exact amountOut then we refund msg.sender and approve the router to spend 0.
        if (amountIn < amountA) {
            tokA.approve(ROUTER, 0);
            tokA.transfer(msg.sender, amountA - amountIn);
        }
        return amountBOutMin;
    }
  }
}