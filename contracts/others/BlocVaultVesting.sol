// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BlocVaultVesting is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public     isActive = false;
    bool private    initialized = false;

    IERC20  public  vestingToken;
    address public  reflectionToken;
    uint256 private accReflectionPerShare;
    uint256 private allocatedReflections;
    uint256 private reflectionDebt;

    uint256[4] public duration = [90, 180, 240, 360];
    uint256 public rewardCycle = 30;    // 30 days
    uint256 public rewardRate = 1000;   // 10% per 30 days

    uint256 public harvestCycle = 7; // 7 days

    uint256 private PRECISION_FACTOR = 1 ether;
    uint256 private TIME_UNIT = 1 days;

    struct UserInfo {
        uint256 counts;          // number of vesting
        uint256 totalVested;     // vested total amount in wei
    }

    struct VestingInfo {
        uint256 amount;             // vested amount
        uint256 duration;           // lock duration in day
        uint256 lockedTime;         // timestamp that user locked tokens
        uint256 releaseTime;        // timestamp that user can unlock tokens
        uint256 lastHarvestTime;    // last timestamp that user harvested reflections of vested tokens
        uint256 tokenDebt;          // amount that user havested reward
        uint256 reflectionDebt;
        uint8   status;
    }
   
    uint256 public totalVested = 0;
    uint256 private totalEarned;
    mapping(address => UserInfo) public userInfo;
    mapping(address => mapping(uint256 => VestingInfo))  public vestingInfos;

    event Vested(address user, uint256 id, uint256 amount, uint256 duration);
    event Released(address user, uint256 id, uint256 amount);
    event Revoked(address user, uint256 id, uint256 amount);
    event RewardClaimed(address user, uint256 amount);
    event DividendClaimed(address user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event DurationUpdated(uint256 idx, uint256 duration);
    event RateUpdated(uint256 rate);
        
    modifier onlyActive() {
        require(isActive == true, "not active");
        _;
    }

    constructor () {}

    function initialize(IERC20 _token, address _reflectionToken) external onlyOwner {
        require(initialized == false, "already initialized");
        initialized = true;

        vestingToken = _token;
        reflectionToken = _reflectionToken;
    }

    function vest(uint256 _amount, uint256 _type) external onlyActive nonReentrant {
        require(_amount > 0, "Invalid amount");
        require(_type < 4, "Invalid vesting type");

        _updatePool();
        
        uint256 beforeAmount = vestingToken.balanceOf(address(this));
        vestingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmount = vestingToken.balanceOf(address(this));
        uint256 realAmount = afterAmount.sub(beforeAmount);
        
        UserInfo storage _userInfo = userInfo[msg.sender];
        
        uint256 lastIndex = _userInfo.counts;
        vestingInfos[msg.sender][lastIndex] = VestingInfo(
            realAmount,
            duration[_type],
            block.timestamp,
            block.timestamp.add(duration[_type].mul(TIME_UNIT)),
            block.timestamp,
            0,
            realAmount.mul(accReflectionPerShare).div(PRECISION_FACTOR),
            0
        );
        
        _userInfo.counts = lastIndex.add(1);
        _userInfo.totalVested = _userInfo.totalVested.add(realAmount);

        totalVested = totalVested.add(realAmount);

        emit Vested(msg.sender, lastIndex, _amount, duration[_type]);
    }

    function revoke(uint256 _vestId) external onlyActive nonReentrant {
        VestingInfo storage _vest = vestingInfos[msg.sender][_vestId];
        require(_vest.amount > 0 && _vest.status == 0, "Not available");

        vestingToken.safeTransfer(msg.sender, _vest.amount);

        _vest.status = 2;

        UserInfo storage _userInfo = userInfo[msg.sender];
        _userInfo.totalVested = _userInfo.totalVested.sub(_vest.amount);
        totalVested = totalVested.sub(_vest.amount);

        emit Revoked(msg.sender, _vestId, _vest.amount);
    }

    function release(uint256 _vestId) external onlyActive nonReentrant {
        VestingInfo storage _vest = vestingInfos[msg.sender][_vestId];

        require(_vest.amount > 0 && _vest.status == 0, "Not available");
        require(_vest.releaseTime < block.timestamp, "Not Releasable");

        _updatePool();

        uint pending = calcReward(_vest.amount, _vest.lockedTime, _vest.releaseTime, _vest.tokenDebt);
        require(pending <= availableRewardTokens(), "Insufficient reward");

        uint256 claimAmt = _vest.amount.add(pending);
        if(claimAmt > 0) {
            vestingToken.safeTransfer(msg.sender, claimAmt);
            emit RewardClaimed(msg.sender, pending);
        }

        if(totalEarned > pending) {
            totalEarned = totalEarned.sub(pending);
        } else {
            totalEarned = 0;
        }

        uint256 reflectionAmt = _vest.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(_vest.reflectionDebt);
        if(reflectionAmt > 0) {
            if(reflectionToken == address(0x0)) {
                payable(msg.sender).transfer(reflectionAmt);
            } else {
                IERC20(reflectionToken).safeTransfer(msg.sender, reflectionAmt);
            }
            allocatedReflections = allocatedReflections.sub(reflectionAmt);
            emit DividendClaimed(msg.sender, reflectionAmt);
        }

        _vest.tokenDebt = _vest.tokenDebt.add(pending);
        _vest.reflectionDebt = _vest.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR);
        _vest.status = 1;

        UserInfo storage _userInfo = userInfo[msg.sender];
        _userInfo.totalVested = _userInfo.totalVested.sub(_vest.amount);
        totalVested = totalVested.sub(_vest.amount);

        emit Released(msg.sender, _vestId, _vest.amount);
    }

    function claimDividend(uint256 _vestId) external onlyActive nonReentrant {
        VestingInfo storage _vest = vestingInfos[msg.sender][_vestId];
        require(_vest.amount > 0 && _vest.status == 0, "Not available");
        require(block.timestamp.sub(_vest.lastHarvestTime) > harvestCycle.mul(TIME_UNIT), "Cannot harvest in 7 days after last harvest");

        _updatePool();

        uint256 reflectionAmt = _vest.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(_vest.reflectionDebt);
        if(reflectionAmt > 0) {
            if(reflectionToken == address(0x0)) {
                payable(msg.sender).transfer(reflectionAmt);
            } else {
                IERC20(reflectionToken).safeTransfer(msg.sender, reflectionAmt);
            }

            allocatedReflections = allocatedReflections.sub(reflectionAmt);
            emit DividendClaimed(msg.sender, reflectionAmt);
        }

        _vest.lastHarvestTime = block.timestamp;
        _vest.reflectionDebt = _vest.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR);
    }

    function claimReward(uint256 _vestId) external onlyActive nonReentrant {
        VestingInfo storage _vest = vestingInfos[msg.sender][_vestId];
        require(_vest.amount > 0 && _vest.status == 0, "Not available");
        require(block.timestamp.sub(_vest.lastHarvestTime) > harvestCycle.mul(TIME_UNIT), "Cannot harvest in 7 days after last harvest");

        uint pending = calcReward(_vest.amount, _vest.lockedTime, _vest.releaseTime, _vest.tokenDebt);
        require(pending <= availableRewardTokens(), "Insufficient reward");

        if(pending > 0) {
            vestingToken.safeTransfer(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);

            if(totalEarned > pending) {
                totalEarned = totalEarned.sub(pending);
            } else {
                totalEarned = 0;
            }
        }        

        _vest.lastHarvestTime = block.timestamp;
        _vest.tokenDebt = _vest.tokenDebt.add(pending);
    }

    function calcReward(uint256 _amount, uint256 _lockedTime, uint256 _releaseTime, uint256 _rewardDebt) internal view returns(uint256 reward) {
        if(_lockedTime > block.timestamp) return 0;

        uint256 passTime = block.timestamp.sub(_lockedTime);
        if(_releaseTime < block.timestamp) {
            passTime = _releaseTime.sub(_lockedTime);
        }

        reward = _amount.mul(rewardRate).div(10000)
                        .mul(passTime).div(rewardCycle.mul(TIME_UNIT))
                        .sub(_rewardDebt);
    }

    function pendingClaim(address _user, uint256 _vestId) external view returns (uint256 pending) {
        VestingInfo storage _vest = vestingInfos[_user][_vestId];
        if(_vest.status > 0 || _vest.amount == 0) return 0;

        pending = calcReward(_vest.amount, _vest.lockedTime, _vest.releaseTime, _vest.tokenDebt);
    }

    function pendingDividend(address _user, uint256 _vestId) external view returns (uint256 pending) {
        VestingInfo storage _vest = vestingInfos[_user][_vestId];
        if(_vest.status > 0 || _vest.amount == 0) return 0;

        uint256 tokenAmt = vestingToken.balanceOf(address(this));
        if(tokenAmt == 0) return 0;

        uint256 reflectionAmt = availableDividendTokens();
        reflectionAmt = reflectionAmt.sub(allocatedReflections);
        uint256 _accReflectionPerShare = accReflectionPerShare.add(reflectionAmt.mul(PRECISION_FACTOR).div(tokenAmt));

        pending = _vest.amount.mul(_accReflectionPerShare).div(PRECISION_FACTOR).sub(_vest.reflectionDebt);
    }

    /**
     * @notice Available amount of reflection token
     */
    function availableDividendTokens() public view returns (uint256) {
        if(address(reflectionToken) == address(0x0)) {
            return address(this).balance;
        }

        if(address(reflectionToken) == address(vestingToken)) {
            uint256 _amount = IERC20(reflectionToken).balanceOf(address(this));
            if(_amount < totalEarned.add(totalVested)) return 0;
            return _amount.sub(totalEarned).sub(totalVested);
        } else {
            uint256 _amount = address(this).balance;
            if(reflectionToken != address(0x0)) {
                _amount = IERC20(reflectionToken).balanceOf(address(this));
            }
            return _amount;
        }
    }
    
    /**
     * @notice Available amount of reward token
     */
    function availableRewardTokens() public view returns (uint256) {
        if(address(vestingToken) == address(reflectionToken)) return totalEarned;

        uint256 _amount = vestingToken.balanceOf(address(this));
        if (_amount < totalVested) return 0;
        return _amount.sub(totalVested);
    }

     /*
     * @notice Deposit reward token
     * @dev Only call by owner. Needs to be for deposit of reward token when reflection token is same with reward token.
     */
    function depositRewards(uint _amount) external nonReentrant {
        require(_amount > 0);

        uint256 beforeAmt = vestingToken.balanceOf(address(this));
        vestingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = vestingToken.balanceOf(address(this));

        totalEarned = totalEarned.add(afterAmt).sub(beforeAmt);
    }

    function harvest() external onlyOwner {
        _updatePool();

        uint256 tokenAmt = availableRewardTokens();
        uint256 reflectionAmt = (tokenAmt).mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(reflectionDebt);
        if(reflectionAmt > 0) {
            payable(msg.sender).transfer(reflectionAmt);
        } else {
            IERC20(reflectionToken).safeTransfer(msg.sender, reflectionAmt);
        }

        reflectionDebt = (tokenAmt.sub(totalVested)).mul(accReflectionPerShare).div(PRECISION_FACTOR);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 tokenAmt = vestingToken.balanceOf(address(this));
        if(tokenAmt > 0) {
            vestingToken.transfer(msg.sender, tokenAmt.sub(totalVested));
        }

        if(address(reflectionToken) != address(vestingToken)) {
            uint256 reflectionAmt = address(this).balance;
            if(reflectionToken != address(0x0)) {
                reflectionAmt = IERC20(reflectionToken).balanceOf(address(this));
            }

            if(reflectionAmt > 0) {
                if(reflectionToken == address(0x0)) {
                    payable(msg.sender).transfer(reflectionAmt);
                } else {
                    IERC20(reflectionToken).transfer(msg.sender, reflectionAmt);
                }
            }
        }

        totalEarned = 0;

        allocatedReflections = 0;
        accReflectionPerShare = 0;
        reflectionDebt = 0;
    }

    function recoverWrongToken(address _token) external onlyOwner {
        require(_token != address(vestingToken), "Cannot recover locked token");
        require(_token != reflectionToken, "Cannot recover reflection token");

        if(_token == address(0x0)) {
            uint256 amount = address(this).balance;
            payable(msg.sender).transfer(amount);
        } else {
            uint256 amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(address(msg.sender), amount);
        }
    }

    function setDuration(uint256 _type, uint256 _duration) external onlyOwner {
        require(isActive == false, "Vesting was started");

        duration[_type] = _duration;
        emit DurationUpdated(_type, _duration);
    }

    function setRewardRate(uint256 _rate) external onlyOwner {
        require(isActive == false, "Vesting was started");

        rewardRate = _rate;
        emit RateUpdated(_rate);
    }

    function setStatus(bool _isActive) external onlyOwner {
        isActive = _isActive;
    }

    function _updatePool() internal {
        uint256 tokenAmt = availableRewardTokens();
        tokenAmt = tokenAmt.add(totalVested);
        if(tokenAmt == 0) return;

        uint256 reflectionAmt = availableDividendTokens();
        reflectionAmt = reflectionAmt.sub(allocatedReflections);

        accReflectionPerShare = accReflectionPerShare.add(reflectionAmt.mul(PRECISION_FACTOR).div(tokenAmt));
        allocatedReflections = allocatedReflections.add(reflectionAmt);
    }

    receive() external payable {}
}