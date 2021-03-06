pragma solidity ^0.6.0;

import "./BaseVault.sol";
import "../utils/TokenConverter.sol";


contract BeltVault is BaseVault, TokenConverter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public constant lpToken = 0x86aFa7ff694Ab8C985b79733745662760e454169;
    address public constant belt = 0xE0e514c71282b6f4e823703a39374Cf58dc3eA4f;
    address public constant wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant busd = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; 


    address public constant beltMasterChef = 0xD4BbC80b9B102b77B21A06cb77E954049605E6c1;
    uint256 public constant beltMasterChefPid = 0;
    address public constant beltVenusPool = 0xf157A4799bE445e3808592eDd7E7f72150a7B050;

    address public constant pancakeFactory = 0xBCfCcbde45cE874adCB698cC183deBcF17952812;
    
    address public dailyToken;
    address public feeReceiver;
    address public devAddr;

    uint256 public xRewardRate = 50;
    uint256 public freePeriod = 2 days;
    uint256 public exitFeeRate = 2;

    constructor(
        address _dailyMasterChef,
        address _dailyToken,
        address _feeReceiver
    ) 
        public 
        BaseVault(
            "daily Belt",
            "d_BELT_FI",
            lpToken
        )
        TokenConverter(pancakeFactory) 
    {
        dailyToken = _dailyToken;
        feeReceiver = _feeReceiver;
        devAddr = msg.sender;
        IERC20(lpToken).safeApprove(beltMasterChef, 10**60);
        IERC20(busd).safeApprove(beltVenusPool, 10**60);
    }

    function _harvest() internal override {
        (uint256 stakeAmount, ) = IBeltMasterChef(beltMasterChef).userInfo(beltMasterChefPid, address(this));
        if (stakeAmount > 0) {
            IBeltMasterChef(beltMasterChef).withdraw(beltMasterChefPid, 0);
        }
        uint256 beltAmount = IERC20(belt).balanceOf(address(this));
        if (beltAmount > 0) {
            // 50% for xDaily stakers
            uint256 xReward = beltAmount.mul(xRewardRate).div(100);
            _swap(belt, wbnb, xReward, address(this));
            _swap(wbnb, dailyToken, IERC20(wbnb).balanceOf(address(this)), feeReceiver);

            beltAmount = beltAmount.sub(xReward);
            _swap(belt, wbnb, beltAmount, address(this));
            _swap(wbnb, busd, IERC20(wbnb).balanceOf(address(this)), address(this));

            (bool success, bytes memory returnData) = beltVenusPool.call{value: 0}(
                abi.encodePacked(
                    bytes4(0x029b2f34),
                    abi.encode(
                        uint256(0), uint256(0), uint256(0),
                        IERC20(busd).balanceOf(address(this)),
                        uint256(1)
                    )
                )
            );
            require(success, "beltVenusPool add lp error");
            
        }
    }

    function _invest() internal override {
        uint256 lpAmount = IERC20(lpToken).balanceOf(address(this));
        if (lpAmount > 0) {
            IBeltMasterChef(beltMasterChef).deposit(beltMasterChefPid, lpAmount);
        }
    }

    function _exit() internal override {
        IBeltMasterChef(beltMasterChef).withdrawAll(beltMasterChefPid);
    }

    function _exitSome(uint256 _amount) internal override {
        IBeltMasterChef(beltMasterChef).withdraw(beltMasterChefPid, _amount);
    }

    function _withdrawFee(uint256 _withdrawAmount, uint256 _lastDepositTime) internal override returns (uint256) {
        if (_lastDepositTime.add(freePeriod) <= block.timestamp) {
            return 0;
        }
        uint256 feeAmount = _withdrawAmount.mul(exitFeeRate).div(1000);
        IERC20(lpToken).safeTransfer(devAddr, feeAmount);
        return feeAmount;
    }

    function _totalTokenBalance() internal view override returns (uint256) {
        uint256 stakeAmount = IBeltMasterChef(beltMasterChef).stakedWantTokens(beltMasterChefPid, address(this));
        return IERC20(lpToken).balanceOf(address(this)).add(stakeAmount);
    }

    function setFreePeriod(uint256 _period) public onlyOwner {
        require(_period >= 2 days && _period <= 15 days, "invalid period");
        freePeriod = _period;
    }

    function setXRewardRate(uint256 _rate) public onlyOwner {
        require(_rate >= 10 && _rate <= 80, "invalid rate");
        xRewardRate = _rate;
    }

    function setExitFeeRate(uint256 _rate) public onlyOwner {
        require(_rate <= 50, "invalid");
        exitFeeRate = _rate;
    }

    function dev(address _dev) public {
        require(msg.sender == devAddr || msg.sender == owner(), "dev: wut?");
        devAddr = _dev;
    }
    
}


interface IBeltMasterChef {
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 pid, address user) external view returns (uint256, uint256); 
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function withdrawAll(uint256 _pid) external;
}