// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract DAOSwap {
  IUniswapV2Factory private immutable UniswapV2Fatory;
  IUniswapV2Router02 private immutable UniswapRouter;
  //UNISWAP Router
  address private constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
  //Uniswap Factory
  address private constant FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
  address private immutable WETH;

  event CreatedLiquidityPair(address token0, address token1);
  event SwapComplete(address token0, address token1, address indexed user,bool usedWETH);

  constructor() {
    UniswapV2Fatory = IUniswapV2Factory(FACTORY);
    UniswapRouter =  IUniswapV2Router02(ROUTER);
    WETH = UniswapRouter.WETH();
  }

  function getTotalLiquidity(address _token0, address _token1) internal returns (uint){
    //get LP pair, address(0) returned if it does not exist
    address pair = UniswapV2Fatory.getPair(_token0, _token1);
    if(pair != address(0)){
      IUniswapV2Pair UniswapPair = IUniswapV2Pair(pair);
      //get reserves if existing pairs
      (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = UniswapPair.getReserves();
      //return amount of token1(ie token to swap to) to ensure it meets min out req. 
      return _token1 == UniswapPair.token1() ? reserve1 : reserve0;
    }
    else{
      //create Pair if not existing
      UniswapV2Fatory.createPair(_token0, _token1);
      emit CreatedLiquidityPair(_token0, _token1);
      //No Liquidity upon creation so return 0
      return 0;
    }
  }

  function swapUserToken(address tokenA,
                         address tokenB,
                         uint amountA, uint amountBOutMin, bool secondaryRouting) public {
    //check  liquidity to ensure there is enough to fullfill min Out request
    //returns 0 if there is not LP for token combo as well, creates
    uint totalABLiq = getTotalLiquidity(tokenA, tokenB);

    bool useWETH = false;
    if(!secondaryRouting){
      //Check for LP pair + correct output reserves
      require(totalABLiq > amountBOutMin, "Not enough Liquidity/Pair available");
    }
    else if(totalABLiq == 0){
      //If secondaryRoute allowed
      //Check for liquidity of full path A -> WETH, WETH->B
      require(getTotalLiquidity(tokenA, WETH) > 0
             && getTotalLiquidity(WETH, tokenB) > amountBOutMin, "No secondary Liquidity available");
      useWETH = true;
    }
    //get User tokens for transfer to Uniswap 
    IERC20 tokA = IERC20(tokenA);
    require(tokA.transferFrom(msg.sender, address(this), amountA), "User does not have suffiecient balance or allowance");
    //Approve router to move funds
    require(tokA.approve(ROUTER, amountA), "Approval Failed");
    //create Uniswap path from A -> B if Liq, otherwise A -> WETH -> B
    address[] memory path;
    if (!useWETH){
      path = new address[](2);
      path[0] = tokenA;
      path[1] = tokenB;
    }
    else{
      path = new address[](3);
      path[0] = tokenA;
      path[1] = WETH;
      path[2] = tokenB;
    }
    //execute swap, send output directly to user(msg.sender), no custody of tokens 
    UniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                                          amountA,
                                          amountBOutMin,
                                          path,
                                          msg.sender,
                                          block.timestamp);

    
    emit SwapComplete(tokenA, tokenA, msg.sender, useWETH);
  }
}
