// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libs/IUniRouter02.sol";
import "../libs/IWETH.sol";

// BrewlabsFarm is the master of earnedToken. He can make earnedToken and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once earnedToken is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract BrewlabsFarmImpl is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool private isInitialized;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 reflectionDebt; // Reflection debt. See explanation below.
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
        uint256 duration;
        uint256 startBlock;
        uint256 bonusEndBlock;
        uint256 lastRewardBlock; // Last block number that tokens distribution occurs.
        uint256 accTokenPerShare; // Accumulated tokens per share, times 1e12. See below.
        uint256 accReflectionPerShare; // Accumulated tokens per share, times 1e12. See below.
        uint256 lastReflectionPerPoint;
        uint16 depositFee; // Deposit fee in basis points
        uint16 withdrawFee; // Deposit fee in basis points
    }

    struct SwapSetting {
        IERC20 lpToken;
        address swapRouter;
        address[] earnedToToken0;
        address[] earnedToToken1;
        address[] reflectionToToken0;
        address[] reflectionToToken1;
        bool enabled;
    }

    // The earnedToken TOKEN!
    IERC20 public earnedToken;
    // Reflection Token
    address public reflectionToken;
    uint256 public accReflectionPerPoint;
    bool public hasDividend;
    bool public autoAdjustableForRewardRate = false;

    // earnedToken tokens created per block.
    uint256 public rewardPerBlock;
    // Bonus muliplier for early earnedToken makers.
    uint256 public BONUS_MULTIPLIER;
    uint256 public PERCENT_PRECISION;
    uint256 private BLOCKS_PER_DAY;

    // Deposit Fee address
    address public feeAddress;
    address public treasury;
    uint256 public performanceFee;
    uint256 public rewardFee;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    SwapSetting[] public swapSettings;
    uint256[] public totalStaked;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when earnedToken mining starts.
    uint256 public startBlock;

    uint256 private totalEarned;
    uint256 private totalRewardStaked;
    uint256 private totalReflectionStaked;
    uint256 private totalReflections;
    uint256 private reflectionDebt;

    uint256 public paidRewards;
    uint256 private shouldTotalPaid;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event ClaimDividend(address indexed user, uint256 indexed pid, uint256 amount);
    event Compound(address indexed user, uint256 indexed pid, uint256 amount);
    event CompoundDividend(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetPool(
        uint256 pid,
        address indexed lpToken,
        uint256 allocPoint,
        uint256 duration,
        uint256 depositFee,
        uint256 withdrawFee,
        uint256 startBlock,
        uint256 endBlock
    );
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetBuyBackWallet(address indexed user, address newAddress);
    event SetPerformanceFee(uint256 fee);
    event SetRewardFee(uint256 fee);
    event SetAutoAdjustableForRewardRate(bool status);
    event UpdateEmissionRate(address indexed user, uint256 rewardPerBlock);

    mapping(IERC20 => bool) public poolExistence;

    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    constructor() {}

    /**
     * @notice Initialize index contract.
     * @param _brews: earning token
     * @param _reflectionToken: dividend token
     * @param _rewardPerBlock: reward per block
     * @param _hasDividend: dividend flag
     * @param _owner: owner address
     */
    function initialize(
        IERC20 _brews,
        address _reflectionToken,
        uint256 _rewardPerBlock,
        bool _hasDividend,
        address _owner
    ) external {
        require(!isInitialized, "Already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "Not allowed");

        // initialize default variables
        isInitialized = true;

        BONUS_MULTIPLIER = 1;
        PERCENT_PRECISION = 10000;
        BLOCKS_PER_DAY = 28800;

        performanceFee = 0.0035 ether;
        treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        feeAddress = _owner;

        earnedToken = _brews;
        reflectionToken = _reflectionToken;
        rewardPerBlock = _rewardPerBlock;
        hasDividend = _hasDividend;

        startBlock = block.number + 30 * BLOCKS_PER_DAY; // after 30 days

        _transferOwnership(_owner);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint16 _depositFee,
        uint16 _withdrawFee,
        uint256 _duration,
        bool _withUpdate
    ) external onlyOwner nonDuplicated(_lpToken) {
        require(_depositFee <= PERCENT_PRECISION, "add: invalid deposit fee basis points");
        require(_withdrawFee <= PERCENT_PRECISION, "add: invalid withdraw fee basis points");

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                duration: _duration,
                startBlock: lastRewardBlock,
                bonusEndBlock: lastRewardBlock + _duration * BLOCKS_PER_DAY,
                lastRewardBlock: lastRewardBlock,
                accTokenPerShare: 0,
                accReflectionPerShare: 0,
                lastReflectionPerPoint: 0,
                depositFee: _depositFee,
                withdrawFee: _withdrawFee
            })
        );

        swapSettings.push();
        swapSettings[swapSettings.length - 1].lpToken = _lpToken;

        totalStaked.push(0);
        emit SetPool(
            poolInfo.length - 1,
            address(_lpToken),
            _allocPoint,
            _duration,
            _depositFee,
            _withdrawFee,
            lastRewardBlock,
            lastRewardBlock + _duration * BLOCKS_PER_DAY
            );
    }

    // Update the given pool's earnedToken allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFee,
        uint16 _withdrawFee,
        uint256 _duration,
        bool _withUpdate
    ) external onlyOwner {
        require(_depositFee <= PERCENT_PRECISION, "set: invalid deposit fee basis points");
        require(_withdrawFee <= PERCENT_PRECISION, "set: invalid withdraw fee basis points");
        if (poolInfo[_pid].bonusEndBlock > block.number) {
            require(poolInfo[_pid].startBlock + _duration * BLOCKS_PER_DAY > block.number, "set: invalid duration");
        }

        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;

        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFee = _depositFee;
        poolInfo[_pid].withdrawFee = _withdrawFee;
        poolInfo[_pid].duration = _duration;

        if (poolInfo[_pid].bonusEndBlock < block.number) {
            if (!_withUpdate) updatePool(_pid);

            poolInfo[_pid].startBlock = block.number;
            poolInfo[_pid].bonusEndBlock = block.number + _duration * BLOCKS_PER_DAY;
        } else {
            poolInfo[_pid].bonusEndBlock = poolInfo[_pid].startBlock + _duration * BLOCKS_PER_DAY;
        }
        emit SetPool(
            _pid,
            address(poolInfo[_pid].lpToken),
            _allocPoint,
            _duration,
            _depositFee,
            _withdrawFee,
            poolInfo[_pid].startBlock,
            poolInfo[_pid].bonusEndBlock
            );
    }

    // Update the given pool's compound parameters. Can only be called by the owner.
    function setSwapSetting(
        uint256 _pid,
        address _uniRouter,
        address[] memory _earnedToToken0,
        address[] memory _earnedToToken1,
        address[] memory _reflectionToToken0,
        address[] memory _reflectionToToken1,
        bool _enabled
    ) external onlyOwner {
        SwapSetting storage swapSetting = swapSettings[_pid];

        swapSetting.enabled = _enabled;
        swapSetting.swapRouter = _uniRouter;
        swapSetting.earnedToToken0 = _earnedToToken0;
        swapSetting.earnedToToken1 = _earnedToToken1;
        swapSetting.reflectionToToken0 = _reflectionToToken0;
        swapSetting.reflectionToToken1 = _reflectionToToken1;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to, uint256 _endBlock) public view returns (uint256) {
        if (_from > _endBlock) return 0;
        if (_to > _endBlock) {
            return (_endBlock - _from) * BONUS_MULTIPLIER;
        }

        return (_to - _from) * BONUS_MULTIPLIER;
    }

    // View function to see pending earnedToken on frontend.
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number, pool.bonusEndBlock);
            uint256 reward = (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
            accTokenPerShare += (reward * 1e12) / lpSupply;
        }
        return (user.amount * accTokenPerShare) / 1e12 - user.rewardDebt;
    }

    function pendingReflections(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accReflectionPerShare = pool.accReflectionPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (reflectionToken == address(pool.lpToken)) lpSupply = totalReflectionStaked;
        if (block.number > pool.lastRewardBlock && lpSupply > 0 && hasDividend && totalAllocPoint > 0) {
            uint256 reflectionAmt = availableDividendTokens();
            if (reflectionAmt > totalReflections) {
                reflectionAmt -= totalReflections;
            } else {
                reflectionAmt = 0;
            }

            uint256 _accReflectionPerPoint = accReflectionPerPoint + (reflectionAmt * 1e12) / totalAllocPoint;

            accReflectionPerShare = pool.accReflectionPerShare
                + ((pool.allocPoint * (_accReflectionPerPoint - pool.lastReflectionPerPoint)) / lpSupply);
        }
        return (user.amount * accReflectionPerShare) / 1e12 - user.reflectionDebt;
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
        if (address(pool.lpToken) == address(earnedToken)) lpSupply = totalRewardStaked;
        if (address(pool.lpToken) == reflectionToken) lpSupply = totalReflectionStaked;
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number, pool.bonusEndBlock);
        uint256 reward = (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
        pool.accTokenPerShare += (reward * 1e12) / lpSupply;

        if (hasDividend) {
            uint256 reflectionAmt = availableDividendTokens();
            if (reflectionAmt > totalReflections) {
                reflectionAmt -= totalReflections;
            } else {
                reflectionAmt = 0;
            }

            accReflectionPerPoint += (reflectionAmt * 1e12) / totalAllocPoint;
            pool.accReflectionPerShare +=
                (pool.allocPoint * (accReflectionPerPoint - pool.lastReflectionPerPoint)) / (lpSupply);

            pool.lastReflectionPerPoint = accReflectionPerPoint;

            totalReflections += reflectionAmt;
        }

        pool.lastRewardBlock = block.number;
        shouldTotalPaid = shouldTotalPaid + reward;
    }

    // Deposit LP tokens to BrewlabsFarm for earnedToken allocation.
    function deposit(uint256 _pid, uint256 _amount) external payable nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _transferPerformanceFee();
        massUpdatePools();

        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
            if (pending > 0) {
                require(availableRewardTokens() >= pending, "Insufficient reward tokens");
                paidRewards = paidRewards + pending;

                pending = (pending * (PERCENT_PRECISION - rewardFee)) / PERCENT_PRECISION;
                safeTokenTransfer(msg.sender, pending);
                if (totalEarned > pending) {
                    totalEarned = totalEarned - pending;
                } else {
                    totalEarned = 0;
                }
                emit Claim(msg.sender, _pid, pending);
            }

            uint256 pendingReflection = (user.amount * pool.accReflectionPerShare) / 1e12 - user.reflectionDebt;
            if (pendingReflection > 0 && hasDividend) {
                totalReflections -= pendingReflection;
                pendingReflection = _estimateDividendAmount(pendingReflection);
                if (address(reflectionToken) == address(0x0)) {
                    payable(msg.sender).transfer(pendingReflection);
                } else {
                    IERC20(reflectionToken).safeTransfer(msg.sender, pendingReflection);
                }
                emit ClaimDividend(msg.sender, _pid, pendingReflection);
            }
        }

        uint256 realAmount = _amount;
        if (_amount > 0) {
            uint256 beforeAmt = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 afterAmt = pool.lpToken.balanceOf(address(this));
            uint256 amount = afterAmt - beforeAmt;

            if (pool.depositFee > 0) {
                uint256 depositFee = (amount * pool.depositFee) / PERCENT_PRECISION;
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount += amount - depositFee;
                realAmount -= depositFee;
            } else {
                user.amount = user.amount + amount;
            }

            _calculateTotalStaked(_pid, pool.lpToken, amount, true);
        }

        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;
        user.reflectionDebt = (user.amount * pool.accReflectionPerShare) / 1e12;

        emit Deposit(msg.sender, _pid, realAmount);

        if (pool.bonusEndBlock <= block.number) {
            totalAllocPoint = totalAllocPoint - pool.allocPoint;
            pool.allocPoint = 0;
            rewardPerBlock = 0;
            emit UpdateEmissionRate(msg.sender, rewardPerBlock);
        } else if ((rewardFee > 0 && _amount > 0) || autoAdjustableForRewardRate) {
            _updateRewardRate();
        }
    }

    // Withdraw LP tokens from BrewlabsFarm.
    function withdraw(uint256 _pid, uint256 _amount) external payable nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(_amount > 0, "Amount should be greator than 0");

        _transferPerformanceFee();

        if (pool.bonusEndBlock < block.number) {
            massUpdatePools();

            totalAllocPoint = totalAllocPoint - pool.allocPoint;
            pool.allocPoint = 0;
            rewardPerBlock = 0;
            emit UpdateEmissionRate(msg.sender, rewardPerBlock);
        } else {
            updatePool(_pid);
        }

        uint256 pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            paidRewards = paidRewards + pending;

            pending = (pending * (PERCENT_PRECISION - rewardFee)) / PERCENT_PRECISION;
            safeTokenTransfer(msg.sender, pending);
            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            emit Claim(msg.sender, _pid, pending);
        }

        uint256 pendingReflection = (user.amount * pool.accReflectionPerShare) / 1e12 - user.reflectionDebt;
        if (pendingReflection > 0 && hasDividend) {
            totalReflections -= pendingReflection;
            pendingReflection = _estimateDividendAmount(pendingReflection);
            if (address(reflectionToken) == address(0x0)) {
                payable(msg.sender).transfer(pendingReflection);
            } else {
                IERC20(reflectionToken).safeTransfer(msg.sender, pendingReflection);
            }
            emit ClaimDividend(msg.sender, _pid, pendingReflection);
        }

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            if (pool.withdrawFee > 0) {
                uint256 withdrawFee = (_amount * pool.withdrawFee) / PERCENT_PRECISION;
                pool.lpToken.safeTransfer(feeAddress, withdrawFee);
                pool.lpToken.safeTransfer(address(msg.sender), _amount - withdrawFee);
            } else {
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
            }

            _calculateTotalStaked(_pid, pool.lpToken, _amount, false);
        }
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;
        user.reflectionDebt = (user.amount * pool.accReflectionPerShare) / 1e12;

        emit Withdraw(msg.sender, _pid, _amount);

        if (autoAdjustableForRewardRate) _updateRewardRate();
    }

    function claimReward(uint256 _pid) external payable nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount == 0) return;

        _transferPerformanceFee();
        updatePool(_pid);

        uint256 pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            paidRewards = paidRewards + pending;

            pending = (pending * (PERCENT_PRECISION - rewardFee)) / PERCENT_PRECISION;
            safeTokenTransfer(msg.sender, pending);
            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            emit Claim(msg.sender, _pid, pending);
        }
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;
    }

    function compoundReward(uint256 _pid) external payable nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        SwapSetting memory swapSetting = swapSettings[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount == 0) return;
        if (!swapSetting.enabled) return;

        _transferPerformanceFee();
        updatePool(_pid);

        uint256 pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            paidRewards = paidRewards + pending;

            pending = (pending * (PERCENT_PRECISION - rewardFee)) / PERCENT_PRECISION;
            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            emit Compound(msg.sender, _pid, pending);
        }

        if (address(earnedToken) != address(pool.lpToken)) {
            uint256 tokenAmt = pending / 2;
            uint256 tokenAmt0 = tokenAmt;
            address token0 = address(earnedToken);
            if (swapSetting.earnedToToken0.length > 0) {
                token0 = swapSetting.earnedToToken0[swapSetting.earnedToToken0.length - 1];
                tokenAmt0 = _safeSwap(swapSetting.swapRouter, tokenAmt, swapSetting.earnedToToken0, address(this));
            }
            uint256 tokenAmt1 = tokenAmt;
            address token1 = address(earnedToken);
            if (swapSetting.earnedToToken1.length > 0) {
                token1 = swapSetting.earnedToToken1[swapSetting.earnedToToken1.length - 1];
                tokenAmt1 = _safeSwap(swapSetting.swapRouter, tokenAmt, swapSetting.earnedToToken1, address(this));
            }

            uint256 beforeAmt = pool.lpToken.balanceOf(address(this));
            _addLiquidity(swapSetting.swapRouter, token0, token1, tokenAmt0, tokenAmt1, address(this));
            uint256 afterAmt = pool.lpToken.balanceOf(address(this));

            pending = afterAmt - beforeAmt;
        }

        user.amount = user.amount + pending;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;
        user.reflectionDebt = user.reflectionDebt + (pending * pool.accReflectionPerShare) / 1e12;

        _calculateTotalStaked(_pid, pool.lpToken, pending, true);
        emit Deposit(msg.sender, _pid, pending);
    }

    function claimDividend(uint256 _pid) external payable nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount == 0) return;
        if (!hasDividend) return;

        _transferPerformanceFee();
        updatePool(_pid);

        uint256 pendingReflection = (user.amount * pool.accReflectionPerShare) / 1e12 - user.reflectionDebt;
        if (pendingReflection > 0) {
            totalReflections = totalReflections - pendingReflection;
            pendingReflection = _estimateDividendAmount(pendingReflection);
            if (address(reflectionToken) == address(0x0)) {
                payable(msg.sender).transfer(pendingReflection);
            } else {
                IERC20(reflectionToken).safeTransfer(msg.sender, pendingReflection);
            }
            emit ClaimDividend(msg.sender, _pid, pendingReflection);
        }

        user.reflectionDebt = (user.amount * pool.accReflectionPerShare) / 1e12;
    }

    function compoundDividend(uint256 _pid) external payable nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        SwapSetting memory swapSetting = swapSettings[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount == 0) return;
        if (!hasDividend) return;

        _transferPerformanceFee();
        updatePool(_pid);

        uint256 _pending = (user.amount * pool.accReflectionPerShare) / 1e12 - user.reflectionDebt;
        uint256 pending = _estimateDividendAmount(_pending);
        totalReflections = totalReflections - _pending;
        emit CompoundDividend(msg.sender, _pid, pending);

        if (reflectionToken != address(pool.lpToken)) {
            if (reflectionToken == address(0x0)) {
                address wethAddress = IUniRouter02(swapSetting.swapRouter).WETH();
                IWETH(wethAddress).deposit{value: pending}();
            }

            uint256 tokenAmt = pending / 2;
            uint256 tokenAmt0 = tokenAmt;
            address token0 = reflectionToken;
            if (swapSetting.reflectionToToken0.length > 0) {
                token0 = swapSetting.reflectionToToken0[swapSetting.reflectionToToken0.length - 1];
                tokenAmt0 = _safeSwap(swapSetting.swapRouter, tokenAmt, swapSetting.reflectionToToken0, address(this));
            }
            uint256 tokenAmt1 = tokenAmt;
            address token1 = reflectionToken;
            if (swapSetting.reflectionToToken1.length > 0) {
                token0 = swapSetting.reflectionToToken1[swapSetting.reflectionToToken1.length - 1];
                tokenAmt1 = _safeSwap(swapSetting.swapRouter, tokenAmt, swapSetting.reflectionToToken1, address(this));
            }

            uint256 beforeAmt = pool.lpToken.balanceOf(address(this));
            _addLiquidity(swapSetting.swapRouter, token0, token1, tokenAmt0, tokenAmt1, address(this));
            uint256 afterAmt = pool.lpToken.balanceOf(address(this));

            pending = afterAmt - beforeAmt;
        }

        user.amount = user.amount + pending;
        user.rewardDebt = user.rewardDebt + (pending * pool.accTokenPerShare) / 1e12;
        user.reflectionDebt = (user.amount * pool.accReflectionPerShare) / 1e12;

        _calculateTotalStaked(_pid, pool.lpToken, pending, true);
        emit Deposit(msg.sender, _pid, pending);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.reflectionDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        _calculateTotalStaked(_pid, pool.lpToken, amount, false);

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "should pay small gas");

        payable(treasury).transfer(performanceFee);
        if (msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value - performanceFee);
        }
    }

    function _calculateTotalStaked(uint256 _pid, IERC20 _lpToken, uint256 _amount, bool _deposit) internal {
        if (_deposit) {
            totalStaked[_pid] = totalStaked[_pid] + _amount;
            if (address(_lpToken) == address(earnedToken)) {
                totalRewardStaked = totalRewardStaked + _amount;
            }
            if (address(_lpToken) == reflectionToken) {
                totalReflectionStaked = totalReflectionStaked + _amount;
            }
        } else {
            totalStaked[_pid] = totalStaked[_pid] - _amount;
            if (address(_lpToken) == address(earnedToken)) {
                if (totalRewardStaked < _amount) totalRewardStaked = _amount;
                totalRewardStaked = totalRewardStaked - _amount;
            }
            if (address(_lpToken) == reflectionToken) {
                if (totalReflectionStaked < _amount) totalReflectionStaked = _amount;
                totalReflectionStaked = totalReflectionStaked - _amount;
            }
        }
    }

    function _estimateDividendAmount(uint256 amount) internal view returns (uint256) {
        uint256 dTokenBal = availableDividendTokens();
        if (amount > totalReflections) amount = totalReflections;
        if (amount > dTokenBal) amount = dTokenBal;
        return amount;
    }

    /**
     * @notice Available amount of reward token
     */
    function availableRewardTokens() public view returns (uint256) {
        if (address(earnedToken) == reflectionToken && hasDividend) return totalEarned;

        uint256 _amount = earnedToken.balanceOf(address(this));
        return _amount - totalRewardStaked;
    }

    /**
     * @notice Available amount of reflection token
     */
    function availableDividendTokens() public view returns (uint256) {
        if (hasDividend == false) return 0;
        if (address(reflectionToken) == address(0x0)) {
            return address(this).balance;
        }

        uint256 _amount = IERC20(reflectionToken).balanceOf(address(this));
        if (address(reflectionToken) == address(earnedToken)) {
            if (_amount < totalEarned) return 0;
            _amount = _amount - totalEarned;
        }
        return _amount - totalReflectionStaked;
    }

    function insufficientRewards() external view returns (uint256) {
        uint256 adjustedShouldTotalPaid = shouldTotalPaid;
        uint256 remainRewards = availableRewardTokens() + paidRewards;

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            PoolInfo memory pool = poolInfo[pid];
            if (startBlock == 0) {
                adjustedShouldTotalPaid +=
                    (rewardPerBlock * pool.allocPoint * pool.duration * BLOCKS_PER_DAY) / totalAllocPoint;
            } else {
                uint256 multiplier = getMultiplier(pool.lastRewardBlock, pool.bonusEndBlock, pool.bonusEndBlock);
                adjustedShouldTotalPaid += (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
            }
        }

        if (remainRewards >= adjustedShouldTotalPaid) return 0;

        return adjustedShouldTotalPaid - remainRewards;
    }

    // Safe earnedToken transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = earnedToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBal) {
            transferSuccess = earnedToken.transfer(_to, tokenBal);
        } else {
            transferSuccess = earnedToken.transfer(_to, _amount);
        }
        require(transferSuccess, "safeTokenTransfer: transfer failed");
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setPerformanceFee(uint256 _fee) external {
        require(msg.sender == treasury, "setPerformanceFee: FORBIDDEN");

        performanceFee = _fee;
        emit SetPerformanceFee(_fee);
    }

    function setRewardFee(uint256 _fee) external onlyOwner {
        require(_fee < PERCENT_PRECISION, "setRewardFee: invalid percentage");

        rewardFee = _fee;
        emit SetRewardFee(_fee);
    }

    function setBuyBackWallet(address _addr) external {
        require(msg.sender == treasury, "setBuyBackWallet: FORBIDDEN");
        treasury = _addr;
        emit SetBuyBackWallet(msg.sender, _addr);
    }

    function setAutoAdjustableForRewardRate(bool _status) external onlyOwner {
        autoAdjustableForRewardRate = _status;
        emit SetAutoAdjustableForRewardRate(_status);
    }

    //Earning Token has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _rewardPerBlock) external onlyOwner {
        massUpdatePools();
        rewardPerBlock = _rewardPerBlock;
        emit UpdateEmissionRate(msg.sender, _rewardPerBlock);
    }

    function updateStartBlock(uint256 _startBlock) external onlyOwner {
        require(startBlock > block.number, "farm is running now");
        require(_startBlock > block.number, "should be greater than current block");

        startBlock = _startBlock;
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            poolInfo[pid].startBlock = startBlock;
            poolInfo[pid].lastRewardBlock = startBlock;
            poolInfo[pid].bonusEndBlock = startBlock + poolInfo[pid].duration * BLOCKS_PER_DAY;
        }
    }

    /**
     * @notice Deposit reward token
     * @dev Only call by owner. Needs to be for deposit of reward token when reflection token is same with reward token.
     */
    function depositRewards(uint256 _amount) external nonReentrant {
        require(_amount > 0);

        uint256 beforeAmt = earnedToken.balanceOf(address(this));
        earnedToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = earnedToken.balanceOf(address(this));

        totalEarned = totalEarned + afterAmt - beforeAmt;
    }

    function increaseEmissionRate(uint256 _amount) external onlyOwner {
        require(startBlock > 0, "pool is not started");
        require(_amount > 0, "invalid amount");

        uint256 bonusEndBlock = 0;
        for (uint256 i = 0; i < poolInfo.length; i++) {
            if (bonusEndBlock < poolInfo[i].bonusEndBlock) {
                bonusEndBlock = poolInfo[i].bonusEndBlock;
            }
        }
        require(bonusEndBlock > block.number, "pool was already finished");

        massUpdatePools();

        uint256 beforeAmt = earnedToken.balanceOf(address(this));
        earnedToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = earnedToken.balanceOf(address(this));

        totalEarned = totalEarned + afterAmt - beforeAmt;
        _updateRewardRate();
    }

    function _updateRewardRate() internal {
        uint256 bonusEndBlock = 0;
        for (uint256 i = 0; i < poolInfo.length; i++) {
            if (bonusEndBlock < poolInfo[i].bonusEndBlock) {
                bonusEndBlock = poolInfo[i].bonusEndBlock;
            }
        }
        if (bonusEndBlock <= block.number) return;

        uint256 remainRewards = availableRewardTokens() + paidRewards;
        if (remainRewards > shouldTotalPaid) {
            remainRewards = remainRewards - shouldTotalPaid;

            uint256 remainBlocks = bonusEndBlock - block.number;
            rewardPerBlock = remainRewards / remainBlocks;
            emit UpdateEmissionRate(msg.sender, rewardPerBlock);
        }
    }

    function emergencyWithdrawRewards(uint256 _amount) external onlyOwner {
        if (_amount == 0) {
            uint256 amount = earnedToken.balanceOf(address(this));
            safeTokenTransfer(msg.sender, amount);
        } else {
            safeTokenTransfer(msg.sender, _amount);
        }
    }

    function emergencyWithdrawReflections() external onlyOwner {
        if (address(reflectionToken) == address(0x0)) {
            uint256 amount = address(this).balance;
            payable(address(msg.sender)).transfer(amount);
        } else {
            uint256 amount = IERC20(reflectionToken).balanceOf(address(this));
            IERC20(reflectionToken).transfer(msg.sender, amount);
        }
    }

    function transferToHarvest() external onlyOwner {
        if (hasDividend || address(earnedToken) == reflectionToken) return;

        if (reflectionToken == address(0x0)) {
            payable(treasury).transfer(address(this).balance);
        } else {
            uint256 _amount = IERC20(reflectionToken).balanceOf(address(this));
            IERC20(reflectionToken).safeTransfer(treasury, _amount);
        }
    }

    function recoverWrongToken(address _token) external onlyOwner {
        require(
            _token != address(earnedToken) && _token != reflectionToken,
            "cannot recover reward token or reflection token"
        );
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

    function _safeSwap(address _uniRouter, uint256 _amountIn, address[] memory _path, address _to)
        internal
        returns (uint256)
    {
        uint256 beforeAmt = IERC20(_path[_path.length - 1]).balanceOf(address(this));
        IERC20(_path[0]).safeApprove(_uniRouter, _amountIn);
        IUniRouter02(_uniRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn, 0, _path, _to, block.timestamp + 600
        );
        uint256 afterAmt = IERC20(_path[_path.length - 1]).balanceOf(address(this));
        return afterAmt - beforeAmt;
    }

    function _addLiquidity(
        address _uniRouter,
        address _token0,
        address _token1,
        uint256 _tokenAmt0,
        uint256 _tokenAmt1,
        address _to
    ) internal returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        IERC20(_token0).safeIncreaseAllowance(_uniRouter, _tokenAmt0);
        IERC20(_token1).safeIncreaseAllowance(_uniRouter, _tokenAmt1);

        (amountA, amountB, liquidity) = IUniRouter02(_uniRouter).addLiquidity(
            _token0, _token1, _tokenAmt0, _tokenAmt1, 0, 0, _to, block.timestamp + 600
        );

        IERC20(_token0).safeApprove(_uniRouter, uint256(0));
        IERC20(_token1).safeApprove(_uniRouter, uint256(0));
    }

    receive() external payable {}
}
