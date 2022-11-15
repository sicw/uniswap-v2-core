pragma solidity ^0.5.11;
import './ERC20.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapETHFactory.sol';
import './interfaces/IUniswapETH.sol';


contract UniswapETH is ERC20 {

  event TokenPurchase(address indexed buyer, uint256 indexed ethSold, uint256 indexed tokensBought);
  event EthPurchase(address indexed buyer, uint256 indexed tokensSold, uint256 indexed ethBought);
  event AddLiquidity(address indexed provider, uint256 indexed ethAmount, uint256 indexed tokenAmount);
  event RemoveLiquidity(address indexed provider, uint256 indexed ethAmount, uint256 indexed tokenAmount);

  string public name;                   // Uniswap V2
  string public symbol;                 // UNI-V2
  uint256 public decimals;              // 18
  IERC20 token;                         // ERC20 token traded on this contract
  IUniswapFactory factory;              // factory that created this contract

  bool private rentrancyLock = false;

  modifier nonReentrant() {
    require(!rentrancyLock);
    rentrancyLock = true;
    _;
    rentrancyLock = false;
  }


  constructor(address tokenAddr) public {
    require(address(tokenAddr) != address(0), 'INVALID_ADDRESS');
    factory = IUniswapFactory(msg.sender);
    token = IERC20(tokenAddr);
    name = 'Uniswap V2';
    symbol = 'UNI-V2';
    decimals = 18;
  }


  function () external payable {
    ethToTokenInput(msg.value, 1, block.timestamp, msg.sender, msg.sender);
  }

  // 同UniswapERC20中的计算公式
  function getInputPrice(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) public pure returns (uint256) {
    require(inputReserve > 0 && outputReserve > 0, 'INVALID_VALUE');
    uint256 inputAmountWithFee = inputAmount.mul(997);
    uint256 numerator = inputAmountWithFee.mul(outputReserve);
    uint256 denominator = inputReserve.mul(1000).add(inputAmountWithFee);
    return numerator / denominator;
  }


  function getOutputPrice(uint256 outputAmount, uint256 inputReserve, uint256 outputReserve) public pure returns (uint256) {
    require(inputReserve > 0 && outputReserve > 0);
    uint256 numerator = inputReserve.mul(outputAmount).mul(1000);
    uint256 denominator = (outputReserve.sub(outputAmount)).mul(997);
    return (numerator / denominator).add(1);
  }

  /*
    下面的function就是几种操作
    1. eth做为输入, token做为输出
         eth
        token
      1.1 用1eth兑换多少token
      1.2 我想兑换出100个token, 需要多少eth

    2. token做为输入, eth做为输出
        token
         eth
      2.1 用100token兑换多少eth
      2.2 我想兑换出1个eth, 需要多少token
  */

  /*
    我用xxx个eth 买token
  */
  // eth做为输入 用1eth兑换token
  function ethToTokenInput(uint256 ethSold, uint256 minTokens, uint256 deadline, address buyer, address recipient) private nonReentrant returns (uint256) {
    require(deadline >= block.timestamp && ethSold > 0 && minTokens > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 tokensBought = getInputPrice(ethSold, address(this).balance.sub(ethSold), tokenReserve);
    require(tokensBought >= minTokens);
    // 给msg.sender转token
    require(token.transfer(recipient, tokensBought));
    emit TokenPurchase(buyer, ethSold, tokensBought);
    return tokensBought;
  }

  // eth兑换token payable修饰先支付eth
  function ethToTokenSwapInput(uint256 minTokens, uint256 deadline) public payable returns (uint256) {
    return ethToTokenInput(msg.value, minTokens, deadline, msg.sender, msg.sender);
  }

  // eth兑换token token发送给recipient
  function ethToTokenTransferInput(uint256 minTokens, uint256 deadline, address recipient) public payable returns(uint256) {
    require(recipient != address(this) && recipient != address(0));
    return ethToTokenInput(msg.value, minTokens, deadline, msg.sender, recipient);
  }

  // eth做为输入 我想买100个token需要多少eth
  function ethToTokenOutput(uint256 tokensBought, uint256 maxEth, uint256 deadline, address payable buyer, address recipient) private nonReentrant returns (uint256) {
    require(deadline >= block.timestamp && tokensBought > 0 && maxEth > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 ethSold = getOutputPrice(tokensBought, address(this).balance.sub(maxEth), tokenReserve);
    // Throws if ethSold > maxEth
    uint256 ethRefund = maxEth.sub(ethSold);
    if (ethRefund > 0) {
      // 找零操作
      buyer.transfer(ethRefund);
    }
    // 发送token给recipient
    require(token.transfer(recipient, tokensBought));
    emit TokenPurchase(buyer, ethSold, tokensBought);
    return ethSold;
  }

  // 要买xxx个token, 先把最大花费max eth传进来, 有剩余的话再返回去
  function ethToTokenSwapOutput(uint256 tokensBought, uint256 deadline) public payable returns(uint256) {
    return ethToTokenOutput(tokensBought, msg.value, deadline, msg.sender, msg.sender);
  }

  // 同上, token发送给recipient
  function ethToTokenTransferOutput(uint256 tokensBought, uint256 deadline, address recipient) public payable returns (uint256) {
    require(recipient != address(this) && recipient != address(0));
    return ethToTokenOutput(tokensBought, msg.value, deadline, msg.sender, recipient);
  }


  // token做为输入 用100个token兑换eth
  function tokenToEthInput(uint256 tokensSold, uint256 minEth, uint256 deadline, address buyer, address payable recipient) private nonReentrant returns (uint256) {
    require(deadline >= block.timestamp && tokensSold > 0 && minEth > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 ethBought = getInputPrice(tokensSold, tokenReserve, address(this).balance);
    require(ethBought >= minEth);
    // 发送eth
    recipient.transfer(ethBought);
    // 转移token 给address(this)
    require(token.transferFrom(buyer, address(this), tokensSold));
    emit EthPurchase(buyer, tokensSold, ethBought);
    return ethBought;
  }


  function tokenToEthSwapInput(uint256 tokensSold, uint256 minEth, uint256 deadline) public returns (uint256) {
    return tokenToEthInput(tokensSold, minEth, deadline, msg.sender, msg.sender);
  }


  function tokenToEthTransferInput(uint256 tokensSold, uint256 minEth, uint256 deadline, address payable recipient) public returns (uint256) {
    require(recipient != address(this) && recipient != address(0));
    return tokenToEthInput(tokensSold, minEth, deadline, msg.sender, recipient);
  }

  // token做为输入 想要1个eth 需要多少token
  function tokenToEthOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline, address buyer, address payable recipient) private nonReentrant returns (uint256) {
    require(deadline >= block.timestamp && ethBought > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 tokensSold = getOutputPrice(ethBought, tokenReserve, address(this).balance);
    // tokens sold is always > 0
    require(maxTokens >= tokensSold);
    // 发送eth
    recipient.transfer(ethBought);
    // 将token转移到address(this)
    require(token.transferFrom(buyer, address(this), tokensSold));
    emit EthPurchase(buyer, tokensSold, ethBought);
    return tokensSold;
  }


  function tokenToEthSwapOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline) public returns (uint256) {
    return tokenToEthOutput(ethBought, maxTokens, deadline, msg.sender, msg.sender);
  }


  function tokenToEthTransferOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline, address payable recipient) public returns (uint256) {
    require(recipient != address(this) && recipient != address(0));
    return tokenToEthOutput(ethBought, maxTokens, deadline, msg.sender, recipient);
  }

  // token -> eth -> token
  function tokenToTokenInput(
    uint256 tokensSold,
    uint256 minTokensBought,
    uint256 minEthBought,
    uint256 deadline,
    address buyer,
    address recipient,
    address payable exchangeAddr)
    private nonReentrant returns (uint256)
  {
    require(deadline >= block.timestamp && tokensSold > 0 && minTokensBought > 0 && minEthBought > 0);
    require(exchangeAddr != address(this) && exchangeAddr != address(0));
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 ethBought = getInputPrice(tokensSold, tokenReserve, address(this).balance);
    require(ethBought >= minEthBought);
    require(token.transferFrom(buyer, address(this), tokensSold));
    uint256 tokensBought = IUniswapExchange(exchangeAddr).ethToTokenTransferInput.value(ethBought)(minTokensBought, deadline, recipient);
    emit EthPurchase(buyer, tokensSold, ethBought);
    return tokensBought;
  }


  function tokenToTokenSwapInput(
    uint256 tokensSold,
    uint256 minTokensBought,
    uint256 minEthBought,
    uint256 deadline,
    address tokenAddr)
    public returns (uint256)
  {
    address payable exchangeAddr = factory.getExchange(tokenAddr);
    return tokenToTokenInput(tokensSold, minTokensBought, minEthBought, deadline, msg.sender, msg.sender, exchangeAddr);
  }


  function tokenToTokenTransferInput(
    uint256 tokensSold,
    uint256 minTokensBought,
    uint256 minEthBought,
    uint256 deadline,
    address recipient,
    address tokenAddr)
    public returns (uint256)
  {
    address payable exchangeAddr = factory.getExchange(tokenAddr);
    return tokenToTokenInput(tokensSold, minTokensBought, minEthBought, deadline, msg.sender, recipient, exchangeAddr);
  }

  function tokenToTokenOutput(
    uint256 tokensBought,
    uint256 maxTokensSold,
    uint256 maxEthSold,
    uint256 deadline,
    address buyer,
    address recipient,
    address payable exchangeAddr)
    private nonReentrant returns (uint256)
  {
    require(deadline >= block.timestamp && (tokensBought > 0 && maxEthSold > 0));
    require(exchangeAddr != address(this) && exchangeAddr != address(0));
    uint256 ethBought = IUniswapExchange(exchangeAddr).getEthToTokenOutputPrice(tokensBought);
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 tokensSold = getOutputPrice(ethBought, tokenReserve, address(this).balance);
    // tokens sold is always > 0
    require(maxTokensSold >= tokensSold && maxEthSold >= ethBought);
    require(token.transferFrom(buyer, address(this), tokensSold));
    IUniswapExchange(exchangeAddr).ethToTokenTransferOutput.value(ethBought)(tokensBought, deadline, recipient);
    emit EthPurchase(buyer, tokensSold, ethBought);
    return tokensSold;
  }


  function tokenToTokenSwapOutput(
    uint256 tokensBought,
    uint256 maxTokensSold,
    uint256 maxEthSold,
    uint256 deadline,
    address tokenAddr)
    public returns (uint256)
  {
    address payable exchangeAddr = factory.getExchange(tokenAddr);
    return tokenToTokenOutput(tokensBought, maxTokensSold, maxEthSold, deadline, msg.sender, msg.sender, exchangeAddr);
  }


  function tokenToTokenTransferOutput(
    uint256 tokensBought,
    uint256 maxTokensSold,
    uint256 maxEthSold,
    uint256 deadline,
    address recipient,
    address tokenAddr)
    public returns (uint256)
  {
    address payable exchangeAddr = factory.getExchange(tokenAddr);
    return tokenToTokenOutput(tokensBought, maxTokensSold, maxEthSold, deadline, msg.sender, recipient, exchangeAddr);
  }


  function getEthToTokenInputPrice(uint256 ethSold) public view returns (uint256) {
    require(ethSold > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    return getInputPrice(ethSold, address(this).balance, tokenReserve);
  }


  function getEthToTokenOutputPrice(uint256 tokensBought) public view returns (uint256) {
    require(tokensBought > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 ethSold = getOutputPrice(tokensBought, address(this).balance, tokenReserve);
    return ethSold;
  }


  function getTokenToEthInputPrice(uint256 tokensSold) public view returns (uint256) {
    require(tokensSold > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 ethBought = getInputPrice(tokensSold, tokenReserve, address(this).balance);
    return ethBought;
  }


  function getTokenToEthOutputPrice(uint256 ethBought) public view returns (uint256) {
    require(ethBought > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    return getOutputPrice(ethBought, tokenReserve, address(this).balance);
  }


  function tokenAddress() public view returns (address) {
    return address(token);
  }


  function factoryAddress() public view returns (address) {
    return address(factory);
  }

  /*
    1. 初次添加流动性: 向address(this)发送eth和token
    2. 非初次添加流动性: 以eth为主 等比计算token amount
    3. 校验操作
    4. 给msg.sender铸造lp token
  */
  // payable修饰的, 在调用时需要传入eth
  function addLiquidity(uint256 minLiquidity, uint256 maxTokens, uint256 deadline) public payable nonReentrant returns (uint256) {
    require(deadline >= block.timestamp && maxTokens > 0 && msg.value > 0, 'INVALID_INPUT');
    uint256 totalLiquidity = totalSupply;

    if (totalLiquidity > 0) {
      require(minLiquidity > 0);
      // payable修饰的, 执行到这儿时balance已经增加了, 所以这里要减掉 后面好计算tokenAmount
      uint256 ethReserve = address(this).balance.sub(msg.value);
      uint256 tokenReserve = token.balanceOf(address(this));
      // 以eth为为主进行等比计算tokenAmount
      uint256 tokenAmount = (msg.value.mul(tokenReserve) / ethReserve).add(1);
      // 以eth为为主进行等比计算liquidity amount
      uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;
      require(maxTokens >= tokenAmount && liquidityMinted >= minLiquidity);
      balanceOf[msg.sender] = balanceOf[msg.sender].add(liquidityMinted);
      totalSupply = totalLiquidity.add(liquidityMinted);
      require(token.transferFrom(msg.sender, address(this), tokenAmount));
      emit AddLiquidity(msg.sender, msg.value, tokenAmount);
      emit Transfer(address(0), msg.sender, liquidityMinted);
      return liquidityMinted;

    } else {
      // 输入eth最低1000000000 wei
      require(msg.value >= 1000000000, 'INVALID_VALUE');
      require(factory.getExchange(address(token)) == address(this));
      uint256 tokenAmount = maxTokens;
      // 输入的eth数量
      uint256 initialLiquidity = address(this).balance;
      totalSupply = initialLiquidity;
      balanceOf[msg.sender] = initialLiquidity;
      require(token.transferFrom(msg.sender, address(this), tokenAmount));
      emit AddLiquidity(msg.sender, msg.value, tokenAmount);
      emit Transfer(address(0), msg.sender, initialLiquidity);
      return initialLiquidity;
    }
  }

  /*
    1. 根据参数中的liquidity amount等比计算 ethAmount、tokenAmount
    2. 数量校验
    3. 减少流动性
    4. 调用transfer给msg.sender发送eth和token
  */
  function removeLiquidity(uint256 amount, uint256 minEth, uint256 minTokens, uint256 deadline) public nonReentrant returns (uint256, uint256) {
    require(amount > 0 && deadline >= block.timestamp && minEth > 0 && minTokens > 0);
    uint256 totalLiquidity = totalSupply;
    require(totalLiquidity > 0);
    uint256 tokenReserve = token.balanceOf(address(this));
    uint256 ethAmount = amount.mul(address(this).balance) / totalLiquidity;
    uint256 tokenAmount = amount.mul(tokenReserve) / totalLiquidity;
    require(ethAmount >= minEth && tokenAmount >= minTokens);
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
    totalSupply = totalLiquidity.sub(amount);
    // 转移eht
    msg.sender.transfer(ethAmount);
    // 转移token
    require(token.transfer(msg.sender, tokenAmount));
    emit RemoveLiquidity(msg.sender, ethAmount, tokenAmount);
    emit Transfer(msg.sender, address(0), amount);
    return (ethAmount, tokenAmount);
  }
}
