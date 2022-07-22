// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTPresale is Ownable {
    using SafeERC20 for IERC20; 

    address public usdtAddress;
    address public paradoxAddress;

    IERC20 internal para;
    IERC20 internal usdt;

    address public nftAddress;
    IERC721 internal nfts;

    mapping(address => bool) _claimed;

    bytes32 public root;

    uint256 constant mintSupply = 12500000 * paradoxDecimals;

    uint256 constant paradoxDecimals = 10 ** 18;
    uint256 constant usdtDecimals = 10 ** 6;
    
    uint256 constant exchangeRate = 8;
    uint256 constant exchangeRatePrecision = 100;

    uint256 constant month = 4 weeks;

    mapping(address => Lock) public locks;

    struct Lock {
        uint256 total;
        uint256 debt;
        uint256 startTime;
    }

    constructor (address _usdt, address _nfts, address _paradox, bytes32 _root) {
        usdtAddress = _usdt;
        usdt = IERC20(_usdt);

        nftAddress = _nfts;
        nfts = IERC721(_nfts);

        paradoxAddress = _paradox;
        para = IERC20(_paradox);

        root = _root;
    }

    function claimParadox(
        address destination,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        require(canClaim(destination, amount, merkleProof), "Invalid Claim");
        require(nfts.balanceOf(msg.sender) * 500 * usdtDecimals >= amount, "Not Enough USDT");

        _claimed[destination] = true;

        uint256 maxUSD = 500 * amount;
        // get exchange rate to para
        uint256 rate = maxUSD * exchangeRate * paradoxDecimals / usdtDecimals;
        require(rate <= para.balanceOf(address(this)), "Low balance");
        // give user 10% now
        uint256 rateNow = rate * 10 / 100;
        uint256 vestingRate = rate - rateNow;

        locks[destination] = Lock({
            total: vestingRate,
            debt: 0,
            startTime: block.timestamp
        });

        usdt.safeTransferFrom(destination, address(this), maxUSD);
        para.safeTransfer(destination, rateNow);
    }

    /**
     * @dev helper for validating if an address has GENI to claim
     * @return true if claimant has not already claimed and the data is valid, false otherwise
     */
    function canClaim(
        address destination,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(destination, amount));
        return
            !_claimed[destination] &&
            MerkleProof.verify(merkleProof, root, node);
    }

    function pendingVestedClaim(address _user) external view returns (uint256) {
        Lock memory userLock = locks[_user];

        uint256 monthsPassed = block.timestamp % userLock.startTime;
        /** @notice userlock.total = 90%, 10% released each month. */
        uint256 monthlyRelease = userLock.total / 9;
        
        uint256 release;
        for (uint256 i = 0; i <= monthsPassed; i++) {
            release += monthlyRelease;
        }

        return release - userLock.debt;
    }

   function claimVested(address _user) external {
        Lock memory userLock = locks[_user];

        uint256 monthsPassed = block.timestamp % userLock.startTime;
        /** @notice userlock.total = 90%, 10% released each month. */
        uint256 monthlyRelease = userLock.total / 9;
        
        uint256 release;
        for (uint256 i = 0; i <= monthsPassed; i++) {
            release += monthlyRelease;
        }

        uint256 reward = release - userLock.debt;
        userLock.debt += reward;
        para.safeTransfer(_user, reward);
    }

    function updateRoot(bytes32 _root) external onlyOwner{
        root = _root;
    }
}