// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libs/IUniRouter02.sol";
import "../libs/IWETH.sol";

interface WhiteList {
    function whitelisted(address _address) external view returns (bool);
}

contract BrewlabsLockupImpl is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool private isInitialized;

    uint256 private PERCENT_PRECISION;
    uint256 private BLOCKS_PER_DAY;
    uint256 public PRECISION_FACTOR;
    uint256 private MAX_STAKES;

    // The staked token
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    // The dividend token of staking token
    address public dividendToken;

    uint256 public duration; // 365 days
    // The block number when staking starts.
    uint256 public startBlock;
    // The block number when staking ends.
    uint256 public bonusEndBlock;
    // Accrued token per share
    uint256 public accDividendPerShare;
    // Whether a limit is set for users

    address public walletA;
    address public treasury;
    uint256 public performanceFee;

    address public factory;
    address public deployer;
    address public operator;

    bool public hasUserLimit;
    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;
    address public whiteList;

    bool public activeEmergencyWithdraw;

    // swap router and path, slipPage
    uint256 public slippageFactor;
    uint256 public slippageFactorUL;
    address public uniRouterAddress;
    address[] public reflectionToStakedPath;
    address[] public earnedToStakedPath;

    struct Stake {
        uint8 stakeType;
        uint256 amount; // amount to stake
        uint256 duration; // the lockup duration of the stake
        uint256 end; // when does the staking period end
        uint256 rewardDebt; // Reward debt
        uint256 reflectionDebt; // Reflection debt
    }

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 locked;
        uint256 available;
        uint256 firstIndex;
    }

    mapping(address => Stake[]) public userStakes;
    mapping(address => UserInfo) public userStaked;

    uint256 public totalStaked;
    uint256 private totalEarned;
    uint256 private totalReflections;
    uint256 private reflections;

    uint256 public paidRewards;
    uint256 private shouldTotalPaid;

    struct Lockup {
        uint8 stakeType;
        uint256 duration;
        uint256 depositFee;
        uint256 withdrawFee;
        uint256 rate;
        uint256 accTokenPerShare;
        uint256 lastRewardBlock;
        uint256 totalStaked;
        uint256 totalStakedLimit;
    }

    Lockup[] public lockups;

    event Deposit(address indexed user, uint256 stakeType, uint256 amount);
    event Withdraw(address indexed user, uint256 stakeType, uint256 amount);
    event Claim(address indexed user, uint256 stakeType, uint256 amount);
    event ClaimDividend(address indexed user, uint256 stakeType, uint256 amount);
    event Compound(address indexed user, uint256 stakeType, uint256 amount);
    event CompoundDividend(address indexed user, uint256 stakeType, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);
    event SetEmergencyWithdrawStatus(bool status);

    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event LockupUpdated(uint8 _type, uint256 _duration, uint256 _fee0, uint256 _fee1, uint256 _rate);
    event RewardsStop(uint256 blockNumber);
    event EndBlockChanged(uint256 blockNumber);
    event UpdatePoolLimit(uint256 poolLimitPerUser, bool hasLimit);

    event ServiceInfoChanged(address _addr, uint256 _fee);
    event DurationChanged(uint256 _duration);
    event OperatorTransferred(address oldOperator, address newOperator);
    event SetWhiteList(address _whitelist);

    event SetSettings(
        uint256 _slippageFactor, address _uniRouter, address[] _path0, address[] _path1, address _walletA
    );

    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == operator, "caller is not owner or operator");
        _;
    }

    constructor() {}

    /**
     * @notice Initialize the contract
     * @param _stakingToken: staked token address
     * @param _rewardToken: earned token address
     * @param _dividendToken: reflection token address
     * @param _uniRouter: uniswap router address for swap tokens
     * @param _earnedToStakedPath: swap path to compound (earned -> staking path)
     * @param _reflectionToStakedPath: swap path to compound (reflection -> staking path)
     * @param _owner: owner address
     * @param _deployer: deployer address
     */
    function initialize(
        IERC20 _stakingToken,
        IERC20 _rewardToken,
        address _dividendToken,
        address _uniRouter,
        address[] memory _earnedToStakedPath,
        address[] memory _reflectionToStakedPath,
        address _owner,
        address _deployer
    ) external {
        require(!isInitialized, "Already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "Not allowed");

        // Make this contract initialized
        isInitialized = true;

        PERCENT_PRECISION = 10000;
        BLOCKS_PER_DAY = 28800;
        MAX_STAKES = 256;

        duration = 365; // 365 days
        slippageFactor = 8000; // 20% default slippage tolerance
        slippageFactorUL = 9950;

        treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        performanceFee = 0.0035 ether;

        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        dividendToken = _dividendToken;

        factory = msg.sender;
        deployer = _deployer;
        operator = _deployer;
        walletA = _deployer;

        uint256 decimalsRewardToken = uint256(IERC20Metadata(address(rewardToken)).decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");
        PRECISION_FACTOR = uint256(10 ** (40 - decimalsRewardToken));

        uniRouterAddress = _uniRouter;
        earnedToStakedPath = _earnedToStakedPath;
        reflectionToStakedPath = _reflectionToStakedPath;
        whiteList = address(0x0);

        _transferOwnership(_owner);
    }

    /**
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     * @param _stakeType: lockup index
     */
    function deposit(uint256 _amount, uint8 _stakeType) external payable nonReentrant {
        require(startBlock > 0 && startBlock < block.number, "Staking hasn't started yet");
        require(_amount > 0, "Amount should be greator than 0");
        require(_stakeType < lockups.length, "Invalid stake type");
        if (whiteList != address(0x0)) {
            require(WhiteList(whiteList).whitelisted(msg.sender), "not whitelisted");
        }

        _transferPerformanceFee();
        _updatePool(_stakeType);

        UserInfo storage user = userStaked[msg.sender];
        Stake[] storage stakes = userStakes[msg.sender];
        Lockup storage lockup = lockups[_stakeType];

        if (lockup.totalStakedLimit > 0) {
            require(lockup.totalStaked < lockup.totalStakedLimit, "Total staked limit exceeded");

            if (lockup.totalStaked + _amount > lockup.totalStakedLimit) {
                _amount = lockup.totalStakedLimit - lockup.totalStaked;
            }
        }

        uint256 pending = 0;
        uint256 pendingReflection = 0;
        for (uint256 j = user.firstIndex; j < stakes.length; j++) {
            Stake storage stake = stakes[j];
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;

            pendingReflection =
                pendingReflection + ((stake.amount * accDividendPerShare) / PRECISION_FACTOR - stake.reflectionDebt);

            uint256 _pending = (stake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR - stake.rewardDebt;
            pending = pending + _pending;

            stake.rewardDebt = (stake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR;
            stake.reflectionDebt = (stake.amount * accDividendPerShare) / PRECISION_FACTOR;
        }

        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            rewardToken.safeTransfer(address(msg.sender), pending);
            _updateEarned(pending);
            paidRewards = paidRewards + pending;
            emit Claim(msg.sender, _stakeType, pending);
        }

        if (pendingReflection > 0) {
            uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
            totalReflections = totalReflections - pendingReflection;
            _transferToken(dividendToken, msg.sender, _pendingReflection);
            emit ClaimDividend(msg.sender, _stakeType, _pendingReflection);
        }

        uint256 beforeAmount = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 afterAmount = stakingToken.balanceOf(address(this));
        uint256 realAmount = afterAmount - beforeAmount;
        if (realAmount > _amount) realAmount = _amount;

        if (hasUserLimit) {
            require(realAmount + user.amount <= poolLimitPerUser, "User amount above limit");
        }
        if (lockup.depositFee > 0) {
            uint256 fee = (realAmount * lockup.depositFee) / PERCENT_PRECISION;
            if (fee > 0) {
                stakingToken.safeTransfer(walletA, fee);
                realAmount = realAmount - fee;
            }
        }

        _addStake(_stakeType, msg.sender, lockup.duration, realAmount, user.firstIndex);

        user.amount = user.amount + realAmount;
        lockup.totalStaked = lockup.totalStaked + realAmount;
        totalStaked = totalStaked + realAmount;

        emit Deposit(msg.sender, _stakeType, realAmount);
    }

    function _addStake(uint8 _stakeType, address _account, uint256 _duration, uint256 _amount, uint256 _firstIndex)
        internal
    {
        Stake[] storage stakes = userStakes[_account];

        uint256 end = block.timestamp + _duration * 1 days;
        uint256 i = stakes.length;
        require(i < MAX_STAKES, "Max stakes");

        stakes.push(); // grow the array
        // find the spot where we can insert the current stake
        // this should make an increasing list sorted by end
        while (i != 0 && stakes[i - 1].end > end && i >= _firstIndex) {
            // shift it back one
            stakes[i] = stakes[i - 1];
            i -= 1;
        }

        Lockup storage lockup = lockups[_stakeType];

        // insert the stake
        Stake storage newStake = stakes[i];
        newStake.stakeType = _stakeType;
        newStake.duration = _duration;
        newStake.end = end;
        newStake.amount = _amount;
        newStake.rewardDebt = (newStake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR;
        newStake.reflectionDebt = (newStake.amount * accDividendPerShare) / PRECISION_FACTOR;
    }

    /**
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     * @param _stakeType: lockup index
     */
    function withdraw(uint256 _amount, uint8 _stakeType) external payable nonReentrant {
        require(_amount > 0, "Amount should be greator than 0");
        require(_stakeType < lockups.length, "Invalid stake type");

        _transferPerformanceFee();
        _updatePool(_stakeType);

        UserInfo storage user = userStaked[msg.sender];
        Stake[] storage stakes = userStakes[msg.sender];
        Lockup storage lockup = lockups[_stakeType];

        bool bUpdatable = true;
        uint256 firstIndex = user.firstIndex;

        uint256 pending = 0;
        uint256 pendingReflection = 0;
        uint256 remained = _amount;
        for (uint256 j = user.firstIndex; j < stakes.length; j++) {
            Stake storage stake = stakes[j];
            if (bUpdatable && stake.amount == 0) firstIndex = j;
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;
            if (remained == 0) break;

            uint256 _pending = (stake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR - stake.rewardDebt;
            pendingReflection =
                pendingReflection + ((stake.amount * accDividendPerShare) / PRECISION_FACTOR - stake.reflectionDebt);

            pending = pending + _pending;
            if (stake.end < block.timestamp || bonusEndBlock < block.number) {
                if (stake.amount > remained) {
                    stake.amount = stake.amount - remained;
                    remained = 0;
                } else {
                    remained = remained - stake.amount;
                    stake.amount = 0;
                    if (bUpdatable) firstIndex = j;
                }
            }

            stake.rewardDebt = (stake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR;
            stake.reflectionDebt = (stake.amount * accDividendPerShare) / PRECISION_FACTOR;

            if (stake.amount > 0) bUpdatable = false;
        }

        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            rewardToken.safeTransfer(address(msg.sender), pending);
            _updateEarned(pending);
            paidRewards = paidRewards + pending;
            emit Claim(msg.sender, _stakeType, pending);
        }

        if (pendingReflection > 0) {
            uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
            totalReflections = totalReflections - pendingReflection;
            _transferToken(dividendToken, msg.sender, _pendingReflection);
            emit ClaimDividend(msg.sender, _stakeType, _pendingReflection);
        }

        uint256 realAmount = _amount - remained;
        user.firstIndex = firstIndex;
        user.amount = user.amount - realAmount;
        lockup.totalStaked = lockup.totalStaked - realAmount;
        totalStaked = totalStaked - realAmount;

        if (realAmount > 0) {
            emit Withdraw(msg.sender, _stakeType, realAmount);

            if (lockup.withdrawFee > 0) {
                uint256 fee = (realAmount * lockup.withdrawFee) / PERCENT_PRECISION;
                stakingToken.safeTransfer(walletA, fee);
                realAmount = realAmount - fee;
            }

            stakingToken.safeTransfer(address(msg.sender), realAmount);
        }
    }

    function claimReward(uint8 _stakeType) external payable nonReentrant {
        if (_stakeType >= lockups.length) return;
        if (startBlock == 0) return;

        _transferPerformanceFee();
        _updatePool(_stakeType);

        UserInfo storage user = userStaked[msg.sender];
        Stake[] storage stakes = userStakes[msg.sender];
        Lockup storage lockup = lockups[_stakeType];

        uint256 pending = 0;
        for (uint256 j = user.firstIndex; j < stakes.length; j++) {
            Stake storage stake = stakes[j];
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;

            uint256 _pending = (stake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR - stake.rewardDebt;
            pending = pending + _pending;

            stake.rewardDebt = (stake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR;
        }

        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            rewardToken.safeTransfer(address(msg.sender), pending);
            _updateEarned(pending);
            paidRewards = paidRewards + pending;
            emit Claim(msg.sender, _stakeType, pending);
        }
    }

    function claimDividend(uint8 _stakeType) external payable nonReentrant {
        if (_stakeType >= lockups.length) return;
        if (startBlock == 0) return;

        _transferPerformanceFee();
        _updatePool(_stakeType);

        UserInfo storage user = userStaked[msg.sender];
        Stake[] storage stakes = userStakes[msg.sender];

        uint256 pendingReflection = 0;
        for (uint256 j = user.firstIndex; j < stakes.length; j++) {
            Stake storage stake = stakes[j];
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;

            pendingReflection =
                pendingReflection + ((stake.amount * accDividendPerShare) / PRECISION_FACTOR - stake.reflectionDebt);

            stake.reflectionDebt = (stake.amount * accDividendPerShare) / PRECISION_FACTOR;
        }

        if (pendingReflection > 0) {
            uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
            totalReflections = totalReflections - pendingReflection;
            emit ClaimDividend(msg.sender, _stakeType, _pendingReflection);
            _transferToken(dividendToken, msg.sender, _pendingReflection);
        }
    }

    function compoundReward(uint8 _stakeType) external payable nonReentrant {
        if (_stakeType >= lockups.length) return;
        if (startBlock == 0) return;

        _transferPerformanceFee();
        _updatePool(_stakeType);

        UserInfo storage user = userStaked[msg.sender];
        Stake[] storage stakes = userStakes[msg.sender];
        Lockup storage lockup = lockups[_stakeType];

        uint256 pending = 0;
        uint256 compounded = 0;
        for (uint256 j = user.firstIndex; j < stakes.length; j++) {
            Stake storage stake = stakes[j];
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;

            uint256 _pending = (stake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR - stake.rewardDebt;
            pending = pending + _pending;

            if (address(stakingToken) != address(rewardToken) && _pending > 0) {
                uint256 _beforeAmount = stakingToken.balanceOf(address(this));
                _safeSwap(_pending, earnedToStakedPath, address(this));
                uint256 _afterAmount = stakingToken.balanceOf(address(this));
                _pending = _afterAmount - _beforeAmount;
            }
            compounded = compounded + _pending;

            stake.amount = stake.amount + _pending;
            stake.rewardDebt = (stake.amount * lockup.accTokenPerShare) / PRECISION_FACTOR;
            stake.reflectionDebt = stake.reflectionDebt + (_pending * accDividendPerShare) / PRECISION_FACTOR;
        }

        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            _updateEarned(pending);
            paidRewards = paidRewards + pending;
            emit Compound(msg.sender, _stakeType, pending);

            user.amount = user.amount + compounded;
            lockup.totalStaked = lockup.totalStaked + compounded;
            totalStaked = totalStaked + compounded;

            emit Deposit(msg.sender, _stakeType, compounded);
        }
    }

    function compoundDividend(uint8 _stakeType) external payable nonReentrant {
        if (_stakeType >= lockups.length) return;
        if (startBlock == 0) return;

        _transferPerformanceFee();
        _updatePool(_stakeType);

        UserInfo storage user = userStaked[msg.sender];
        Stake[] storage stakes = userStakes[msg.sender];
        Lockup storage lockup = lockups[_stakeType];

        uint256 compounded = 0;
        for (uint256 j = user.firstIndex; j < stakes.length; j++) {
            Stake storage stake = stakes[j];
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;

            uint256 pending = (stake.amount * accDividendPerShare) / PRECISION_FACTOR - stake.reflectionDebt;
            uint256 _pending = estimateDividendAmount(pending);
            totalReflections = totalReflections - pending;
            emit CompoundDividend(msg.sender, _stakeType, _pending);

            if (address(stakingToken) != address(dividendToken) && _pending > 0) {
                if (address(dividendToken) == address(0x0)) {
                    address wethAddress = IUniRouter02(uniRouterAddress).WETH();
                    IWETH(wethAddress).deposit{value: _pending}();
                }

                uint256 _beforeAmount = stakingToken.balanceOf(address(this));
                _safeSwap(_pending, reflectionToStakedPath, address(this));
                uint256 _afterAmount = stakingToken.balanceOf(address(this));

                _pending = _afterAmount - _beforeAmount;
            }

            compounded = compounded + _pending;
            stake.amount = stake.amount + _pending;
            stake.rewardDebt += (_pending * lockup.accTokenPerShare) / PRECISION_FACTOR;
            stake.reflectionDebt = (stake.amount * accDividendPerShare) / PRECISION_FACTOR;
        }

        if (compounded > 0) {
            user.amount = user.amount + compounded;
            lockup.totalStaked = lockup.totalStaked + compounded;
            totalStaked = totalStaked + compounded;

            emit Deposit(msg.sender, _stakeType, compounded);
        }
    }

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "should pay small gas to compound or harvest");

        payable(treasury).transfer(performanceFee);
        if (msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value - performanceFee);
        }
    }

    /**
     * @notice Withdraw staked tokens without caring about rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw(uint8 _stakeType) external nonReentrant {
        require(activeEmergencyWithdraw, "Emergnecy withdraw not enabled");
        if (_stakeType >= lockups.length) return;

        UserInfo storage user = userStaked[msg.sender];
        Stake[] storage stakes = userStakes[msg.sender];
        Lockup storage lockup = lockups[_stakeType];

        uint256 firstIndex = user.firstIndex;
        uint256 amountToTransfer = 0;
        for (uint256 j = user.firstIndex; j < stakes.length; j++) {
            Stake storage stake = stakes[j];
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) {
                firstIndex = j;
                continue;
            }

            amountToTransfer = amountToTransfer + stake.amount;

            stake.amount = 0;
            stake.rewardDebt = 0;
            stake.reflectionDebt = 0;
            firstIndex = j;
        }

        if (amountToTransfer > 0) {
            stakingToken.safeTransfer(address(msg.sender), amountToTransfer);

            user.firstIndex = firstIndex;
            user.amount = user.amount - amountToTransfer;
            lockup.totalStaked = lockup.totalStaked - amountToTransfer;
            totalStaked = totalStaked - amountToTransfer;
        }

        emit EmergencyWithdraw(msg.sender, amountToTransfer);
    }

    function rewardPerBlock(uint8 _stakeType) external view returns (uint256) {
        if (_stakeType >= lockups.length) return 0;

        return lockups[_stakeType].rate;
    }

    /**
     * @notice Available amount of reward token
     */
    function availableRewardTokens() public view returns (uint256) {
        if (address(rewardToken) == address(dividendToken)) return totalEarned;

        uint256 _amount = rewardToken.balanceOf(address(this));
        if (address(rewardToken) == address(stakingToken)) {
            if (_amount < totalStaked) return 0;
            return _amount - totalStaked;
        }

        return _amount;
    }

    /**
     * @notice Available amount of reflection token
     */
    function availableDividendTokens() public view returns (uint256) {
        if (address(dividendToken) == address(0x0)) {
            return address(this).balance;
        }

        uint256 _amount = IERC20(dividendToken).balanceOf(address(this));

        if (address(dividendToken) == address(rewardToken)) {
            if (_amount < totalEarned) return 0;
            _amount = _amount - totalEarned;
        }

        if (address(dividendToken) == address(stakingToken)) {
            if (_amount < totalStaked) return 0;
            _amount = _amount - totalStaked;
        }

        return _amount;
    }

    function insufficientRewards() external view returns (uint256) {
        uint256 adjustedShouldTotalPaid = shouldTotalPaid;
        uint256 remainRewards = availableRewardTokens() + paidRewards;

        for (uint256 i = 0; i < lockups.length; i++) {
            if (startBlock == 0) {
                adjustedShouldTotalPaid = adjustedShouldTotalPaid + lockups[i].rate * duration * BLOCKS_PER_DAY;
            } else {
                uint256 remainBlocks = _getMultiplier(lockups[i].lastRewardBlock, bonusEndBlock);
                adjustedShouldTotalPaid = adjustedShouldTotalPaid + lockups[i].rate * remainBlocks;
            }
        }

        if (remainRewards >= adjustedShouldTotalPaid) return 0;

        return adjustedShouldTotalPaid - remainRewards;
    }

    function userInfo(uint8 _stakeType, address _account)
        external
        view
        returns (uint256 amount, uint256 available, uint256 locked)
    {
        Stake[] memory stakes = userStakes[_account];

        for (uint256 i = 0; i < stakes.length; i++) {
            Stake memory stake = stakes[i];

            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;

            amount = amount + stake.amount;
            if (block.timestamp > stake.end || bonusEndBlock < block.number) {
                available = available + stake.amount;
            } else {
                locked = locked + stake.amount;
            }
        }
    }

    /**
     * @notice View function to see pending reward on frontend.
     * @param _account: user address
     * @param _stakeType: lockup index
     * @return Pending reward for a given user
     */
    function pendingReward(address _account, uint8 _stakeType) external view returns (uint256) {
        if (_stakeType >= lockups.length || startBlock == 0) return 0;

        Stake[] memory stakes = userStakes[_account];
        Lockup memory lockup = lockups[_stakeType];

        if (lockup.totalStaked == 0) return 0;

        uint256 adjustedTokenPerShare = lockup.accTokenPerShare;
        if (block.number > lockup.lastRewardBlock && lockup.totalStaked != 0 && lockup.lastRewardBlock > 0) {
            uint256 multiplier = _getMultiplier(lockup.lastRewardBlock, block.number);
            uint256 reward = multiplier * lockup.rate;

            adjustedTokenPerShare = lockup.accTokenPerShare + (reward * PRECISION_FACTOR) / lockup.totalStaked;
        }

        uint256 pending = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            Stake memory stake = stakes[i];
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;

            pending = pending + ((stake.amount * adjustedTokenPerShare) / PRECISION_FACTOR - stake.rewardDebt);
        }
        return pending;
    }

    function pendingDividends(address _account, uint8 _stakeType) external view returns (uint256) {
        if (_stakeType >= lockups.length) return 0;
        if (startBlock == 0 || totalStaked == 0) return 0;

        Stake[] memory stakes = userStakes[_account];

        uint256 reflectionAmount = availableDividendTokens();
        if (reflectionAmount > totalReflections) {
            reflectionAmount -= totalReflections;
        } else {
            reflectionAmount = 0;
        }

        uint256 sTokenBal = totalStaked;
        uint256 eTokenBal = availableRewardTokens();
        if (address(stakingToken) == address(rewardToken)) {
            sTokenBal = sTokenBal + eTokenBal;
        }

        uint256 adjustedReflectionPerShare = accDividendPerShare + ((reflectionAmount * PRECISION_FACTOR) / sTokenBal);

        uint256 pendingReflection = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            Stake memory stake = stakes[i];
            if (stake.stakeType != _stakeType) continue;
            if (stake.amount == 0) continue;

            pendingReflection = pendingReflection
                + ((stake.amount * adjustedReflectionPerShare) / PRECISION_FACTOR - stake.reflectionDebt);
        }
        return pendingReflection;
    }

    /**
     * Admin Methods
     */
    function harvest() external onlyAdmin {
        _updatePool(0);

        if (reflections > 0) {
            _transferToken(dividendToken, walletA, estimateDividendAmount(reflections));
            totalReflections = totalReflections - reflections;
            reflections = 0;
        }
    }

    /**
     * @notice Deposit reward token
     * @dev Only call by owner. Needs to be for deposit of reward token when reflection token is same with reward token.
     */
    function depositRewards(uint256 _amount) external onlyAdmin nonReentrant {
        require(_amount > 0, "invalid amount");

        uint256 beforeAmt = rewardToken.balanceOf(address(this));
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = rewardToken.balanceOf(address(this));

        totalEarned = totalEarned + afterAmt - beforeAmt;
    }

    function increaseEmissionRate(uint8 _stakeType, uint256 _amount) external onlyAdmin {
        require(startBlock > 0, "pool is not started");
        require(bonusEndBlock > block.number, "pool was already finished");
        require(_amount > 0, "invalid amount");

        _updatePool(_stakeType);

        uint256 beforeAmt = rewardToken.balanceOf(address(this));
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = rewardToken.balanceOf(address(this));

        totalEarned = totalEarned + afterAmt - beforeAmt;

        uint256 remainRewards = availableRewardTokens() + paidRewards;
        uint256 adjustedShouldTotalPaid = shouldTotalPaid;
        for (uint256 i = 0; i < lockups.length; i++) {
            if (i == _stakeType) continue;

            if (startBlock == 0) {
                adjustedShouldTotalPaid = adjustedShouldTotalPaid + lockups[i].rate * duration * BLOCKS_PER_DAY;
            } else {
                uint256 remainBlocks = _getMultiplier(lockups[i].lastRewardBlock, bonusEndBlock);
                adjustedShouldTotalPaid = adjustedShouldTotalPaid + lockups[i].rate * remainBlocks;
            }
        }

        if (remainRewards > shouldTotalPaid) {
            remainRewards = remainRewards - adjustedShouldTotalPaid;

            uint256 remainBlocks = bonusEndBlock - block.number;
            lockups[_stakeType].rate = remainRewards / remainBlocks;
            emit LockupUpdated(
                _stakeType,
                lockups[_stakeType].duration,
                lockups[_stakeType].depositFee,
                lockups[_stakeType].withdrawFee,
                lockups[_stakeType].rate
                );
        }
    }

    /**
     * @notice Withdraw reward token
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(block.number > bonusEndBlock, "Pool is running");
        require(availableRewardTokens() >= _amount, "Insufficient reward tokens");

        rewardToken.safeTransfer(address(msg.sender), _amount);
        totalEarned = totalEarned > _amount ? totalEarned - _amount : 0;
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(rewardToken) || _tokenAddress == dividendToken, "Cannot be reward token");

        if (_tokenAddress == address(stakingToken)) {
            uint256 tokenBal = stakingToken.balanceOf(address(this));
            require(_tokenAmount <= tokenBal - totalStaked, "Insufficient balance");
        }

        if (_tokenAddress == address(0x0)) {
            payable(msg.sender).transfer(_tokenAmount);
        } else {
            IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
        }

        emit AdminTokenRecovered(_tokenAddress, _tokenAmount);
    }

    function startReward() external onlyAdmin {
        require(startBlock == 0, "Pool was already started");

        startBlock = block.number + 100;
        bonusEndBlock = startBlock + duration * BLOCKS_PER_DAY;
        for (uint256 i = 0; i < lockups.length; i++) {
            lockups[i].lastRewardBlock = startBlock;
        }

        emit NewStartAndEndBlocks(startBlock, bonusEndBlock);
    }

    function stopReward() external onlyAdmin {
        for (uint8 i = 0; i < lockups.length; i++) {
            _updatePool(i);
        }

        uint256 remainRewards = availableRewardTokens() + paidRewards;
        if (remainRewards > shouldTotalPaid) {
            remainRewards = remainRewards - shouldTotalPaid;
            rewardToken.transfer(msg.sender, remainRewards);
            _updateEarned(remainRewards);
        }

        bonusEndBlock = block.number;
        emit RewardsStop(bonusEndBlock);
    }

    function updateEndBlock(uint256 _endBlock) external onlyAdmin {
        require(startBlock > 0, "Pool is not started");
        require(bonusEndBlock > block.number, "Pool was already finished");
        require(_endBlock > block.number && _endBlock > startBlock, "Invalid end block");
        bonusEndBlock = _endBlock;
        emit EndBlockChanged(_endBlock);
    }

    /**
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
     */
    function updatePoolLimitPerUser(bool _hasUserLimit, uint256 _poolLimitPerUser) external onlyAdmin {
        if (_hasUserLimit) {
            require(_poolLimitPerUser > poolLimitPerUser, "New limit must be higher");
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            poolLimitPerUser = 0;
        }
        hasUserLimit = _hasUserLimit;

        emit UpdatePoolLimit(poolLimitPerUser, _hasUserLimit);
    }

    function updateLockup(
        uint8 _stakeType,
        uint256 _duration,
        uint256 _depositFee,
        uint256 _withdrawFee,
        uint256 _rate,
        uint256 _totalStakedLimit
    ) external onlyOwner {
        // require(block.number < startBlock, "Pool was already started");
        require(_stakeType < lockups.length, "Lockup Not found");
        require(_depositFee <= 2000, "Invalid deposit fee");
        require(_withdrawFee <= 2000, "Invalid withdraw fee");

        _updatePool(_stakeType);

        Lockup storage _lockup = lockups[_stakeType];
        _lockup.duration = _duration;
        _lockup.depositFee = _depositFee;
        _lockup.withdrawFee = _withdrawFee;
        _lockup.rate = _rate;
        _lockup.totalStakedLimit = _totalStakedLimit;

        emit LockupUpdated(_stakeType, _duration, _depositFee, _withdrawFee, _rate);
    }

    function addLockup(
        uint256 _duration,
        uint256 _depositFee,
        uint256 _withdrawFee,
        uint256 _rate,
        uint256 _totalStakedLimit
    ) external onlyOwner {
        require(_depositFee <= 2000, "Invalid deposit fee");
        require(_withdrawFee <= 2000, "Invalid withdraw fee");

        lockups.push();

        Lockup storage _lockup = lockups[lockups.length - 1];
        _lockup.stakeType = uint8(lockups.length - 1);
        _lockup.duration = _duration;
        _lockup.depositFee = _depositFee;
        _lockup.withdrawFee = _withdrawFee;
        _lockup.rate = _rate;
        _lockup.lastRewardBlock = block.number;
        _lockup.totalStakedLimit = _totalStakedLimit;

        emit LockupUpdated(uint8(lockups.length - 1), _duration, _depositFee, _withdrawFee, _rate);
    }

    function setServiceInfo(address _addr, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_addr != address(0x0), "Invalid address");

        treasury = _addr;
        performanceFee = _fee;

        emit ServiceInfoChanged(_addr, _fee);
    }

    function setEmergencyWithdraw(bool _status) external {
        require(msg.sender == treasury || msg.sender == owner(), "setEmergencyWithdraw: FORBIDDEN");

        activeEmergencyWithdraw = _status;
        emit SetEmergencyWithdrawStatus(_status);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(startBlock == 0, "Pool was already started");
        require(_duration >= 30, "lower limit reached");

        duration = _duration;
        emit DurationChanged(_duration);
    }

    function transferOperator(address _operator) external onlyAdmin {
        require(_operator != address(0x0), "invalid address");
        emit OperatorTransferred(operator, _operator);
        operator = _operator;
    }

    function setSettings(
        uint256 _slippageFactor,
        address _uniRouter,
        address[] memory _earnedToStakedPath,
        address[] memory _reflectionToStakedPath,
        address _feeAddr
    ) external onlyOwner {
        require(_slippageFactor <= slippageFactorUL, "_slippageFactor too high");
        require(_feeAddr != address(0x0), "Invalid Address");

        slippageFactor = _slippageFactor;
        uniRouterAddress = _uniRouter;
        reflectionToStakedPath = _reflectionToStakedPath;
        earnedToStakedPath = _earnedToStakedPath;
        walletA = _feeAddr;

        emit SetSettings(_slippageFactor, _uniRouter, _earnedToStakedPath, _reflectionToStakedPath, _feeAddr);
    }

    function setWhitelist(address _whitelist) external onlyOwner {
        whiteList = _whitelist;
        emit SetWhiteList(_whitelist);
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool(uint8 _stakeType) internal {
        // calc reflection rate
        if (totalStaked > 0) {
            uint256 reflectionAmount = availableDividendTokens();
            if (reflectionAmount > totalReflections) {
                reflectionAmount -= totalReflections;
            } else {
                reflectionAmount = 0;
            }

            uint256 sTokenBal = totalStaked;
            uint256 eTokenBal = availableRewardTokens();
            if (address(stakingToken) == address(rewardToken)) {
                sTokenBal = sTokenBal + eTokenBal;
            }

            accDividendPerShare += (reflectionAmount * PRECISION_FACTOR) / sTokenBal;

            reflections += (reflectionAmount * eTokenBal) / sTokenBal;
            totalReflections += reflectionAmount;
        }

        Lockup storage lockup = lockups[_stakeType];
        if (block.number <= lockup.lastRewardBlock || lockup.lastRewardBlock == 0) return;

        if (lockup.totalStaked == 0) {
            lockup.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lockup.lastRewardBlock, block.number);
        uint256 _reward = multiplier * lockup.rate;
        lockup.accTokenPerShare = lockup.accTokenPerShare + ((_reward * PRECISION_FACTOR) / lockup.totalStaked);

        lockup.lastRewardBlock = block.number;
        shouldTotalPaid = shouldTotalPaid + _reward;
    }

    function estimateDividendAmount(uint256 amount) internal view returns (uint256) {
        uint256 dTokenBal = availableDividendTokens();
        if (amount > totalReflections) amount = totalReflections;
        if (amount > dTokenBal) amount = dTokenBal;
        return amount;
    }

    /**
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to - _from;
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock - _from;
        }
    }

    function _transferToken(address _token, address _to, uint256 _amount) internal {
        if (_token == address(0x0)) {
            payable(_to).transfer(_amount);
        } else {
            IERC20(_token).transfer(_to, _amount);
        }
    }

    function _updateEarned(uint256 _amount) internal {
        totalEarned = totalEarned > _amount ? totalEarned - _amount : 0;
    }

    function _safeSwap(uint256 _amountIn, address[] memory _path, address _to) internal {
        uint256[] memory amounts = IUniRouter02(uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length - 1];

        IERC20(_path[0]).safeApprove(uniRouterAddress, _amountIn);
        IUniRouter02(uniRouterAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn, (amountOut * slippageFactor) / PERCENT_PRECISION, _path, _to, block.timestamp + 600
        );
    }

    receive() external payable {}
}
