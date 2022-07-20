// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract BUSDBuffetTeamLocker is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public isActive = false;
    bool private initialized = false;

    IERC20 public token;

    uint256 public lockDuration = 365; // 365 days
    address public  reflectionToken;
    uint256 private accReflectionPerShare;
    uint256 private allocatedReflections;

    uint256 private PRECISION_FACTOR = 1 ether;
    uint256 constant MAX_STAKES = 256;

    struct Lock {
        uint256 amount;              // allocation point of token supply
        uint256 duration;            // team member can claim after duration in days
        uint256 reflectionDebt;
        uint256 releaseTime;
    }
   
    mapping(address => Lock[]) public locks;
    address[] public members;

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
        
        uint256 beforeAmount = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterAmount = token.balanceOf(address(this));
        uint256 realAmount = afterAmount.sub(beforeAmount);
        
        _addLock(msg.sender, realAmount);
        
        members.push(msg.sender);

        emit Deposited(msg.sender, amount, lockDuration);
    }

    function _addLock(address _account, uint256 _amount) internal {
        Lock[] storage _locks = locks[_account];

        uint256 releaseTime = block.timestamp.add(lockDuration.mul(1 days));
        uint256 i = _locks.length;

        require(i < MAX_STAKES, "Max Locks");

        _locks.push(); // grow the array
        // find the spot where we can insert the current stake
        // this should make an increasing list sorted by end
        while (i != 0 && _locks[i - 1].releaseTime > releaseTime) {
            // shift it back one
            _locks[i] = _locks[i - 1];
            i -= 1;
        }
        
        // insert the stake
        Lock storage _lock = _locks[i];
        _lock.amount = _amount;
        _lock.duration = lockDuration;
        _lock.reflectionDebt = _amount.mul(accReflectionPerShare).div(PRECISION_FACTOR);
        _lock.releaseTime = releaseTime;
    }


    function harvest() external onlyActive {
        _updatePool();

        Lock[] storage _locks = locks[msg.sender];

        uint256 reflectionAmt = 0;
        for(uint256 i = 0; i < _locks.length; i++) {
            Lock storage _lock = _locks[i];
            if(_lock.amount == 0) continue;

            reflectionAmt = reflectionAmt.add(
                _lock.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(_lock.reflectionDebt)
            );

            _lock.reflectionDebt = _lock.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR);
        }

        if(reflectionAmt > 0) {
            if(reflectionToken == address(0x0)) {
                payable(msg.sender).transfer(reflectionAmt);
            } else {
                IERC20(reflectionToken).safeTransfer(msg.sender, reflectionAmt);
            }

            allocatedReflections = allocatedReflections.sub(reflectionAmt);
        }
    }
    

    function release() public onlyActive {
        _updatePool();

        Lock[] storage _locks = locks[msg.sender];

        uint256 claimAmt = 0;
        uint256 reflectionAmt = 0;
        for(uint256 i = 0; i < _locks.length; i++) {
            Lock storage _lock = _locks[i];
            if(_lock.amount == 0) continue;
            if(_lock.releaseTime > block.timestamp) continue;

            claimAmt = claimAmt.add(_lock.amount);
            reflectionAmt = reflectionAmt.add(
                _lock.amount.mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(_lock.reflectionDebt)
            );

            _lock.amount = 0;
            _lock.reflectionDebt = 0;
        }

        if(claimAmt > 0) {
            token.safeTransfer(msg.sender, claimAmt);
        }

        if(reflectionAmt > 0) {
            if(reflectionToken == address(0x0)) {
                payable(msg.sender).transfer(reflectionAmt);
            } else {
                IERC20(reflectionToken).safeTransfer(msg.sender, reflectionAmt);
            }
            allocatedReflections = allocatedReflections.sub(reflectionAmt);
        }
    }

    function pendingReflection(address _user) external view returns (uint256) {
        uint256 tokenAmt = token.balanceOf(address(this));
        if(tokenAmt == 0) return 0;

        uint256 reflectionAmt = address(this).balance;
        if(reflectionToken != address(0x0)) {
            reflectionAmt = IERC20(reflectionToken).balanceOf(address(this));
        }
        reflectionAmt = reflectionAmt.sub(allocatedReflections);
        uint256 _accReflectionPerShare = accReflectionPerShare.add(reflectionAmt.mul(PRECISION_FACTOR).div(tokenAmt));

        Lock[] storage _locks = locks[_user];

        uint256 pending = 0;
        for(uint256 i = 0; i < _locks.length; i++) {
            Lock storage _lock = _locks[i];
            if(_lock.amount == 0) continue;

            pending = pending.add(
                _lock.amount.mul(_accReflectionPerShare).div(PRECISION_FACTOR).sub(_lock.reflectionDebt)
            );
        }
        
        return pending;
    }

    function pendingTokens(address _user) public view returns (uint256) {
        Lock[] storage _locks = locks[_user];

        uint256 claimAmt = 0;
        for(uint256 i = 0; i < _locks.length; i++) {
            Lock storage _lock = _locks[i];
            if(_lock.amount == 0) continue;
            if(_lock.releaseTime > block.timestamp) continue;

            claimAmt = claimAmt.add(_lock.amount);
        }

        return claimAmt;
    }

    function totalLocked(address _user) public view returns (uint256) {
        Lock[] storage _locks = locks[_user];

        uint256 amount = 0;
        for(uint256 i = 0; i < _locks.length; i++) {
            Lock storage _lock = _locks[i];
            if(_lock.amount == 0) continue;

            amount = amount.add(_lock.amount);
        }

        return amount;
    }

    function setStatus(bool _isActive) external onlyOwner {
        isActive = _isActive;
    }

    function updateLockDuration(uint256 _duration) external onlyOwner {
        lockDuration = _duration;
        emit LockDurationUpdated(_duration);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 tokenAmt = token.balanceOf(address(this));
        if(tokenAmt > 0) {
            token.transfer(msg.sender, tokenAmt);
        }

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

    function _updatePool() internal {
        uint256 tokenAmt = token.balanceOf(address(this));
        if(tokenAmt == 0) return;

        uint256 reflectionAmt = address(this).balance;
        if(reflectionToken != address(0x0)) {
            reflectionAmt = IERC20(reflectionToken).balanceOf(address(this));
        }
        reflectionAmt = reflectionAmt.sub(allocatedReflections);

        accReflectionPerShare = accReflectionPerShare.add(reflectionAmt.mul(PRECISION_FACTOR).div(tokenAmt));
        allocatedReflections = allocatedReflections.add(reflectionAmt);
    }

    receive() external payable {}
}