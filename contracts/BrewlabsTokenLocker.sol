// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BrewlabsTokenLocker is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool private initialized = false;

    IERC20  public token;
    address public reflectionToken;

    uint256 public defrostFee;
    uint256 public editFee;
    uint256 public performanceFee = 0.0035 ether;

    uint256 public NONCE = 0;
    uint256 public totalLocked;
    address public treasury;

    uint256 private accReflectionPerShare;
    uint256 private totalReflections;
    address private devWallet;
    uint256 private devRate;
    
    struct TokenLock {
        uint256 lockID; // lockID nonce per token
        uint256 lockDate; // the date the token was locked
        uint256 amount; // the amount of tokens still locked
        uint256 unlockTime; // the date the token can be withdrawn
        uint256 unlockRate; // 0 - not vesting, else - vesting 
        address operator;
        uint256 tokenDebt;
        uint256 reflectionDebt;
        bool isDefrost;
    }
    mapping(uint256 => TokenLock) public locks;

    event NewLock(uint256 lockID, address operator, address token, uint256 amount, uint256 unlockTime, uint256 unlockRate);
    event SplitLock(uint256 lockID, uint256 newLockID, address operator, uint256 amount, uint256 unlockTime);
    event AddLock(uint256 lockID, uint256 amount);
    event TransferLock(uint256 lockID, address operator);
    event Relock(uint256 lockID, uint256 amount, uint256 unlockTime);
    event DefrostActivated(uint256 lockID);
    event Defrosted(uint256 lockID);
    event Claimed(uint256 lockID, uint256 amount);

    event UpdateUnlockRate(uint256 rate);
    event UpdateTreasury(address addr);

    constructor() {}

    function initialize(address _token, address _reflectionToken, address _treasury, uint256 _editFee, uint256 _defrostFee, address _devWallet, uint256 _devRate, address _owner) external {
        require(initialized == false, "already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "not allowed");

        initialized = true;
            
        token = IERC20(_token);
        reflectionToken = _reflectionToken;

        treasury = _treasury;
        editFee = _editFee;
        defrostFee = _defrostFee;

        devWallet = _devWallet;
        devRate = _devRate;

        _transferOwnership(_owner);
    }

    function newLock(address _operator, uint256 _amount, uint256 _unlockTime, uint256 _unlockRate) external onlyOwner {
        require(_operator != address(0x0), "Invalid address");
        require(_unlockTime > block.timestamp, "Invalid unlock time");
        require(_amount > 0, "Invalid amount");

        _updatePool();

        uint256 beforeAmt = token.balanceOf(address(this));
        token.transferFrom(msg.sender, address(this), _amount);
        uint256 amountIn = token.balanceOf(address(this)).sub(beforeAmt);

        NONCE = NONCE.add(1);

        TokenLock storage lock = locks[NONCE];
        lock.lockID = NONCE;
        lock.lockDate = block.timestamp;
        lock.amount = amountIn;
        lock.unlockTime = _unlockTime;
        lock.unlockRate = _unlockRate;
        lock.operator = _operator;
        lock.tokenDebt = 0;
        lock.reflectionDebt = amountIn.mul(accReflectionPerShare).div(1e18);
        lock.isDefrost = false;

        totalLocked = totalLocked.add(amountIn);
        emit NewLock(lock.lockID, _operator, address(token), amountIn, _unlockTime, _unlockRate);
    }

    function addLock(uint256 _lockID, uint256 _amount) external payable nonReentrant {
        require(_amount > 0, "Invalid amount");
        
        TokenLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.unlockTime > block.timestamp, "already unlocked");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");

        _updatePool();
        _transferFee(editFee);

        uint256 beforeAmt = token.balanceOf(address(this));
        token.transferFrom(msg.sender, address(this), _amount);
        uint256 amountIn = token.balanceOf(address(this)).sub(beforeAmt);

        lock.amount = lock.amount.add(amountIn);
        lock.reflectionDebt = lock.reflectionDebt.add(amountIn.mul(accReflectionPerShare).div(1e18));
        
        totalLocked = totalLocked.add(amountIn);
        emit AddLock(_lockID, amountIn);
    }

    function splitLock(uint256 _lockID, address _operator, uint256 _amount, uint256 _unlockTime) external payable {
        require(_operator != address(0x0), "Invalid address");
        require(_amount > 0, "Invalid amount");

        TokenLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");
        require(lock.unlockTime > block.timestamp, "already unlocked");
        require(lock.amount.sub(lock.tokenDebt) > _amount, "amount exceed original locked amount");
        require(_unlockTime >= lock.unlockTime, "unlock time should be longer than original");

        _updatePool();
        _transferFee(editFee);

        uint256 pending = lock.amount.sub(lock.tokenDebt).mul(accReflectionPerShare).div(1e18).sub(lock.reflectionDebt);
        if(pending > 0) {
            if(reflectionToken == address(0x0)) {
                payable(lock.operator).transfer(pending);
            } else {
                IERC20(reflectionToken).safeTransfer(lock.operator, pending);
            }
            totalReflections = totalReflections.sub(pending);
        }

        lock.amount = lock.amount.sub(lock.tokenDebt).sub(_amount);
        lock.tokenDebt = 0;
        lock.reflectionDebt = lock.amount.mul(accReflectionPerShare).div(1e18);

        NONCE = NONCE.add(1);

        lock = locks[NONCE];
        lock.lockID = NONCE;
        lock.lockDate = block.timestamp;
        lock.amount = _amount;
        lock.tokenDebt = 0;
        lock.reflectionDebt = _amount.mul(accReflectionPerShare).div(1e18);
        lock.unlockTime = _unlockTime;
        lock.operator = _operator;
        lock.isDefrost = false;

        emit SplitLock(_lockID, lock.lockID, _operator, _amount, _unlockTime);
    }

    function reLock(uint256 _lockID, uint256 _unlockTime) external payable nonReentrant {
        require(_unlockTime > block.timestamp, "Invalid unlock time");
        require(_unlockTime > locks[_lockID].unlockTime, "Relock time should be longer than original");

        TokenLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");

        _updatePool();
        _transferFee(editFee);

        uint256 pending = lock.amount.sub(lock.tokenDebt).mul(accReflectionPerShare).div(1e18).sub(lock.reflectionDebt);
        if(pending > 0) {
            if(reflectionToken == address(0x0)) {
                payable(lock.operator).transfer(pending);
            } else {
                IERC20(reflectionToken).safeTransfer(lock.operator, pending);
            }
            totalReflections = totalReflections.sub(pending);
        }

        lock.lockDate = block.timestamp;
        lock.unlockTime = _unlockTime;
        lock.amount = lock.amount.sub(lock.tokenDebt);
        lock.tokenDebt = 0;
        lock.reflectionDebt = lock.amount.mul(accReflectionPerShare).div(1e18);

        emit Relock(_lockID, lock.amount, lock.unlockTime);
    }

    function transferLock(uint256 _lockID, address _operator) external payable {
        TokenLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");
        require(lock.unlockTime > block.timestamp, "already unlocked");

        require(_operator != address(0x0) && _operator != lock.operator, "invalid new operator");

        _transferFee(editFee);

        lock.operator = _operator;
        emit TransferLock(_lockID, _operator);
    }

    function claim(uint256 _lockID) external nonReentrant {
        TokenLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");
        require(lock.unlockTime < block.timestamp, "being locked yet");

        _updatePool();

        uint256 pending = lock.amount.sub(lock.tokenDebt).mul(accReflectionPerShare).div(1e18).sub(lock.reflectionDebt);
        if(pending > 0) {
            if(reflectionToken == address(0x0)) {
                payable(lock.operator).transfer(pending);
            } else {
                IERC20(reflectionToken).safeTransfer(lock.operator, pending);
            }
            totalReflections = totalReflections.sub(pending);
        }

        uint256 claimAmt = pendingClaims(_lockID);
        if(claimAmt > 0) {
            token.safeTransfer(lock.operator, claimAmt);

            lock.tokenDebt = lock.tokenDebt.add(claimAmt);
            lock.reflectionDebt = lock.amount.sub(lock.tokenDebt).mul(accReflectionPerShare).div(1e18);

            totalLocked = totalLocked.sub(claimAmt);
            emit Claimed(_lockID, claimAmt);
        }
    }

    function harvest(uint256 _lockID) external payable nonReentrant {
        TokenLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");

        _transferPerformanceFee();
        _updatePool();

        uint256 pending = lock.amount.sub(lock.tokenDebt).mul(accReflectionPerShare).div(1e18).sub(lock.reflectionDebt);
        if(pending > 0) {
            if(reflectionToken == address(0x0)) {
                payable(lock.operator).transfer(pending);
            } else {
                IERC20(reflectionToken).safeTransfer(lock.operator, pending);
            }
            totalReflections = totalReflections.sub(pending);
        }

        lock.reflectionDebt = lock.amount.sub(lock.tokenDebt).mul(accReflectionPerShare).div(1e18);
    }

    function allowDefrost(uint256 _lockID) external payable nonReentrant {
        TokenLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");
        require(lock.unlockTime > block.timestamp, "already unlocked");
        
        _transferFee(defrostFee);
        lock.isDefrost = true;

        emit DefrostActivated(_lockID);
    }

    function pendingReflections(uint256 _lockID) external view returns (uint256 pending) {
        TokenLock storage lock = locks[_lockID];
        if(lock.amount <= lock.tokenDebt) return 0;

        uint256 reflectionAmt = availableDividendTokens();
        uint256 _accReflectionPerShare = accReflectionPerShare.add(
                reflectionAmt.sub(totalReflections).mul(1e18).div(totalLocked)
            );

        pending = lock.amount.sub(lock.tokenDebt).mul(_accReflectionPerShare).div(1e18).sub(lock.reflectionDebt);
    }

    function pendingClaims(uint256 _lockID) public view returns (uint256) {
        TokenLock storage lock = locks[_lockID];
        if(lock.unlockTime > block.timestamp) return 0;
        if(lock.amount <= lock.tokenDebt) return 0;
        if(lock.unlockRate == 0) return lock.amount.sub(lock.tokenDebt);

        uint256 multiplier = block.timestamp.sub(lock.unlockTime);
        uint256 amount = lock.unlockRate.mul(multiplier);
        if(amount > lock.amount) amount = lock.amount;

        return amount.sub(lock.tokenDebt);
    }

    function availableDividendTokens() public view returns (uint256) {
        if(address(reflectionToken) == address(0x0)) {
            return address(this).balance;
        }

        uint256 _amount = IERC20(reflectionToken).balanceOf(address(this));        
        if(reflectionToken == address(token)) {
            if(_amount < totalLocked) return 0;
            _amount = _amount.sub(totalLocked);
        }

        return _amount;
    }

    function defrost(uint256 _lockID) external nonReentrant {
        TokenLock storage lock = locks[_lockID];
        require(msg.sender == owner() || msg.sender == lock.operator, "forbidden: only owner or operator");
        require(lock.isDefrost == true, "defrost is not activated");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");
        require(lock.unlockTime > block.timestamp, "already unlocked");

        _updatePool();

        uint256 pending = lock.amount.sub(lock.tokenDebt).mul(accReflectionPerShare).div(1e18).sub(lock.reflectionDebt);
        if(pending > 0) {
            if(reflectionToken == address(0x0)) {
                payable(treasury).transfer(pending);
            } else {
                IERC20(reflectionToken).safeTransfer(treasury, pending);
            }
            totalReflections = totalReflections.sub(pending);
        }

        uint256 claimAmt = lock.amount.sub(lock.tokenDebt);
        token.transfer(lock.operator, claimAmt);

        lock.tokenDebt = lock.amount;
        lock.reflectionDebt = 0;
        totalLocked = totalLocked.sub(claimAmt);

        emit Defrosted(_lockID);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0x0), "invalid treasury");
        
        treasury = _treasury;
        emit UpdateTreasury(_treasury);
    }


    function _updatePool() internal {
        if(totalLocked > 0) {
            uint256 reflectionAmt = availableDividendTokens();

            accReflectionPerShare = accReflectionPerShare.add(
                    reflectionAmt.sub(totalReflections).mul(1e18).div(totalLocked)
                );

            totalReflections = reflectionAmt;
        }
    }

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "should pay small gas to compound or harvest");

        payable(treasury).transfer(performanceFee);
        if(msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value.sub(performanceFee));
        }
    }

    function _transferFee(uint256 fee) internal {
        require(msg.value >= fee, "not enough processing fee");
        if(msg.value > fee) {
            payable(msg.sender).transfer(msg.value.sub(fee));
        }

        uint256 _devFee = fee.mul(devRate).div(10000);
        if(_devFee > 0) {
            payable(devWallet).transfer(_devFee);
        }

        payable(treasury).transfer(fee.sub(_devFee));
    }

    receive() external payable {}
}