pragma solidity ^0.6.0;

import "./BaseVault.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Router01.sol";


contract SolarVault is BaseVault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public lpToken;
    address public token0;
    address public token1;
    uint256 public solarMasterChefPid;

    address[] public path0;
    address[] public path1;

    address public constant solarToken = 0x6bD193Ee6D2104F14F94E2cA6efefae561A4334B;
    address public constant solarMasterChef = 0xf03b75831397D4695a6b9dDdEEA0E578faa30907;
    address public constant solarRouter = 0xAA30eF758139ae4a7f798112902Bf6d65612045f;
    
    address public feeReceiver;
    uint256 public feeRate = 0;

    uint256 public freePeriod = 0;
    uint256 public exitFeeRate = 0;

    constructor(
        address _lpToken,
        string memory _name,
        string memory _symbol,
        address[] memory _path0,
        address[] memory _path1,
        uint256 _solarChefPid,
        address _feeReceiver
    ) 
        public 
        BaseVault(
            _name,
            _symbol,
            _lpToken
        )
    {
        lpToken = _lpToken;
        solarMasterChefPid = _solarChefPid;
        feeReceiver = _feeReceiver;
        token0 = IUniswapV2Pair(lpToken).token0();
        token1 = IUniswapV2Pair(lpToken).token1();
        path0 = _path0;
        path1 = _path1;
        IERC20(lpToken).approve(solarMasterChef, uint256(-1));
        IERC20(solarToken).approve(solarRouter, uint256(-1));
        IERC20(token0).approve(solarRouter, uint256(-1));
        IERC20(token1).approve(solarRouter, uint256(-1));
    }

    function _harvest() internal override {
        (uint256 stakeAmount, ) = ISolarMasterChef(solarMasterChef).userInfo(solarMasterChefPid, address(this));
        if (stakeAmount > 0) {
            ISolarMasterChef(solarMasterChef).withdraw(solarMasterChefPid, 0);
        }

        uint256 solarAmount = IERC20(solarToken).balanceOf(address(this));
        if (solarAmount > 0) {
            IERC20(solarToken).safeTransfer(feeReceiver, solarAmount.mul(feeRate).div(100));
            solarAmount = IERC20(solarToken).balanceOf(address(this));

            if (path0.length > 0) {
                IUniswapV2Router01(solarRouter).swapExactTokensForTokens(solarAmount.div(2), 1, path0, address(this), block.timestamp);
            }
            if (path1.length > 0) {
                IUniswapV2Router01(solarRouter).swapExactTokensForTokens(solarAmount.div(2), 1, path1, address(this), block.timestamp);
            }
            IUniswapV2Router01(solarRouter).addLiquidity(token0, token1, 
                IERC20(token0).balanceOf(address(this)), 
                IERC20(token1).balanceOf(address(this)), 
                1, 1, address(this), block.timestamp);
        }
    }

    function _invest() internal override {
        uint256 lpAmount = IERC20(lpToken).balanceOf(address(this));
        if (lpAmount > 0) {
            ISolarMasterChef(solarMasterChef).deposit(solarMasterChefPid, lpAmount);
        }

    }

    function _exit() internal override {
        ISolarMasterChef(solarMasterChef).emergencyWithdraw(solarMasterChefPid);
    }

    function _exitSome(uint256 _amount) internal override {
        ISolarMasterChef(solarMasterChef).withdraw(solarMasterChefPid, _amount);
    }

    function _withdrawFee(uint256 _withdrawAmount, uint256 _lastDepositTime) internal override returns (uint256) {
        if (_lastDepositTime.add(freePeriod) <= block.timestamp) {
            return 0;
        }
        uint256 feeAmount = _withdrawAmount.mul(exitFeeRate).div(1000);
        IERC20(lpToken).safeTransfer(feeReceiver, feeAmount);
        return feeAmount;
    }

    function _totalTokenBalance() internal view override returns (uint256) {
        (uint256 stakeAmount, ) = ISolarMasterChef(solarMasterChef).userInfo(solarMasterChefPid, address(this));
        return IERC20(lpToken).balanceOf(address(this)).add(stakeAmount);
    }

    function setPath(address[] calldata _path0, address[] calldata _path1) public onlyOwner {
        path0 = _path0;
        path1 = _path1;
    }

    function setFeeReceiver(address _addr) public onlyOwner {
        feeReceiver = _addr;
    }

    function setFeeRate(uint256 _rate) public onlyOwner {
        require(_rate <= 50, "invalid rate");
        feeRate = _rate;
    }

    function setExitFeeRate(uint256 _rate) public onlyOwner {
        require(_rate <= 10, "invalid");
        exitFeeRate = _rate;
    }

    function setFreePeriod(uint256 _period) public onlyOwner {
        require(_period <= 30 days, "invalid period");
        freePeriod = _period;
    }
    
}


interface ISolarMasterChef {
    function userInfo(uint256 pid, address user) external view returns (uint256, uint256); 
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
}