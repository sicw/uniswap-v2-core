pragma solidity ^0.5.11;
import "./UniswapERC20.sol";

contract UniswapERC20Factory {

  event NewERC20Exchange(address indexed tokenA, address indexed tokenB, address indexed exchange);

  // 存储pair时, 从小到大排序.
  struct Pair {
    address tokenA;
    address tokenB;
  }

  // 交换对的数量
  uint256 public exchangeCount;
  // tokenA + tokenB => exchange
  mapping (address => mapping(address => address)) internal setExchange;
  // exchange => tokenA + tokenB
  mapping (address => Pair) public getPair;
  // exchangeId => exchange
  mapping (uint256 => address) public getExchangeWithId;


  function createExchange(address token1, address token2) public returns (address) {
    require(token1 != address(0) && token2 != address(0) && token1 != token2);
    // todo 这里存在bug, 如果token1/token2交易对已经存在于pairs中, 而传进来的token1和token2没有排序, 会认为没有该交易对
    require(setExchange[token1][token2] == address(0), 'EXCHANGE_EXISTS');

    // 排序 tokenA < tokenB
    address tokenA = token1;
    address tokenB = token2;
    if(uint256(token2) < uint256(token1)) {
      tokenA = token2;
      tokenB = token1;
    }

    // 创建交易对
    UniswapERC20 exchange = new UniswapERC20(tokenA, tokenB);
    // 按顺序添加交易对
    setExchange[tokenA][tokenB] = address(exchange);
    getPair[address(exchange)].tokenA = tokenA;
    getPair[address(exchange)].tokenB = tokenB;

    // 增加交易对数量
    uint256 exchangeId = exchangeCount + 1;
    exchangeCount = exchangeId;
    getExchangeWithId[exchangeId] = address(exchange);

    emit NewERC20Exchange(tokenA, tokenB, address(exchange));
    return address(exchange);
  }
}
