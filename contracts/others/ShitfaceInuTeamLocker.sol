// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract ShitfaceInuTeamLocker is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public isActive = false;
    bool private initialized = false;

    IERC20 public token;
    address public reflectionToken;
    uint256 public totalLocked;

    uint256 public lockDuration = 180; // 180 days
    uint256 private accReflectionPerShare;
    uint256 private allocatedReflections;
    uint256 private processingLimit = 30;

    uint256 private PRECISION_FACTOR = 1 ether;
    uint256 constant MAX_STAKES = 256;

    struct Lock {
        uint256 amount;              // locked amount
        uint256 duration;            // team member can claim after duration in days
        uint256 releaseTime;
    }

    struct UserInfo {
        uint256 amount;         // total locked amount
        uint256 firstIndex;     // first index for unlocked elements
        uint256 reflectionDebt; // Reflection debt
    }
   
    mapping(address => Lock[]) public locks;
    mapping(address => UserInfo) public userInfo;
    address[] public members;
    mapping(address => bool) private isMember;

    event Deposited(address member, uint256 amount, uint256 duration);
    event Released(address member, uint256 amount);
    event LockDurationUpdated(uint256 duration);
        
    modifier onlyActive() {
        require(isActive == true, "not active");
        _;
    }

    constructor () {}

    function initialize(IERC20 _token, address _reflectionToken) external onlyOwner {
        require(initialized == false, "already initialized");
        initialized = true;

        token = _token;
        reflectionToken = _reflectionToken;
    }

    function deposit(uint256 amount) external onlyActive {
        require(amount > 0, "Invalid amount");

        _updatePool();

        UserInfo storage user = userInfo[msg.sender];        
        uint256 pending = user.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(user.reflectionDebt);
        if (pending > 0) {
            if(reflectionToken == address(0x0)) {
                payable(msg.sender).transfer(pending);
            } else {
                IERC20(reflectionToken).safeTransfer(address(msg.sender), pending);
            }
            allocatedReflections = allocatedReflections.sub(pending);
        }
        
        uint256 beforeAmount = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterAmount = token.balanceOf(address(this));
        uint256 realAmount = afterAmount.sub(beforeAmount);
        
        _addLock(msg.sender, realAmount, user.firstIndex);
        
        if(isMember[msg.sender] == false) {
            members.push(msg.sender);
            isMember[msg.sender] = true;
        }

        user.amount = user.amount.add(realAmount);
        user.reflectionDebt = user.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR);

        totalLocked = totalLocked.add(realAmount);

        emit Deposited(msg.sender, amount, lockDuration);
    }

    function _addLock(address _account, uint256 _amount, uint256 firstIndex) internal {
        Lock[] storage _locks = locks[_account];

        uint256 releaseTime = block.timestamp.add(lockDuration.mul(1 days));
        uint256 i = _locks.length;

        require(i < MAX_STAKES, "Max Locks");

        _locks.push(); // grow the array
        // find the spot where we can insert the current stake
        // this should make an increasing list sorted by end
        while (i != 0 && _locks[i - 1].releaseTime > releaseTime && i >= firstIndex) {
            // shift it back one
            _locks[i] = _locks[i - 1];
            i -= 1;
        }
        
        // insert the stake
        Lock storage _lock = _locks[i];
        _lock.amount = _amount;
        _lock.duration = lockDuration;
        _lock.releaseTime = releaseTime;
    }


    function harvest() external onlyActive {
        _updatePool();

        UserInfo storage user = userInfo[msg.sender];        
        uint256 pending = user.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(user.reflectionDebt);
        if (pending > 0) {
            if(reflectionToken == address(0x0)) {
                payable(msg.sender).transfer(pending);
            } else {
                IERC20(reflectionToken).safeTransfer(address(msg.sender), pending);
            }
            allocatedReflections = allocatedReflections.sub(pending);
        }
        
        user.reflectionDebt = user.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR);
    }

    function release() public onlyActive {
        _updatePool();

        UserInfo storage user = userInfo[msg.sender];
        Lock[] storage _locks = locks[msg.sender];
        
        bool bUpdatable = true;
        uint256 firstIndex = user.firstIndex;
        
        uint256 claimAmt = 0;
        for(uint256 i = user.firstIndex; i < _locks.length; i++) {
            Lock storage _lock = _locks[i];

            if(bUpdatable && _lock.amount == 0) firstIndex = i;
            if(_lock.amount == 0) continue;
            if(_lock.releaseTime > block.timestamp) {
                bUpdatable = false;
                continue;
            }

            if(i - user.firstIndex > processingLimit) break;

            claimAmt = claimAmt.add(_lock.amount);
            _lock.amount = 0;

            firstIndex = i;
        }

        if(claimAmt > 0) {
            token.safeTransfer(msg.sender, claimAmt);
            emit Released(msg.sender, claimAmt);
        }
        
        uint256 reflectionAmt = user.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(user.reflectionDebt);
        if(reflectionAmt > 0) {
            if(reflectionToken == address(0x0)) {
                payable(msg.sender).transfer(reflectionAmt);
            } else {
                IERC20(reflectionToken).safeTransfer(msg.sender, reflectionAmt);
            }
            allocatedReflections = allocatedReflections.sub(reflectionAmt);
        }

        user.amount = user.amount.sub(claimAmt);
        user.reflectionDebt = user.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR);

        totalLocked = totalLocked.sub(claimAmt);
    }

    function pendingReflection(address _user) external view returns (uint256) {
        if(totalLocked == 0) return 0;

        uint256 reflectionAmt = availableRelectionTokens();
        reflectionAmt = reflectionAmt.sub(allocatedReflections);
        uint256 _accReflectionPerShare = accReflectionPerShare.add(reflectionAmt.mul(PRECISION_FACTOR).div(totalLocked));

        UserInfo memory user = userInfo[_user];
        uint256 pending = user.amount.mul(_accReflectionPerShare).div(PRECISION_FACTOR).sub(user.reflectionDebt);
        return pending;
    }

    function pendingTokens(address _user) public view returns (uint256) {
        Lock[] memory _locks = locks[_user];
        UserInfo memory user = userInfo[_user];

        uint256 claimAmt = 0;
        for(uint256 i = user.firstIndex; i < _locks.length; i++) {
            Lock memory _lock = _locks[i];
            if(_lock.amount == 0) continue;
            if(_lock.releaseTime > block.timestamp) continue;

            claimAmt = claimAmt.add(_lock.amount);
        }

        return claimAmt;
    }

    function totalLockedforUser(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        return user.amount;
    }

    function setStatus(bool _isActive) external onlyOwner {
        isActive = _isActive;
    }

    function updateLockDuration(uint256 _duration) external onlyOwner {
        lockDuration = _duration;
        emit LockDurationUpdated(_duration);
    }

    function setProcessingLimit(uint256 _limit) external onlyOwner {
        require(_limit > 0, "Invalid limit");
        processingLimit = _limit;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 tokenAmt = token.balanceOf(address(this));
        if(tokenAmt > 0) {
            token.transfer(msg.sender, tokenAmt);
        }

        if(address(token) == reflectionToken) return;

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

    function recoverWrongToken(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(token), "Cannot recover locked token");
        require(_tokenAddress != reflectionToken, "Cannot recover reflection token");

        if(_tokenAddress == address(0x0)) {
            uint256 amount = address(this).balance;
            payable(msg.sender).transfer(amount);
        } else {
            uint256 amount = IERC20(_tokenAddress).balanceOf(address(this));
            IERC20(_tokenAddress).safeTransfer(address(msg.sender), amount);
        }
    }

    function availableRelectionTokens() internal view returns (uint256) {
        uint256 _amount = address(this).balance;
        if(reflectionToken != address(0x0)) {
            _amount = IERC20(reflectionToken).balanceOf(address(this));

            if (address(token) == reflectionToken) {
                if (_amount < totalLocked) return 0;            
                return _amount.sub(totalLocked);
            }
        }

        return _amount;
    }

    function _updatePool() internal {
        if(totalLocked == 0) return;

        uint256 reflectionAmt = availableRelectionTokens();
        reflectionAmt = reflectionAmt.sub(allocatedReflections);

        accReflectionPerShare = accReflectionPerShare.add(reflectionAmt.mul(PRECISION_FACTOR).div(totalLocked));
        allocatedReflections = allocatedReflections.add(reflectionAmt);
    }

    receive() external payable {}
}