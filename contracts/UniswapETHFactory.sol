pragma solidity ^0.5.11;
import "./UniswapETH.sol";

contract UniswapETHFactory {

  event NewExchange(address indexed token, address indexed exchange);

  uint256 public tokenCount;
  mapping (address => address) public getExchange;
  mapping (address => address) public getToken;
  mapping (uint256 => address) public getTokenWithId;

  // 创建兑换对 token <--> eth 所以这里只有一个token
  function createExchange(address token) public returns (address) {
    require(token != address(0));
    require(getExchange[token] == address(0), 'EXCHANGE_EXISTS');
    UniswapETH exchange = new UniswapETH(token);
    getExchange[token] = address(exchange);
    getToken[address(exchange)] = token;
    uint256 tokenId = tokenCount + 1;
    tokenCount = tokenId;
    getTokenWithId[tokenId] = token;
    emit NewExchange(token, address(exchange));
    return address(exchange);
  }
}
