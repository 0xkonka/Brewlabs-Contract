// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BrewlabsPairLocker is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool private initialized = false;

    IERC20 public lpToken;
    uint256 public editFee;
    uint256 public defrostFee;
    uint256 public NONCE = 0;

    address public treasury;
    address private devWallet;
    uint256 private devRate;

    struct PairLock {
        uint256 lockID; // lockID nonce per uni pair
        uint256 lockDate; // the date the token was locked
        uint256 amount; // the amount of tokens still locked
        uint256 unlockTime; // the date the token can be withdrawn
        address operator;
        uint256 tokenDebt;
        bool isDefrost;
    }

    mapping(uint256 => PairLock) public locks;
    uint256 public totalLocked;

    event NewLock(uint256 lockID, address operator, address token, uint256 amount, uint256 unlockTime);
    event Splitlock(uint256 lockID, uint256 newLockID, address operator, uint256 amount, uint256 unlockTime);
    event AddLock(uint256 lockID, uint256 amount);
    event TransferLock(uint256 lockID, address operator);
    event Relock(uint256 lockID, uint256 unlockTime);
    event DefrostActivated(uint256 lockID);
    event Defrosted(uint256 lockID);
    event Unlocked(uint256 lockID);
    event UpdateTreasury(address addr);

    constructor() {}

    function initialize(
        address _lpToken,
        address _treasury,
        uint256 _editFee,
        uint256 _defrostFee,
        address _devWallet,
        uint256 _devRate,
        address _owner
    ) external {
        require(!initialized, "already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "not allowed");

        initialized = true;

        lpToken = IERC20(_lpToken);
        treasury = _treasury;
        editFee = _editFee;
        defrostFee = _defrostFee;

        devWallet = _devWallet;
        devRate = _devRate;

        _transferOwnership(_owner);
    }

    function newLock(address _operator, uint256 _amount, uint256 _unlockTime) external onlyOwner {
        require(_amount > 0, "Invalid amount");
        require(_unlockTime > block.timestamp, "Invalid unlock time");

        uint256 beforeAmt = lpToken.balanceOf(address(this));
        lpToken.transferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = lpToken.balanceOf(address(this));

        NONCE = NONCE.add(1);
        PairLock storage lock = locks[NONCE];
        lock.lockID = NONCE;
        lock.lockDate = block.timestamp;
        lock.amount = afterAmt.sub(beforeAmt);
        lock.tokenDebt = 0;
        lock.unlockTime = _unlockTime;
        lock.operator = _operator;
        lock.isDefrost = false;

        totalLocked = totalLocked.add(lock.amount);

        emit NewLock(lock.lockID, _operator, address(lpToken), lock.amount, _unlockTime);
    }

    function addLock(uint256 _lockID, uint256 _amount) external payable nonReentrant {
        require(_amount > 0, "Invalid amount");

        PairLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "already unlocked");
        require(lock.unlockTime > block.timestamp, "passed unlock time");

        _transferFee(editFee);

        uint256 beforeAmt = lpToken.balanceOf(address(this));
        lpToken.transferFrom(msg.sender, address(this), _amount);
        uint256 amountIn = lpToken.balanceOf(address(this)).sub(beforeAmt);

        lock.amount = lock.amount.add(amountIn);
        totalLocked = totalLocked.add(amountIn);

        emit AddLock(lock.lockID, amountIn);
    }

    function splitLock(uint256 _lockID, address _operator, uint256 _amount, uint256 _unlockTime)
        external
        payable
        nonReentrant
    {
        require(_amount > 0, "Invalid amount");
        require(_operator != address(0x0), "Invalid address");

        PairLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "already unlocked");
        require(lock.unlockTime > block.timestamp, "passed unlock time");
        require(lock.amount.sub(lock.tokenDebt) > _amount, "amount exceed original locked amount");
        require(lock.unlockTime <= _unlockTime, "unlock time should be greater than original");

        _transferFee(editFee);

        lock.amount = lock.amount.sub(_amount);

        NONCE = NONCE.add(1);

        lock = locks[NONCE];
        lock.lockID = NONCE;
        lock.lockDate = block.timestamp;
        lock.amount = _amount;
        lock.tokenDebt = 0;
        lock.unlockTime = _unlockTime;
        lock.operator = _operator;
        lock.isDefrost = false;

        emit Splitlock(_lockID, lock.lockID, _operator, _amount, _unlockTime);
    }

    function reLock(uint256 _lockID, uint256 _unlockTime) external payable nonReentrant {
        require(_unlockTime > block.timestamp, "Invalid unlock time");
        require(_unlockTime > locks[_lockID].unlockTime, "Relock time should be longer than original");

        PairLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");

        _transferFee(editFee);

        lock.lockDate = block.timestamp;
        lock.unlockTime = _unlockTime;
        lock.amount = lock.amount.sub(lock.tokenDebt);
        lock.tokenDebt = 0;
        emit Relock(_lockID, _unlockTime);
    }

    function transferLock(uint256 _lockID, address _operator) external payable {
        PairLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");
        require(lock.unlockTime > block.timestamp, "already unlocked");

        require(_operator != address(0x0) && _operator != lock.operator, "Invalid new operator");

        _transferFee(editFee);

        lock.operator = _operator;
        emit TransferLock(_lockID, _operator);
    }

    function claim(uint256 _lockID) external nonReentrant {
        PairLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "already unlocked");
        require(lock.unlockTime < block.timestamp, "cannot unlock");

        lpToken.transfer(lock.operator, lock.amount);

        lock.tokenDebt = lock.amount;
        totalLocked = totalLocked.sub(lock.amount);
        emit Unlocked(_lockID);
    }

    function allowDefrost(uint256 _lockID) external payable {
        PairLock storage lock = locks[_lockID];
        require(lock.operator == msg.sender, "not operator");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");
        require(lock.unlockTime > block.timestamp, "already unlocked");

        _transferFee(defrostFee);

        lock.isDefrost = true;
        emit DefrostActivated(_lockID);
    }

    function defrost(uint256 _lockID) external nonReentrant {
        PairLock storage lock = locks[_lockID];
        require(msg.sender == owner() || msg.sender == lock.operator, "forbidden: only owner or operator");
        require(lock.isDefrost == true, "defrost is not activated");
        require(lock.amount > lock.tokenDebt, "not enough locked amount");
        require(lock.unlockTime > block.timestamp, "already unlocked");

        lpToken.transfer(lock.operator, lock.amount);

        lock.tokenDebt = lock.amount;
        totalLocked = totalLocked.sub(lock.amount);
        emit Defrosted(_lockID);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0x0), "invalid treasury");

        treasury = _treasury;
        emit UpdateTreasury(_treasury);
    }

    function _transferFee(uint256 fee) internal {
        require(msg.value >= fee, "not enough processing fee");
        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value.sub(fee));
        }

        uint256 _devFee = fee.mul(devRate).div(10000);
        if (_devFee > 0) {
            payable(devWallet).transfer(_devFee);
        }

        payable(treasury).transfer(fee.sub(_devFee));
    }

    receive() external payable {}
}
