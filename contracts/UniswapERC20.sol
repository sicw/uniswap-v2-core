pragma solidity ^0.5.11;
import './ERC20.sol';
import './interfaces/IERC20.sol';

contract UniswapERC20 is ERC20 {

  event SwapAForB(address indexed buyer, uint256 amountSold, uint256 amountBought);
  event SwapBForA(address indexed buyer, uint256 amountSold, uint256 amountBought);
  event AddLiquidity(address indexed provider, uint256 amountTokenA, uint256 amountTokenB);
  event RemoveLiquidity(address indexed provider, uint256 amountTokenA, uint256 amountTokenB);

  string public name;                   // Uniswap V2
  string public symbol;                 // UNI-V2
  uint256 public decimals;              // 18
  // 按照address大小排序, 小的tokenA, 大的是tokenB
  address public tokenA;                // ERC20 token traded on this contract
  address public tokenB;                // ERC20 token traded on this contract
  address public factoryAddress;        // factory that created this contract

  bool private rentrancyLock = false;

  modifier nonReentrant() {
    require(!rentrancyLock);
    rentrancyLock = true;
    _;
    rentrancyLock = false;
  }


  constructor(address _tokenA, address _tokenB) public {
    require(address(_tokenA) != address(0) && _tokenB != address(0), 'INVALID_ADDRESS');
    factoryAddress = msg.sender;
    tokenA = _tokenA;
    tokenB = _tokenB;
    name = 'Uniswap V2';
    symbol = 'UNI-V2';
    decimals = 18;
  }

  /*
  TO:DO: Find usage for fallback
  function () external {
    pass;
  } */


  function getInputPrice(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) public pure returns (uint256) {
    require(inputReserve > 0 && outputReserve > 0, 'INVALID_VALUE');
    // 扣除千分之三的手续费 inputAmount减少千分之三 然后带入计算outputAmount
    // x*y = (x+x') * (y-y')
    // y' = (1 - x / (x+x'))*y
    // y' = x'*y / (x+x')
    // 原x=10000 y=10000 要兑换1000个x(输入) 能得到多少y(输出)
    // 909.09  = 1000*10000 / (10000+1000) 不算手续费
    // 906.61  = 1000*997*10000 / (10000*1000+1000*997) 算手续费
    // 多收outputToken千分之三手续费 (少转出outputToken)
    uint256 inputAmountWithFee = inputAmount.mul(997);
    uint256 numerator = inputAmountWithFee.mul(outputReserve);
    uint256 denominator = inputReserve.mul(1000).add(inputAmountWithFee);
    // 100.5就是100了
    return numerator / denominator;
  }


  function getOutputPrice(uint256 outputAmount, uint256 inputReserve, uint256 outputReserve) public pure returns (uint256) {
    require(inputReserve > 0 && outputReserve > 0);
    // 多收inputToken千分之三的手续费 (多收取inputToken千分之三) 整体*1000 / 997 最后加一是取整
    // x*y = (x+x') * (y-y')
    // x' = x*(y / (y-y') - 1)
    // x' = x*y' / (y-y') + 1
    // 要兑换1000个y(输出) 需要多少x(输入)
    // 1111.11 = 10000 * 1000 / 10000 - 1000 不算手续费
    // 1115.45 = 10000 * 1000 * 1000 / (10000 - 1000) * 997 + 1 算手续费
    uint256 numerator = inputReserve.mul(outputAmount).mul(1000);
    uint256 denominator = (outputReserve.sub(outputAmount)).mul(997);
    // 向上取整 100.1 也是 101
    return (numerator / denominator).add(1);
  }


  //TO: DO msg.sender is wrapper
  // 给了输入token, 然后交换另一个token
  function swapInput(address inputToken, uint256 amountSold, address recipient) public nonReentrant returns (uint256) {
      address _tokenA = address(tokenA);
      address _tokenB = address(tokenB);
      // 解析inputToken 和 outputToken 因为你也不知道传进来的inputToken是tokenA还是tokenB
      bool inputIsA = inputToken == _tokenA;
      require(inputIsA || inputToken == _tokenB);
      address outputToken = _tokenA;
      if(inputIsA) {
        outputToken == _tokenB;
      }

      // 以当前合约的address做为地址 获取所在token的存量(该交易对里有多少token)
      uint256 inputReserve = IERC20(inputToken).balanceOf(address(this));
      uint256 outputReserve = IERC20(outputToken).balanceOf(address(this));
      // 计算能买多少另一个token
      // transferFrom 第三方合约调用A->B转账时使用
      // 已知x' x y 求y'
      uint256 amountBought = getInputPrice(amountSold, inputReserve, outputReserve);
      // 将输入token转进address(this) 需要msg.sender给当前合约授权
      require(IERC20(inputToken).transferFrom(msg.sender, address(this), amountSold));
      // 输出token的owner就是address(this) 使用transfer就可以了
      // 将输出token 从address(this) 发送到 recipient 可以直接调用transfer
      require(IERC20(outputToken).transfer(recipient, amountBought));

      if(inputIsA) {
        emit SwapAForB(msg.sender, amountSold, amountBought);
      } else {
        emit SwapBForA(msg.sender, amountSold, amountBought);
      }

      return amountBought;
  }


  //TO: DO msg.sender is wrapper
  // 想要兑换出:outputToken 数量:amountBought
  function swapOutput(address outputToken, uint256 amountBought, address recipient) public nonReentrant returns (uint256) {
      address _tokenA = address(tokenA);
      address _tokenB = address(tokenB);
      bool outputIsA = outputToken == _tokenA;
      require(outputIsA || outputToken == _tokenB);
      address inputToken = _tokenA;
      if(outputIsA) {
        inputToken == _tokenB;
      }

      uint256 inputReserve = IERC20(inputToken).balanceOf(address(this));
      uint256 outputReserve = IERC20(outputToken).balanceOf(address(this));
      uint256 amountSold = getOutputPrice(amountBought, inputReserve, outputReserve);
      require(IERC20(inputToken).transferFrom(msg.sender, address(this), amountSold));
      require(IERC20(outputToken).transfer(recipient, amountBought));

      if(outputIsA) {
        emit SwapBForA(msg.sender, amountSold, amountBought);
      } else {
        emit SwapAForB(msg.sender, amountSold, amountBought);
      }

      return amountSold;
  }


  function getInputPrice(address inputToken, uint256 amountSold) public view returns (uint256) {
    require(amountSold > 0);
    address _tokenA = address(tokenA);
    address _tokenB = address(tokenB);
    require(inputToken == _tokenA || inputToken == _tokenB);
    address outputToken = _tokenA;
    if(inputToken == _tokenA) {
      outputToken = _tokenB;
    }
    uint256 inputReserve = IERC20(inputToken).balanceOf(address(this));
    uint256 outputReserve = IERC20(outputToken).balanceOf(address(this));
    return getInputPrice(amountSold, inputReserve, outputReserve);
  }


  function getOutputPrice(address outputToken, uint256 amountBought) public view returns (uint256) {
    require(amountBought > 0);
    address _tokenA = address(tokenA);
    address _tokenB = address(tokenB);
    require(outputToken == _tokenA || outputToken == _tokenB);
    address inputToken = _tokenA;
    if(outputToken == _tokenA) {
      inputToken = _tokenB;
    }
    uint256 inputReserve = IERC20(inputToken).balanceOf(address(this));
    uint256 outputReserve = IERC20(outputToken).balanceOf(address(this));
    return getOutputPrice(amountBought, inputReserve, outputReserve);
  }


  function tokenAAddress() public view returns (address) {
    return address(tokenA);
  }


  function tokenBAddress() public view returns (address) {
    return address(tokenB);
  }


  function addLiquidity(uint256 amountA, uint256 maxTokenB, uint256 minLiquidity) public nonReentrant returns (uint256) {
    require(amountA > 0 && maxTokenB > 0);
    uint256 _totalSupply = totalSupply;
    address _tokenA = tokenA;
    address _tokenB = tokenB;

    if (_totalSupply > 0) {
      // 之前添加过流动性
      require(minLiquidity > 0);

      uint256 reserveA = IERC20(_tokenA).balanceOf(address(this));
      uint256 reserveB = IERC20(_tokenB).balanceOf(address(this));
      // 等比计算投入比例 +1向上取整
      // addx / x = addy / y , addy = addx * y / x
      uint256 amountB = (amountA.mul(reserveB) / reserveA).add(1);
      // lp' / lp total = addx / x = addy / y
      uint256 liquidityMinted = amountA.mul(_totalSupply) / reserveA;
      require(maxTokenB >= amountB && liquidityMinted >= minLiquidity);
      // 添加lp token
      balanceOf[msg.sender] = balanceOf[msg.sender].add(liquidityMinted);
      totalSupply = _totalSupply.add(liquidityMinted);
      // 需要先授权给this
      require(IERC20(_tokenA).transferFrom(msg.sender, address(this), amountA));
      require(IERC20(_tokenB).transferFrom(msg.sender, address(this), amountB));
      emit AddLiquidity(msg.sender, amountA, amountB);
      emit Transfer(address(0), msg.sender, liquidityMinted);
      return liquidityMinted;

    } else {
      // TODO: figure out how to set this safely
      // arithemtic or geometric mean?
      // 初始添加流动性
      uint256 initialLiquidity = amountA;
      totalSupply = initialLiquidity;
      balanceOf[msg.sender] = initialLiquidity;
      require(IERC20(_tokenA).transferFrom(msg.sender, address(this), amountA));
      require(IERC20(_tokenB).transferFrom(msg.sender, address(this), maxTokenB));
      emit AddLiquidity(msg.sender, amountA, maxTokenB);
      emit Transfer(address(0), msg.sender, initialLiquidity);
      return initialLiquidity;
    }
  }

  // amount代表lp token数量
  function removeLiquidity(uint256 amount, uint256 minTokenA, uint256 minTokenB) public nonReentrant returns (uint256, uint256) {
    uint256 _totalSupply = totalSupply;
    require(amount > 0 && minTokenA > 0 && minTokenB > 0 && _totalSupply > 0);
    address _tokenA = tokenA;
    address _tokenB = tokenB;
    uint256 reserveA = IERC20(_tokenA).balanceOf(address(this));
    uint256 reserveB = IERC20(_tokenB).balanceOf(address(this));
    // 等比例计算收益
    uint256 tokenAAmount = amount.mul(reserveA) / _totalSupply;
    uint256 tokenBAmount = amount.mul(reserveB) / _totalSupply;
    require(tokenAAmount >= minTokenA && tokenBAmount >= minTokenB);
    // 减少lp token数量, 只能减少msg.sender的
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
    totalSupply = _totalSupply.sub(amount);
    require(IERC20(_tokenA).transfer(msg.sender, tokenAAmount));
    require(IERC20(_tokenB).transfer(msg.sender, tokenBAmount));
    emit RemoveLiquidity(msg.sender, tokenAAmount, tokenBAmount);
    emit Transfer(msg.sender, address(0), amount);
    return (tokenAAmount, tokenBAmount);
  }
}
