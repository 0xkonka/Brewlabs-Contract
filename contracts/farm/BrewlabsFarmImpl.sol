// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libs/IUniRouter02.sol";
import "../libs/IWETH.sol";

contract BrewlabsFarmImpl is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool private isInitialized;

    uint256 private BLOCKS_PER_DAY;
    uint256 private PERCENT_PRECISION;
    uint256 public PRECISION_FACTOR;
    uint256 public MAX_FEE;
    // The precision factor

    // The staked token
    IERC20 public lpToken;
    IERC20 public rewardToken;
    // The dividend token of lpToken token
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

    // service fees
    address public feeAddress;
    address public treasury;
    uint256 public performanceFee;
    uint256 public rewardFee;
    address public operator;

    struct UserInfo {
        uint256 amount; // How many staked lp the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 reflectionDebt; // Reflection debt
    }
    // Info of each user that stakes lpToken

    mapping(address => UserInfo) public userInfo;

    uint256 public totalStaked;
    uint256 private totalEarned;
    uint256 private totalReflections;
    uint256 private totalRewardStaked;
    uint256 private totalReflectionStaked;
    uint256 private reflectionDebt;

    uint256 public paidRewards;
    uint256 private shouldTotalPaid;

    // swap router and path
    struct SwapSetting {
        address swapRouter;
        address[] earnedToToken0;
        address[] earnedToToken1;
        address[] reflectionToToken0;
        address[] reflectionToToken1;
        bool enabled;
    }

    SwapSetting public swapSettings;

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
    event EndBlockUpdated(uint256 blockNumber);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event DurationUpdated(uint256 duration);
    event SetAutoAdjustableForRewardRate(bool status);
    event SetRewardFee(uint256 fee);
    event OperatorTransferred(address oldOperator, address newOperator);

    event SetSettings(uint256 depositFee, uint256 withdrawFee, address feeAddr);

    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == operator, "caller is not owner or operator");
        _;
    }

    constructor() {}

    /**
     * @notice Initialize the contract
     * @param _lpToken: LP address
     * @param _rewardToken: earned token address
     * @param _dividendToken: reflection token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _depositFee: deposit fee
     * @param _withdrawFee: withdraw fee
     * @param _hasDividend: reflection available flag
     * @param _owner: owner address
     */
    function initialize(
        IERC20 _lpToken,
        IERC20 _rewardToken,
        address _dividendToken,
        uint256 _rewardPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        bool _hasDividend,
        address _owner,
        address _operator
    ) external {
        require(!isInitialized, "Already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "Not allowed");

        // Make this contract initialized
        isInitialized = true;

        PERCENT_PRECISION = 10000;
        BLOCKS_PER_DAY = 28800;
        MAX_FEE = 2000;
        PRECISION_FACTOR = 10 ** 18;

        duration = 365; // 365 days

        treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        feeAddress = _owner;
        performanceFee = 0.0035 ether;

        lpToken = _lpToken;
        rewardToken = _rewardToken;
        dividendToken = _dividendToken;

        hasDividend = _hasDividend;
        rewardPerBlock = _rewardPerBlock;

        require(_depositFee < MAX_FEE, "Invalid deposit fee");
        require(_withdrawFee < MAX_FEE, "Invalid withdraw fee");
        depositFee = _depositFee;
        withdrawFee = _withdrawFee;

        operator = _operator;

        _transferOwnership(_owner);
    }

    /**
     * @notice Deposit LP tokens and collect reward tokens (if any)
     * @param _amount: amount to stake (in lp token)
     */
    function deposit(uint256 _amount) external payable nonReentrant {
        require(startBlock > 0 && startBlock < block.number, "Farming hasn't started yet");
        require(_amount > 0, "Amount should be greator than 0");

        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();
        _updatePool();

        if (user.amount > 0) {
            uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
            if (pending > 0) {
                require(availableRewardTokens() >= pending, "Insufficient reward tokens");
                paidRewards = paidRewards + pending;

                pending = (pending * (PERCENT_PRECISION - rewardFee)) / PERCENT_PRECISION;
                rewardToken.safeTransfer(address(msg.sender), pending);
                if (totalEarned > pending) {
                    totalEarned = totalEarned - pending;
                } else {
                    totalEarned = 0;
                }
                emit Claim(msg.sender, pending);
            }

            uint256 pendingReflection = (user.amount * accDividendPerShare) / PRECISION_FACTOR - user.reflectionDebt;
            if (pendingReflection > 0 && hasDividend) {
                uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
                totalReflections -= pendingReflection;
                if (address(dividendToken) == address(0x0)) {
                    payable(msg.sender).transfer(_pendingReflection);
                } else {
                    IERC20(dividendToken).safeTransfer(address(msg.sender), _pendingReflection);
                }
                emit ClaimDividend(msg.sender, _pendingReflection);
            }
        }

        uint256 beforeAmt = lpToken.balanceOf(address(this));
        lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 afterAmt = lpToken.balanceOf(address(this));
        uint256 realAmount = afterAmt - beforeAmt;

        if (depositFee > 0) {
            uint256 fee = (realAmount * depositFee) / PERCENT_PRECISION;
            lpToken.safeTransfer(feeAddress, fee);
            realAmount -= fee;
        }
        _calculateTotalStaked(realAmount, true);

        user.amount = user.amount + realAmount;
        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        user.reflectionDebt = (user.amount * accDividendPerShare) / PRECISION_FACTOR;

        emit Deposit(msg.sender, realAmount);

        if (rewardFee > 0 || autoAdjustableForRewardRate) _updateRewardRate();
    }

    /**
     * @notice Withdraw staked lp token and collect reward tokens
     * @param _amount: amount to withdraw (in lp token)
     */
    function withdraw(uint256 _amount) external payable nonReentrant {
        require(_amount > 0, "Amount should be greator than 0");

        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _transferPerformanceFee();
        _updatePool();

        uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            paidRewards = paidRewards + pending;

            pending = (pending * (PERCENT_PRECISION - rewardFee)) / PERCENT_PRECISION;
            rewardToken.safeTransfer(address(msg.sender), pending);
            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            emit Claim(msg.sender, pending);
        }

        uint256 pendingReflection = (user.amount * accDividendPerShare) / PRECISION_FACTOR - user.reflectionDebt;
        if (pendingReflection > 0 && hasDividend) {
            uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
            totalReflections -= pendingReflection;
            if (address(dividendToken) == address(0x0)) {
                payable(msg.sender).transfer(_pendingReflection);
            } else {
                IERC20(dividendToken).safeTransfer(msg.sender, _pendingReflection);
            }
            emit ClaimDividend(msg.sender, _pendingReflection);
        }

        if (withdrawFee > 0) {
            uint256 fee = (_amount * withdrawFee) / PERCENT_PRECISION;
            lpToken.safeTransfer(feeAddress, fee);
            lpToken.safeTransfer(msg.sender, _amount - fee);
        } else {
            lpToken.safeTransfer(msg.sender, _amount);
        }
        _calculateTotalStaked(_amount, false);

        user.amount = user.amount - _amount;
        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        user.reflectionDebt = (user.amount * accDividendPerShare) / PRECISION_FACTOR;
        emit Withdraw(msg.sender, _amount);

        if (rewardFee > 0 || autoAdjustableForRewardRate) _updateRewardRate();
    }

    function claimReward() external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) return;

        _transferPerformanceFee();
        _updatePool();

        uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            paidRewards = paidRewards + pending;

            pending = (pending * (PERCENT_PRECISION - rewardFee)) / PERCENT_PRECISION;
            rewardToken.safeTransfer(msg.sender, pending);
            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            emit Claim(msg.sender, pending);
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
    }

    function claimDividend() external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) return;
        if (!hasDividend) return;

        _transferPerformanceFee();
        _updatePool();

        uint256 pendingReflection = (user.amount * accDividendPerShare) / PRECISION_FACTOR - user.reflectionDebt;
        if (pendingReflection > 0) {
            uint256 _pendingReflection = estimateDividendAmount(pendingReflection);
            totalReflections = totalReflections - pendingReflection;
            if (address(dividendToken) == address(0x0)) {
                payable(msg.sender).transfer(_pendingReflection);
            } else {
                IERC20(dividendToken).safeTransfer(msg.sender, _pendingReflection);
            }
            emit ClaimDividend(msg.sender, _pendingReflection);
        }

        user.reflectionDebt = (user.amount * accDividendPerShare) / PRECISION_FACTOR;
    }

    function compoundReward() external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) return;
        if (!swapSettings.enabled) return;

        _transferPerformanceFee();
        _updatePool();

        uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            paidRewards = paidRewards + pending;

            pending = (pending * (PERCENT_PRECISION - rewardFee)) / PERCENT_PRECISION;
            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            emit Compound(msg.sender, pending);

            if (address(lpToken) != address(rewardToken)) {
                uint256 tokenAmt = pending / 2;
                uint256 tokenAmt0 = tokenAmt;
                address token0 = address(rewardToken);
                if (swapSettings.earnedToToken0.length > 0) {
                    token0 = swapSettings.earnedToToken0[swapSettings.earnedToToken0.length - 1];
                    tokenAmt0 = _safeSwap(tokenAmt, swapSettings.earnedToToken0, address(this));
                }
                uint256 tokenAmt1 = tokenAmt;
                address token1 = address(rewardToken);
                if (swapSettings.earnedToToken1.length > 0) {
                    token1 = swapSettings.earnedToToken1[swapSettings.earnedToToken1.length - 1];
                    tokenAmt1 = _safeSwap(tokenAmt, swapSettings.earnedToToken1, address(this));
                }

                uint256 beforeAmt = lpToken.balanceOf(address(this));
                _addLiquidity(swapSettings.swapRouter, token0, token1, tokenAmt0, tokenAmt1, address(this));
                uint256 afterAmt = lpToken.balanceOf(address(this));

                pending = afterAmt - beforeAmt;
            }

            user.amount = user.amount + pending;
            user.rewardDebt = (user.amount * accTokenPerShare) / PERCENT_PRECISION;
            user.reflectionDebt = user.reflectionDebt + (pending * accDividendPerShare) / PERCENT_PRECISION;

            _calculateTotalStaked(pending, true);
            emit Deposit(msg.sender, pending);
        }
    }

    function compoundDividend() external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) return;
        if (!hasDividend || !swapSettings.enabled) return;

        _transferPerformanceFee();
        _updatePool();

        uint256 _pending = (user.amount * accDividendPerShare) / PRECISION_FACTOR - user.reflectionDebt;
        totalReflections = totalReflections - _pending;
        uint256 pending = estimateDividendAmount(_pending);
        if (pending > 0) {
            emit CompoundDividend(msg.sender, pending);

            if (address(lpToken) != address(dividendToken)) {
                if (address(dividendToken) == address(0x0)) {
                    address wethAddress = IUniRouter02(swapSettings.swapRouter).WETH();
                    IWETH(wethAddress).deposit{value: pending}();
                }

                uint256 tokenAmt = pending / 2;
                uint256 tokenAmt0 = tokenAmt;
                address token0 = dividendToken;
                if (swapSettings.reflectionToToken0.length > 0) {
                    token0 = swapSettings.reflectionToToken0[swapSettings.reflectionToToken0.length - 1];
                    tokenAmt0 = _safeSwap(tokenAmt, swapSettings.reflectionToToken0, address(this));
                }
                uint256 tokenAmt1 = tokenAmt;
                address token1 = dividendToken;
                if (swapSettings.reflectionToToken1.length > 0) {
                    token0 = swapSettings.reflectionToToken1[swapSettings.reflectionToToken1.length - 1];
                    tokenAmt1 = _safeSwap(tokenAmt, swapSettings.reflectionToToken1, address(this));
                }

                uint256 beforeAmt = lpToken.balanceOf(address(this));
                _addLiquidity(swapSettings.swapRouter, token0, token1, tokenAmt0, tokenAmt1, address(this));
                uint256 afterAmt = lpToken.balanceOf(address(this));

                pending = afterAmt - beforeAmt;
            }

            user.amount = user.amount + pending;
            user.rewardDebt = user.rewardDebt + (pending * accTokenPerShare) / PRECISION_FACTOR;
            user.reflectionDebt = (user.amount * accDividendPerShare) / PRECISION_FACTOR;

            _calculateTotalStaked(pending, true);
            emit Deposit(msg.sender, pending);
        }
    }

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "should pay small gas to compound or harvest");

        payable(treasury).transfer(performanceFee);
        if (msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value - performanceFee);
        }
    }

    function _calculateTotalStaked(uint256 _amount, bool _deposit) internal {
        if (_deposit) {
            totalStaked = totalStaked + _amount;
            if (address(lpToken) == address(rewardToken)) {
                totalRewardStaked = totalRewardStaked + _amount;
            }
            if (address(lpToken) == dividendToken) {
                totalReflectionStaked = totalReflectionStaked + _amount;
            }
        } else {
            totalStaked = totalStaked - _amount;
            if (address(lpToken) == address(rewardToken)) {
                if (totalRewardStaked < _amount) totalRewardStaked = _amount;
                totalRewardStaked = totalRewardStaked - _amount;
            }
            if (address(lpToken) == dividendToken) {
                if (totalReflectionStaked < _amount) totalReflectionStaked = _amount;
                totalReflectionStaked = totalReflectionStaked - _amount;
            }
        }
    }

    /**
     * @notice Withdraw staked tokens without caring about rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) return;

        uint256 amountToTransfer = user.amount;
        lpToken.safeTransfer(address(msg.sender), amountToTransfer);

        user.amount = 0;
        user.rewardDebt = 0;
        user.reflectionDebt = 0;

        _calculateTotalStaked(amountToTransfer, false);
        emit EmergencyWithdraw(msg.sender, amountToTransfer);
    }

    /**
     * @notice Available amount of reward token
     */
    function availableRewardTokens() public view returns (uint256) {
        if (address(rewardToken) == dividendToken && hasDividend) return totalEarned;

        uint256 _amount = rewardToken.balanceOf(address(this));
        return _amount - totalRewardStaked;
    }

    /**
     * @notice Available amount of reflection token
     */
    function availableDividendTokens() public view returns (uint256) {
        if (hasDividend == false) return 0;
        if (dividendToken == address(0x0)) {
            return address(this).balance;
        }

        uint256 _amount = IERC20(dividendToken).balanceOf(address(this));
        if (dividendToken == address(rewardToken)) {
            if (_amount < totalEarned) return 0;
            _amount = _amount - totalEarned;
        }
        return _amount - totalReflectionStaked;
    }

    function insufficientRewards() external view returns (uint256) {
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
    function pendingRewards(address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_user];

        uint256 adjustedTokenPerShare = accTokenPerShare;
        if (block.number > lastRewardBlock && totalStaked != 0 && lastRewardBlock > 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 rewards = multiplier * rewardPerBlock;

            adjustedTokenPerShare = accTokenPerShare + ((rewards * PRECISION_FACTOR) / totalStaked);
        }

        return (user.amount * adjustedTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
    }

    function pendingReflections(address _user) external view returns (uint256) {
        if (totalStaked == 0) return 0;

        UserInfo memory user = userInfo[_user];

        uint256 reflectionAmount = availableDividendTokens();
        if (reflectionAmount > totalReflections) {
            reflectionAmount -= totalReflections;
        } else {
            reflectionAmount = 0;
        }

        uint256 adjustedReflectionPerShare = accDividendPerShare + ((reflectionAmount * PRECISION_FACTOR) / totalStaked);

        uint256 pendingReflection = (user.amount * adjustedReflectionPerShare) / PRECISION_FACTOR - user.reflectionDebt;

        return pendingReflection;
    }

    /**
     * Admin Methods
     */
    function transferToHarvest() external onlyOwner {
        if (hasDividend || address(rewardToken) == dividendToken) return;

        if (dividendToken == address(0x0)) {
            payable(treasury).transfer(address(this).balance);
        } else {
            uint256 _amount = IERC20(dividendToken).balanceOf(address(this));
            IERC20(dividendToken).safeTransfer(treasury, _amount);
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

    function increaseEmissionRate(uint256 _amount) external onlyOwner {
        require(_amount > 0, "invalid amount");
        require(startBlock > 0, "pool is not started");
        require(bonusEndBlock > block.number, "pool was already finished");

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

    function emergencyWithdrawReflections() external onlyOwner {
        if (dividendToken == address(0x0)) {
            uint256 amount = address(this).balance;
            payable(address(msg.sender)).transfer(amount);
        } else {
            uint256 amount = IERC20(dividendToken).balanceOf(address(this));
            IERC20(dividendToken).transfer(msg.sender, amount);
        }
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address _token) external onlyOwner {
        require(
            _token != address(rewardToken) && _token != dividendToken, "cannot recover reward token or reflection token"
        );
        require(_token != address(lpToken), "token is using on pool");

        uint256 amount;
        if (_token == address(0x0)) {
            amount = address(this).balance;
            payable(address(msg.sender)).transfer(amount);
        } else {
            amount = IERC20(_token).balanceOf(address(this));
            if (amount > 0) {
                IERC20(_token).transfer(msg.sender, amount);
            }
        }

        emit AdminTokenRecovered(_token, amount);
    }

    function startReward() external onlyAdmin {
        require(startBlock == 0, "Pool was already started");

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
            rewardToken.transfer(msg.sender, remainRewards);

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
        emit EndBlockUpdated(_endBlock);
    }

    /**
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardPerBlock: the reward per block
     */
    function updateEmissionRate(uint256 _rewardPerBlock) external onlyOwner {
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

        emit ServiceInfoUpadted(_treasury, _fee);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(_duration >= 30, "lower limit reached");

        duration = _duration;
        if (startBlock > 0) {
            bonusEndBlock = startBlock + duration * BLOCKS_PER_DAY;
            require(bonusEndBlock > block.number, "invalid duration");
        }
        emit DurationUpdated(_duration);
    }

    function setRewardFee(uint256 _fee) external onlyOwner {
        require(_fee < PERCENT_PRECISION, "setRewardFee: invalid percentage");

        rewardFee = _fee;
        emit SetRewardFee(_fee);
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

    function setSettings(uint256 _depositFee, uint256 _withdrawFee, address _feeAddr) external onlyOwner {
        require(_feeAddr != address(0x0) || _feeAddr != feeAddress, "Invalid address");
        require(_depositFee < MAX_FEE, "Invalid deposit fee");
        require(_withdrawFee < MAX_FEE, "Invalid withdraw fee");

        depositFee = _depositFee;
        withdrawFee = _withdrawFee;

        feeAddress = _feeAddr;
        emit SetSettings(_depositFee, _withdrawFee, _feeAddr);
    }

    // Update the given pool's compound parameters. Can only be called by the owner.
    function setSwapSetting(
        address _uniRouter,
        address[] memory _earnedToToken0,
        address[] memory _earnedToToken1,
        address[] memory _reflectionToToken0,
        address[] memory _reflectionToToken1,
        bool _enabled
    ) external onlyOwner {
        swapSettings.enabled = _enabled;
        swapSettings.swapRouter = _uniRouter;
        swapSettings.earnedToToken0 = _earnedToToken0;
        swapSettings.earnedToToken1 = _earnedToToken1;
        swapSettings.reflectionToToken0 = _reflectionToToken0;
        swapSettings.reflectionToToken1 = _reflectionToToken1;
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock || lastRewardBlock == 0) return;
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        // calc reflection rate
        if (totalStaked > 0 && hasDividend) {
            uint256 reflectionAmount = availableDividendTokens();
            if (reflectionAmount > totalReflections) {
                reflectionAmount -= totalReflections;
            } else {
                reflectionAmount = 0;
            }

            accDividendPerShare += (reflectionAmount * PRECISION_FACTOR) / totalStaked;
            totalReflections += reflectionAmount;
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

    function _safeSwap(uint256 _amountIn, address[] memory _path, address _to) internal returns (uint256) {
        uint256 beforeAmt = IERC20(_path[_path.length - 1]).balanceOf(address(this));

        IERC20(_path[0]).safeApprove(swapSettings.swapRouter, _amountIn);
        IUniRouter02(swapSettings.swapRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
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
