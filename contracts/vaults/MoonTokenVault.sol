pragma solidity ^0.6.0;

import "./BaseVault.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Router01.sol";


contract MoonTokenVault is BaseVault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public lpToken;
    address public token0;
    address public token1;
    uint256 public moonMasterChefPid;

    address[] public path0;
    address[] public path1;

    address public constant moonToken = 0xB497c3E9D27Ba6b1fea9F1b941d8C79E66cfC9d6;
    address public constant moonMasterChef = 0x78Aa55Ce0b0DC7488d2C38BD92769f4d0C8196Ff;
    address public constant moonRouter = 0x120999312896F36047fBcC44AD197b7347F499d6;
    
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
        uint256 _moonChefPid,
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
        moonMasterChefPid = _moonChefPid;
        feeReceiver = _feeReceiver;
        path0 = _path0;
        path1 = _path1;
        IERC20(lpToken).approve(moonMasterChef, uint256(-1));
        IERC20(moonToken).approve(moonRouter, uint256(-1));
    }

    function _harvest() internal override {
        (uint256 stakeAmount, ) = IMoonMasterChef(moonMasterChef).userInfo(moonMasterChefPid, address(this));
        if (stakeAmount > 0) {
            IMoonMasterChef(moonMasterChef).withdraw(moonMasterChefPid, 0);
        }

        uint256 moonAmount = IERC20(moonToken).balanceOf(address(this));
        if (moonAmount > 0) {
            IERC20(moonToken).safeTransfer(feeReceiver, moonAmount.mul(feeRate).div(100));
            moonAmount = IERC20(moonToken).balanceOf(address(this));

            if (path0.length > 0) {
                IUniswapV2Router01(moonRouter).swapExactTokensForTokens(moonAmount, 1, path0, address(this), block.timestamp);
            }
        }
    }

    function _invest() internal override {
        uint256 lpAmount = IERC20(lpToken).balanceOf(address(this));
        if (lpAmount > 0) {
            IMoonMasterChef(moonMasterChef).deposit(moonMasterChefPid, lpAmount);
        }

    }

    function _exit() internal override {
        IMoonMasterChef(moonMasterChef).emergencyWithdraw(moonMasterChefPid);
    }

    function _exitSome(uint256 _amount) internal override {
        IMoonMasterChef(moonMasterChef).withdraw(moonMasterChefPid, _amount);
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
        (uint256 stakeAmount, ) = IMoonMasterChef(moonMasterChef).userInfo(moonMasterChefPid, address(this));
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
        require(_rate <= 30, "invalid rate");
        feeRate = _rate;
    }

    function setExitFeeRate(uint256 _rate) public onlyOwner {
        require(_rate <= 5, "invalid");
        exitFeeRate = _rate;
    }

    function setFreePeriod(uint256 _period) public onlyOwner {
        require(_period <= 25 days, "invalid period");
        freePeriod = _period;
    }
    
}


interface IMoonMasterChef {
    function userInfo(uint256 pid, address user) external view returns (uint256, uint256); 
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
}