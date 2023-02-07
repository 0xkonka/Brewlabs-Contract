// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Farm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
            //
            // We do some fancy math here. Basically, any point in time, the amount of tokens
            // entitled to a user but is pending to be distributed is:
            //
            //   pending reward = (user.amount * pool.accTokenPerShare) - user.rewardDebt
            //
            // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
            //   1. The pool's `accTokenPerShare` (and `lastRewardBlock`) gets updated.
            //   2. User receives the pending reward sent to his/her address.
            //   3. User's `amount` gets updated.
            //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. tokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that tokens distribution occurs.
        uint256 accTokenPerShare; // Accumulated tokens per share, times 1e12. See below.
    }

    // The token TOKEN!
    IERC20 public token;

    // tokens created per block.
    uint256 public rewardPerBlock;
    // Bonus muliplier for early token makers.
    uint256 public constant BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when token mining starts.
    uint256 public startBlock;

    uint256 public paidRewards;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateEmissionRate(uint256 rewardPerBlock);
    event SetPool(uint256 pid, address indexed lpToken, uint256 allocPoint);

    constructor(IERC20 _token, uint256 _rewardPerBlock) {
        token = _token;
        rewardPerBlock = _rewardPerBlock;
        startBlock = block.number + 30 * 28800; // after 30 days
    }

    mapping(IERC20 => bool) public poolExistence;

    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) external onlyOwner nonDuplicated(_lpToken) {
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({lpToken: _lpToken, allocPoint: _allocPoint, lastRewardBlock: lastRewardBlock, accTokenPerShare: 0})
        );

        emit SetPool(poolInfo.length - 1, address(_lpToken), _allocPoint);
    }

    // Update the given pool's token allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;

        emit SetPool(_pid, address(poolInfo[_pid].lpToken), _allocPoint);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        if (_from > _to) return 0;
        return (_to - _from) * BONUS_MULTIPLIER;
    }

    // View function to see pending token on frontend.
    function pending(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
            accTokenPerShare += (tokenReward * 1e12) / lpSupply;
        }
        return (user.amount * accTokenPerShare) / 1e12 - user.rewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
        pool.accTokenPerShare += (tokenReward * 1e12) / lpSupply;

        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Farm for token allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 _pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
            if (_pending > 0) {
                paidRewards = paidRewards + _pending;
                safeTokenTransfer(msg.sender, _pending);
            }
        }

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount + _amount;
            emit Deposit(msg.sender, _pid, _amount);
        }
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;
    }

    // Withdraw LP tokens from Farm.
    function withdraw(uint256 _pid, uint256 _amount) external payable nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(_amount > 0, "Amount should be greator than 0");

        updatePool(_pid);

        uint256 _pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
        if (_pending > 0) {
            paidRewards = paidRewards + _pending;
            safeTokenTransfer(msg.sender, _pending);
        }

        user.amount = user.amount - _amount;
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBal) {
            transferSuccess = token.transfer(_to, tokenBal);
        } else {
            transferSuccess = token.transfer(_to, _amount);
        }
        require(transferSuccess, "safeTokenTransfer: transfer failed");
    }

    //Token has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _rewardPerBlock) external onlyOwner {
        massUpdatePools();
        rewardPerBlock = _rewardPerBlock;
        emit UpdateEmissionRate(_rewardPerBlock);
    }

    function updateStartBlock(uint256 _startBlock) external onlyOwner {
        require(startBlock > block.number, "farm is running now");
        require(_startBlock > block.number, "should be greater than current block");

        startBlock = _startBlock;
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            poolInfo[pid].lastRewardBlock = startBlock;
        }
    }

    function emergencyWithdrawRewards(uint256 _amount) external onlyOwner {
        if (_amount == 0) {
            uint256 amount = token.balanceOf(address(this));
            safeTokenTransfer(msg.sender, amount);
        } else {
            safeTokenTransfer(msg.sender, _amount);
        }
    }

    function recoverWrongToken(address _token) external onlyOwner {
        require(poolExistence[IERC20(_token)] == false, "token is using on pool");

        if (_token == address(0x0)) {
            uint256 amount = address(this).balance;
            payable(address(msg.sender)).transfer(amount);
        } else {
            uint256 amount = IERC20(_token).balanceOf(address(this));
            if (amount > 0) {
                IERC20(_token).transfer(msg.sender, amount);
            }
        }
    }

    receive() external payable {}
}
