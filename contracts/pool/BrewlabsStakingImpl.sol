// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBrewlabsAggregator} from "../libs/IBrewlabsAggregator.sol";
import {IWETH} from "../libs/IWETH.sol";

interface WhiteList {
    function whitelisted(address _address) external view returns (bool);
}

contract BrewlabsStakingImpl is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool public isInitialized;

    uint256 private PERCENT_PRECISION;
    uint256 private BLOCKS_PER_DAY;
    uint256 public PRECISION_FACTOR;
    uint256 public PRECISION_FACTOR_REFLECTION;
    uint256 public MAX_FEE;

    address public WNATIVE;

    // The staked token
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    // The dividend token of staking token
    address public dividendToken;

    bool public hasDividend;
    bool public autoAdjustableForRewardRate = false;

    uint256 public duration;
    // The block number when staking starts.
    uint256 public startBlock;
    // The block number when staking ends.
    uint256 public bonusEndBlock;
    // tokens created per block.
    uint256 public rewardPerBlock;
    // The block number of the last pool update
    uint256 public lastRewardBlock;
    // Accrued token per share
    uint256 public accTokenPerShare;
    uint256 public accDividendPerShare;
    // The deposit & withdraw fee
    uint256 public depositFee;
    uint256 public withdrawFee;

    address public walletA;
    address public treasury;
    uint256 public performanceFee;

    address public factory;
    address public deployer;
    address public operator;

    // Whether a limit is set for users
    bool public hasUserLimit;
    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;
    address public whiteList;

    IBrewlabsAggregator public swapAggregator;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 reflectionDebt; // Reflection debt
    }

    // Info of each user that stakes tokens (stakingToken)
    mapping(address => UserInfo) public userInfo;

    uint256 public totalStaked;
    uint256 private totalEarned;
    uint256 private totalReflections;
    uint256 private reflections;

    uint256 public paidRewards;
    uint256 private shouldTotalPaid;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event ClaimDividend(address indexed user, uint256 amount);
    event Compound(address indexed user, uint256 amount);
    event CompoundDividend(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);

    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardPerBlock(uint256 rewardPerBlock);
    event RewardsStop(uint256 blockNumber);
    event EndBlockChanged(uint256 blockNumber);
    event UpdatePoolLimit(uint256 poolLimitPerUser, bool hasLimit);

    event ServiceInfoChanged(address _addr, uint256 _fee);
    event WalletAUpdated(address _addr);
    event DurationChanged(uint256 _duration);
    event OperatorTransferred(address oldOperator, address newOperator);
    event SetAutoAdjustableForRewardRate(bool status);
    event SetWhiteList(address _whitelist);
    event SetSwapAggregator(address aggregator);

    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == operator, "Caller is not owner or operator");
        _;
    }

    constructor() {}

    /**
     * @notice Initialize the contract
     * @param _stakingToken: staked token address
     * @param _rewardToken: earned token address
     * @param _dividendToken: reflection token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _depositFee: deposit fee
     * @param _withdrawFee: withdraw fee
     * @param _hasDividend: reflection available flag
     * @param _aggregator: brewlabs swap aggregator
     * @param _owner: owner address
     * @param _deployer: deployer address
     */
    function initialize(
        IERC20 _stakingToken,
        IERC20 _rewardToken,
        address _dividendToken,
        uint256 _duration,
        uint256 _rewardPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        bool _hasDividend,
        address _aggregator,
        address _owner,
        address _deployer
    ) external {
        require(!isInitialized, "Already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "Not allowed");

        // Make this contract initialized
        isInitialized = true;

        PERCENT_PRECISION = 10000;
        BLOCKS_PER_DAY = 28800;
        MAX_FEE = 2000;

        duration = 365; // 365 days
        if (_duration > 0) duration = _duration;

        treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        performanceFee = 0.0035 ether;

        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        dividendToken = _dividendToken;
        hasDividend = _hasDividend;

        rewardPerBlock = _rewardPerBlock;

        require(_depositFee <= MAX_FEE, "Invalid deposit fee");
        require(_withdrawFee <= MAX_FEE, "Invalid withdraw fee");

        depositFee = _depositFee;
        withdrawFee = _withdrawFee;

        factory = msg.sender;
        deployer = _deployer;
        operator = _deployer;

        walletA = _deployer;

        uint256 decimalsRewardToken = uint256(IERC20Metadata(address(rewardToken)).decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");
        PRECISION_FACTOR = uint256(10 ** (40 - decimalsRewardToken));

        uint256 decimalsdividendToken = 18;
        if (address(dividendToken) != address(0x0)) {
            decimalsdividendToken = uint256(IERC20Metadata(address(dividendToken)).decimals());
            require(decimalsdividendToken < 30, "Must be inferior to 30");
        }
        PRECISION_FACTOR_REFLECTION = uint256(10 ** (40 - decimalsdividendToken));

        swapAggregator = IBrewlabsAggregator(_aggregator);
        WNATIVE = swapAggregator.WNATIVE();

        _transferOwnership(_owner);
    }

    /**
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to stake (in staking token)
     */
    function deposit(uint256 _amount) external payable nonReentrant {
        require(startBlock > 0 && startBlock < block.number, "Staking hasn't started yet");
        require(_amount > 0, "Amount should be greator than 0");
        if (whiteList != address(0x0)) {
            require(WhiteList(whiteList).whitelisted(msg.sender), "not whitelisted");
        }

        UserInfo storage user = userInfo[msg.sender];

        if (hasUserLimit) {
            require(_amount + user.amount <= poolLimitPerUser, "User amount above limit");
        }

        _transferPerformanceFee();
        _updatePool();

        if (user.amount > 0) {
            uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
            if (pending > 0) {
                require(availableRewardTokens() >= pending, "Insufficient reward tokens");
                rewardToken.safeTransfer(address(msg.sender), pending);

                totalEarned = totalEarned > pending ? totalEarned - pending : 0;
                paidRewards = paidRewards + pending;
                emit Claim(msg.sender, pending);
            }

            uint256 pendingReflection =
                (user.amount * accDividendPerShare) / PRECISION_FACTOR_REFLECTION - user.reflectionDebt;

            if (pendingReflection > 0 && hasDividend) {
                uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
                totalReflections = totalReflections - pendingReflection;
                if (address(dividendToken) == address(0x0)) {
                    payable(msg.sender).transfer(_pendingReflection);
                } else {
                    IERC20(dividendToken).safeTransfer(address(msg.sender), _pendingReflection);
                }
                emit ClaimDividend(msg.sender, _pendingReflection);
            }
        }

        uint256 beforeAmount = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 afterAmount = stakingToken.balanceOf(address(this));
        uint256 realAmount = afterAmount - beforeAmount;
        if (realAmount > _amount) realAmount = _amount;

        if (depositFee > 0) {
            uint256 fee = (realAmount * depositFee) / PERCENT_PRECISION;
            stakingToken.safeTransfer(walletA, fee);
            realAmount = realAmount - fee;
        }

        user.amount = user.amount + realAmount;
        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        user.reflectionDebt = (user.amount * accDividendPerShare) / PRECISION_FACTOR_REFLECTION;

        totalStaked = totalStaked + realAmount;

        emit Deposit(msg.sender, realAmount);

        if (autoAdjustableForRewardRate) _updateRewardRate();
    }

    /**
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in staking token)
     */
    function withdraw(uint256 _amount) external payable nonReentrant {
        require(_amount > 0, "Amount should be greator than 0");

        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _transferPerformanceFee();
        _updatePool();

        if (user.amount > 0) {
            uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
            if (pending > 0) {
                require(availableRewardTokens() >= pending, "Insufficient reward tokens");
                rewardToken.safeTransfer(address(msg.sender), pending);

                totalEarned = totalEarned > pending ? totalEarned - pending : 0;
                paidRewards = paidRewards + pending;
                emit Claim(msg.sender, pending);
            }

            uint256 pendingReflection =
                (user.amount * accDividendPerShare) / PRECISION_FACTOR_REFLECTION - user.reflectionDebt;

            if (pendingReflection > 0 && hasDividend) {
                uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
                totalReflections = totalReflections - pendingReflection;
                if (address(dividendToken) == address(0x0)) {
                    payable(msg.sender).transfer(_pendingReflection);
                } else {
                    IERC20(dividendToken).safeTransfer(address(msg.sender), _pendingReflection);
                }
                emit ClaimDividend(msg.sender, _pendingReflection);
            }
        }

        uint256 realAmount = _amount;
        if (user.amount < _amount) {
            realAmount = user.amount;
        }

        user.amount = user.amount - realAmount;
        totalStaked = totalStaked - realAmount;
        emit Withdraw(msg.sender, realAmount);

        if (withdrawFee > 0) {
            uint256 fee = (realAmount * withdrawFee) / PERCENT_PRECISION;
            stakingToken.safeTransfer(walletA, fee);
            realAmount = realAmount - fee;
        }

        stakingToken.safeTransfer(address(msg.sender), realAmount);

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        user.reflectionDebt = (user.amount * accDividendPerShare) / PRECISION_FACTOR_REFLECTION;

        if (autoAdjustableForRewardRate) _updateRewardRate();
    }

    function claimReward() external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();
        _updatePool();

        if (user.amount == 0) return;

        uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            rewardToken.safeTransfer(address(msg.sender), pending);

            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            paidRewards = paidRewards + pending;
            emit Claim(msg.sender, pending);
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
    }

    function claimDividend() external payable nonReentrant {
        require(hasDividend == true, "No reflections");
        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();
        _updatePool();

        if (user.amount == 0) return;

        uint256 pendingReflection =
            (user.amount * accDividendPerShare) / PRECISION_FACTOR_REFLECTION - user.reflectionDebt;

        if (pendingReflection > 0) {
            uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
            totalReflections = totalReflections - pendingReflection;
            if (address(dividendToken) == address(0x0)) {
                payable(msg.sender).transfer(_pendingReflection);
            } else {
                IERC20(dividendToken).safeTransfer(address(msg.sender), _pendingReflection);
            }
            emit ClaimDividend(msg.sender, _pendingReflection);
        }

        user.reflectionDebt = (user.amount * accDividendPerShare) / PRECISION_FACTOR_REFLECTION;
    }

    function precomputeCompound(bool isDividend, uint256 _gasPrice)
        external
        view
        returns (IBrewlabsAggregator.FormattedOffer memory offer)
    {
        if (!isDividend && address(stakingToken) == address(rewardToken)) return offer;
        if (isDividend && address(stakingToken) == dividendToken) return offer;

        uint256 pending = isDividend ? pendingDividends(msg.sender) : pendingReward(msg.sender);
        if (pending == 0) return offer;

        if (!isDividend) {
            offer =
                swapAggregator.findBestPathWithGas(pending, address(rewardToken), address(stakingToken), 3, _gasPrice);
        } else {
            offer = swapAggregator.findBestPathWithGas(
                pending, dividendToken == address(0x0) ? WNATIVE : dividendToken, address(stakingToken), 3, _gasPrice
            );
        }
    }

    function compoundReward(IBrewlabsAggregator.Trade memory _trade) external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();
        _updatePool();

        if (user.amount == 0) return;

        uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            paidRewards = paidRewards + pending;
            emit Compound(msg.sender, pending);

            if (address(stakingToken) != address(rewardToken)) {
                pending = _safeSwap(pending, address(rewardToken), address(stakingToken), address(this), _trade);
            }

            if (hasUserLimit) {
                require(pending + user.amount <= poolLimitPerUser, "User amount above limit");
            }

            totalStaked = totalStaked + pending;
            user.amount = user.amount + pending;
            user.reflectionDebt = user.reflectionDebt + (pending * accDividendPerShare) / PRECISION_FACTOR_REFLECTION;

            emit Deposit(msg.sender, pending);
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
    }

    function compoundDividend(IBrewlabsAggregator.Trade memory _trade) external payable nonReentrant {
        require(hasDividend == true, "No reflections");
        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();
        _updatePool();

        if (user.amount == 0) return;

        uint256 _pending = (user.amount * accDividendPerShare) / PRECISION_FACTOR_REFLECTION - user.reflectionDebt;
        uint256 pending = estimateDividendAmount(_pending);
        totalReflections = totalReflections - _pending;
        if (pending > 0) {
            emit CompoundDividend(msg.sender, pending);

            if (address(stakingToken) != address(dividendToken)) {
                if (address(dividendToken) == address(0x0)) {
                    IWETH(WNATIVE).deposit{value: pending}();

                    pending = _safeSwap(pending, WNATIVE, address(stakingToken), address(this), _trade);
                } else {
                    pending = _safeSwap(pending, dividendToken, address(stakingToken), address(this), _trade);
                }
            }

            if (hasUserLimit) {
                require(pending + user.amount <= poolLimitPerUser, "User amount above limit");
            }

            totalStaked = totalStaked + pending;
            user.amount = user.amount + pending;
            user.rewardDebt = user.rewardDebt + (pending * accTokenPerShare) / PRECISION_FACTOR;

            emit Deposit(msg.sender, pending);
        }

        user.reflectionDebt = (user.amount * accDividendPerShare) / PRECISION_FACTOR_REFLECTION;
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
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.reflectionDebt = 0;

        if (amountToTransfer > 0) {
            stakingToken.safeTransfer(address(msg.sender), amountToTransfer);
            totalStaked = totalStaked - amountToTransfer;
        }

        emit EmergencyWithdraw(msg.sender, amountToTransfer);
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

    function insufficientRewards() public view returns (uint256) {
        uint256 adjustedShouldTotalPaid = shouldTotalPaid;
        uint256 remainRewards = availableRewardTokens() + paidRewards;

        if (startBlock == 0) {
            adjustedShouldTotalPaid = adjustedShouldTotalPaid + rewardPerBlock * duration * BLOCKS_PER_DAY;
        } else {
            uint256 remainBlocks = _getMultiplier(lastRewardBlock, bonusEndBlock);
            adjustedShouldTotalPaid = adjustedShouldTotalPaid + rewardPerBlock * remainBlocks;
        }

        if (remainRewards >= adjustedShouldTotalPaid) return 0;

        return adjustedShouldTotalPaid - remainRewards;
    }

    /**
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];

        uint256 adjustedTokenPerShare = accTokenPerShare;
        if (block.number > lastRewardBlock && totalStaked != 0 && lastRewardBlock > 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 rewards = multiplier * rewardPerBlock;

            adjustedTokenPerShare = accTokenPerShare + ((rewards * PRECISION_FACTOR) / totalStaked);
        }

        return (user.amount * adjustedTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
    }

    function pendingDividends(address _user) public view returns (uint256) {
        if (totalStaked == 0) return 0;

        UserInfo memory user = userInfo[_user];

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

        uint256 adjustedReflectionPerShare =
            accDividendPerShare + ((reflectionAmount * PRECISION_FACTOR_REFLECTION) / sTokenBal);

        uint256 pendingReflection =
            (user.amount * adjustedReflectionPerShare) / PRECISION_FACTOR_REFLECTION - user.reflectionDebt;

        return pendingReflection;
    }

    /**
     * Admin Methods
     */
    function harvestTo(address _treasury) external onlyAdmin {
        _updatePool();

        if (reflections > 0) {
            if (address(dividendToken) == address(0x0)) {
                payable(_treasury).transfer(estimateDividendAmount(reflections));
            } else {
                IERC20(dividendToken).safeTransfer(_treasury, estimateDividendAmount(reflections));
            }

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

    function increaseEmissionRate(uint256 _amount) external onlyAdmin {
        require(startBlock > 0, "pool is not started");
        require(bonusEndBlock > block.number, "pool was already finished");
        require(_amount > 0, "invalid amount");

        _updatePool();

        uint256 beforeAmt = rewardToken.balanceOf(address(this));
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = rewardToken.balanceOf(address(this));

        totalEarned = totalEarned + afterAmt - beforeAmt;
        _updateRewardRate();
    }

    function _updateRewardRate() internal {
        if (bonusEndBlock <= block.number) return;

        uint256 remainRewards = availableRewardTokens() + paidRewards;
        if (remainRewards > shouldTotalPaid) {
            remainRewards = remainRewards - shouldTotalPaid;

            uint256 remainBlocks = bonusEndBlock - block.number;
            rewardPerBlock = remainRewards / remainBlocks;
            emit NewRewardPerBlock(rewardPerBlock);
        }
    }

    /**
     * @notice Withdraw reward token
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(block.number > bonusEndBlock, "Pool is running");
        require(availableRewardTokens() >= _amount, "Insufficient reward tokens");

        if (_amount == 0) _amount = availableRewardTokens();
        rewardToken.safeTransfer(address(msg.sender), _amount);

        if (totalEarned > 0) {
            if (_amount > totalEarned) {
                totalEarned = 0;
            } else {
                totalEarned = totalEarned - _amount;
            }
        }
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @param _amount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        require(_token != address(rewardToken) || _token == dividendToken, "Cannot be reward token");

        if (_token == address(stakingToken)) {
            uint256 tokenBal = stakingToken.balanceOf(address(this));
            require(_amount <= tokenBal - totalStaked, "Insufficient balance");
        }

        if (_token == address(0x0)) {
            payable(msg.sender).transfer(_amount);
        } else {
            IERC20(_token).safeTransfer(address(msg.sender), _amount);
        }

        emit AdminTokenRecovered(_token, _amount);
    }

    function startReward() external onlyAdmin {
        require(startBlock == 0, "Pool was already started");
        require(insufficientRewards() == 0, "All reward tokens have not been deposited");

        startBlock = block.number + 100;
        bonusEndBlock = startBlock + duration * BLOCKS_PER_DAY;
        lastRewardBlock = startBlock;

        emit NewStartAndEndBlocks(startBlock, bonusEndBlock);
    }

    function stopReward() external onlyAdmin {
        _updatePool();

        uint256 remainRewards = availableRewardTokens() + paidRewards;
        if (remainRewards > shouldTotalPaid) {
            remainRewards = remainRewards - shouldTotalPaid;
            rewardToken.safeTransfer(msg.sender, remainRewards);

            if (totalEarned > remainRewards) {
                totalEarned = totalEarned - remainRewards;
            } else {
                totalEarned = 0;
            }
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
    function updatePoolLimitPerUser(bool _hasUserLimit, uint256 _poolLimitPerUser) external onlyOwner {
        if (_hasUserLimit) {
            require(_poolLimitPerUser > poolLimitPerUser, "New limit must be higher");
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            poolLimitPerUser = 0;
        }
        hasUserLimit = _hasUserLimit;

        emit UpdatePoolLimit(poolLimitPerUser, hasUserLimit);
    }

    /**
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardPerBlock: the reward per block
     */
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyAdmin {
        // require(block.number < startBlock, "Pool was already started");
        _updatePool();

        rewardPerBlock = _rewardPerBlock;
        emit NewRewardPerBlock(_rewardPerBlock);
    }

    function setServiceInfo(address _treasury, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_treasury != address(0x0), "Invalid address");

        treasury = _treasury;
        performanceFee = _fee;

        emit ServiceInfoChanged(_treasury, _fee);
    }

    function updateWalletA(address _walletA) external onlyOwner {
        require(_walletA != address(0x0) || _walletA != walletA, "Invalid address");

        walletA = _walletA;
        emit WalletAUpdated(_walletA);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(_duration >= 30, "lower limit reached");

        duration = _duration;
        if (startBlock > 0) {
            bonusEndBlock = startBlock + duration * BLOCKS_PER_DAY;
            require(bonusEndBlock > block.number, "invalid duration");
        }
        emit DurationChanged(_duration);
    }

    function setAutoAdjustableForRewardRate(bool _status) external onlyOwner {
        autoAdjustableForRewardRate = _status;
        emit SetAutoAdjustableForRewardRate(_status);
    }

    function transferOperator(address _operator) external onlyAdmin {
        require(_operator != address(0x0), "invalid address");
        emit OperatorTransferred(operator, _operator);
        operator = _operator;
    }

    /**
     * @notice Update swap aggregator.
     * @param _aggregator: swap Aggregator address
     */
    function setSwapAggregator(address _aggregator) external onlyOwner {
        require(_aggregator != address(0x0), "Invalid address");
        require(IBrewlabsAggregator(_aggregator).WNATIVE() != address(0x0), "Invalid swap aggregator");

        swapAggregator = IBrewlabsAggregator(_aggregator);
        WNATIVE = IBrewlabsAggregator(_aggregator).WNATIVE();
        emit SetSwapAggregator(_aggregator);
    }

    function setWhitelist(address _whitelist) external onlyOwner {
        whiteList = _whitelist;
        emit SetWhiteList(_whitelist);
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        // calc reflection rate
        if (totalStaked > 0 && hasDividend) {
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

            accDividendPerShare += (reflectionAmount * PRECISION_FACTOR_REFLECTION) / sTokenBal;

            reflections += (reflectionAmount * eTokenBal) / sTokenBal;
            totalReflections += reflectionAmount;
        }

        if (block.number <= lastRewardBlock || lastRewardBlock == 0) return;
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 _reward = multiplier * rewardPerBlock;
        accTokenPerShare += (_reward * PRECISION_FACTOR) / totalStaked;

        lastRewardBlock = block.number;
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

    function _safeSwap(
        uint256 _amountIn,
        address _fromToken,
        address _toToken,
        address _to,
        IBrewlabsAggregator.Trade memory _trade
    ) internal returns (uint256) {
        IERC20(_fromToken).safeApprove(address(swapAggregator), _amountIn);

        uint256 beforeAmount = IERC20(_toToken).balanceOf(_to);
        _trade.amountIn = _amountIn;
        swapAggregator.swapNoSplit(_trade, _to, block.timestamp + 600);
        uint256 afterAmount = IERC20(_toToken).balanceOf(_to);

        return afterAmount - beforeAmount;
    }

    receive() external payable {}
}
