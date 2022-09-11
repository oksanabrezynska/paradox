// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";



contract NFTPresale is Ownable, Pausable {
    using SafeERC20 for IERC20; 

    address public usdtAddress;
    address public paradoxAddress;

    IERC20 internal para;
    IERC20 internal usdt;

    mapping(address => bool) _claimed;

    uint256 constant paradoxDecimals = 10 ** 18;
    uint256 constant usdtDecimals = 10 ** 6;
    
    uint256 constant exchangeRate = 125;
    uint256 constant exchangeRatePrecision = 1000;

    mapping(address => Lock) public locks;
    
    // exchange launch time to be set by owner, also unlocks vesting
    uint256 public exchangeLaunchTime;

    struct Lock {
        uint256 total;
        uint256 max;
        uint256 paid;
        uint256 debt
    }

    constructor (address _usdt, address _paradox) {
        usdtAddress = _usdt;
        usdt = IERC20(_usdt);

        paradoxAddress = _paradox;
        para = IERC20(_paradox);
        
        // pause claiming vested tokens until exchange launch.
        _pause()
    }

    function getClaimed(address _user) external view returns (bool) {
        return _claimed[_user];
    }

    function buyParadox(
        address destination,
        uint256 amount,
        uint256 buyAmount
    ) external {
        uint256 maxUSD = 1000 * usdtDecimals;
        require(buyAmount <= maxUSD, "Wrong amount");

        // get exchange rate to para
        uint256 rate = buyAmount * exchangeRatePrecision * paradoxDecimals / (usdtDecimals * exchangeRate);
        require(rate <= para.balanceOf(address(this)), "Low balance");
        // give user 10% now
        uint256 rateNow = rate * 20 / 100;
        uint256 vestingRate = rate - rateNow;

        if (locks[destination].total == 0) {
            // new claim
            locks[destination] = Lock({
                total: vestingRate,
                max: maxUSD,
                paid: buyAmount,
                debt: 0
            });

            if (buyAmount == maxUSD) _claimed[destination] = true;
        } else {
            // at this point, the user still has some pending amount they can claim
            require(buyAmount + locks[destination].paid <= locks[destination].max, "Too Much");

            locks[destination].total += vestingRate;
            if (buyAmount + locks[destination].paid == locks[destination].max) _claimed[destination] = true;
            locks[destination].paid += buyAmount;
        }

        usdt.safeTransferFrom(destination, address(this), buyAmount);
        para.safeTransfer(destination, rateNow);
    }

    function pendingClaim(address _user) external view whenNotPaused returns (uint256) {
        Lock memory userLock = locks[_user];

        uint256 monthsPassed = (block.timestamp - exchangeLaunchTime) / 4 weeks;
        /** @notice userlock.total = 90%, 10% released each month. */
        uint256 monthlyRelease = userLock.total / 8;
        
        uint256 release;
        for (uint256 i = 0; i < monthsPassed; i++) {
            release += monthlyRelease;
        }

        return release - userLock.debt;
    }

   function claim() external whenNotPaused {
        Lock storage userLock = locks[msg.sender];

        uint256 monthsPassed = (block.timestamp - exchangeLaunchTime) / 4 weeks;
        /** @notice userlock.total = 80%, 20% released each month. */
        uint256 monthlyRelease = userLock.total / 8;
        
        uint256 release;
        for (uint256 i = 0; i < monthsPassed; i++) {
            release += monthlyRelease;
        }

        uint256 reward = release - userLock.debt;
        userLock.debt += reward;
        para.safeTransfer(msg.sender, reward);
    }

    function withdrawTether() external onlyOwner {
        usdt.safeTransfer(msg.sender, usdt.balanceOf(address(this)));
    }


    /** @notice EMERGENCY FUNCTIONS */
    
    function setLaunchTime(uint256 _launchTime) external onlyOwner {
        exchangeLaunchTime = _launchTime;
        unpause();
    }

    function updateClaimed(address _user) external onlyOwner {
        _claimed[_user] = !_claimed[_user];
    }

    function updateUserLock(address _user, uint256 _total, uint256 _max, uint256 _paid, uint256 _startTime) external onlyOwner {
        Lock storage lock = locks[_user];
        lock.total = _total;
        lock.max = _max;
        lock.paid = _paid;
    }
    
    function withdrawETH() external onlyOwner {
        address payable to = payable(msg.sender);
        to.transfer(address(this).balance);
    }

    function withdrawParadox() external onlyOwner {
        para.safeTransfer(msg.sender, para.balanceOf(address(this)));
    }
}