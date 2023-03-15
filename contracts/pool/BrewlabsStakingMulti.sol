// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libs/IUniRouter02.sol";
import "../libs/IWETH.sol";

interface IToken {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);

    function claim() external;
}

contract BrewlabsStakingMulti is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // The address of the smart chef factory
    address public POOL_FACTORY;

    // Whether it is initialized
    bool public isInitialized;
    uint256 public duration = 60; // 60 days

    // Whether a limit is set for users
    bool public hasUserLimit;
    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // The block number when staking starts.
    uint256 public startBlock;
    // The block number when staking ends.
    uint256 public bonusEndBlock;
    // tokens created per block.
    uint256 public rewardPerBlock;
    // The block number of the last pool update
    uint256 public lastRewardBlock;

    // swap router and path, slipPage
    uint256 public slippageFactor = 800; // 20% default slippage tolerance
    uint256 public constant slippageFactorUL = 995;

    address public uniRouterAddress;
    address[] public earnedToStakedPath;

    // The deposit & withdraw fee
    uint256 public constant MAX_FEE = 2000;
    uint256 public depositFee;
    uint256 public withdrawFee;

    address public walletA;
    address public buyBackWallet = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
    uint256 public performanceFee = 0.0035 ether;

    // The precision factor
    uint256 public PRECISION_FACTOR;
    uint256[] public PRECISION_FACTOR_REFLECTION;

    // The staked token
    IERC20 public stakingToken;
    // The earned token
    IERC20 public earnedToken;
    // The dividend token of staking token
    address[] public dividendTokens;

    // Accrued token per share
    uint256 public accTokenPerShare;
    uint256[] public accDividendPerShare;

    uint256 public totalStaked;

    uint256 private totalEarned;
    uint256[] private totalReflections;
    uint256[] private reflections;

    uint256 private paidRewards;
    uint256 private shouldTotalPaid;

    // Info of each user that stakes tokens (stakingToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256[] reflectionDebt; // Reflection debt
    }

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);

    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardPerBlock(uint256 rewardPerBlock);
    event RewardsStop(uint256 blockNumber);
    event EndBlockUpdated(uint256 blockNumber);
    event UpdatePoolLimit(uint256 poolLimitPerUser, bool hasLimit);

    event ServiceInfoUpadted(address _addr, uint256 _fee);
    event WalletAUpdated(address _addr);
    event DurationUpdated(uint256 _duration);

    event SetSettings(
        uint256 _depositFee, uint256 _withdrawFee, uint256 _slippageFactor, address _uniRouter, address[] _path0
    );

    constructor() {
        POOL_FACTORY = msg.sender;
    }

    /*
    * @notice Initialize the contract
    * @param _stakingToken: staked token address
    * @param _earnedToken: earned token address
    * @param _dividendTokens: reflection token list
    * @param _rewardPerBlock: reward per block (in earnedToken)
    * @param _depositFee: deposit fee
    * @param _withdrawFee: withdraw fee
    * @param _uniRouter: uniswap router address for swap tokens
    * @param _earnedToStakedPath: swap path to compound (earned -> staking path)
    */
    function initialize(
        IERC20 _stakingToken,
        IERC20 _earnedToken,
        address[] memory _dividendTokens,
        uint256 _rewardPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        address _uniRouter,
        address[] memory _earnedToStakedPath
    ) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == POOL_FACTORY, "Not factory");

        // Make this contract initialized
        isInitialized = true;

        stakingToken = _stakingToken;
        earnedToken = _earnedToken;

        uint256 decimalsRewardToken = uint256(IToken(address(earnedToken)).decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");
        PRECISION_FACTOR = uint256(10 ** (40 - decimalsRewardToken));

        for (uint256 i = 0; i < _dividendTokens.length; i++) {
            dividendTokens.push(_dividendTokens[i]);
            totalReflections.push(0);
            accDividendPerShare.push(0);
            reflections.push(0);

            uint256 decimalsdividendToken = 18;
            if (address(dividendTokens[i]) != address(0x0)) {
                decimalsdividendToken = uint256(IToken(address(dividendTokens[i])).decimals());
                require(decimalsdividendToken < 30, "Must be inferior to 30");
            }
            PRECISION_FACTOR_REFLECTION.push(uint256(10 ** (40 - decimalsdividendToken)));
        }

        rewardPerBlock = _rewardPerBlock;

        require(_depositFee < MAX_FEE, "Invalid deposit fee");
        require(_withdrawFee < MAX_FEE, "Invalid withdraw fee");

        depositFee = _depositFee;
        withdrawFee = _withdrawFee;

        walletA = msg.sender;

        uniRouterAddress = _uniRouter;
        earnedToStakedPath = _earnedToStakedPath;
    }

    /*
    * @notice Deposit staked tokens and collect reward tokens (if any)
    * @param _amount: amount to withdraw (in earnedToken)
    */
    function deposit(uint256 _amount) external payable nonReentrant {
        require(startBlock > 0 && startBlock < block.number, "Staking hasn't started yet");
        require(_amount > 0, "Amount should be greator than 0");

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
                earnedToken.safeTransfer(address(msg.sender), pending);

                if (totalEarned > pending) {
                    totalEarned = totalEarned - pending;
                } else {
                    totalEarned = 0;
                }
                paidRewards = paidRewards + pending;
            }

            for (uint256 i = 0; i < dividendTokens.length; i++) {
                uint256 pendingReflection =
                    (user.amount * accDividendPerShare[i]) / PRECISION_FACTOR_REFLECTION[i] - user.reflectionDebt[i];
                pendingReflection = estimateDividendAmount(i, pendingReflection);
                if (pendingReflection > 0) {
                    if (address(dividendTokens[i]) == address(0x0)) {
                        payable(msg.sender).transfer(pendingReflection);
                    } else {
                        IERC20(dividendTokens[i]).safeTransfer(address(msg.sender), pendingReflection);
                    }
                    totalReflections[i] = totalReflections[i] - pendingReflection;
                }
            }
        }

        uint256 beforeAmount = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 afterAmount = stakingToken.balanceOf(address(this));

        uint256 realAmount = afterAmount - beforeAmount;
        if (depositFee > 0) {
            uint256 fee = (realAmount * depositFee) / 10000;
            if (fee > 0) {
                stakingToken.safeTransfer(walletA, fee);
                realAmount = realAmount - fee;
            }
        }

        user.amount = user.amount + realAmount;
        totalStaked = totalStaked + realAmount;

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        if (user.reflectionDebt.length == 0) {
            for (uint256 i = 0; i < dividendTokens.length; i++) {
                user.reflectionDebt.push(0);
            }
        }
        for (uint256 i = 0; i < dividendTokens.length; i++) {
            user.reflectionDebt[i] = (user.amount * accDividendPerShare[i]) / PRECISION_FACTOR_REFLECTION[i];
        }

        emit Deposit(msg.sender, realAmount);
    }

    /*
    * @notice Withdraw staked tokens and collect reward tokens
    * @param _amount: amount to withdraw (in earnedToken)
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
                earnedToken.safeTransfer(address(msg.sender), pending);

                if (totalEarned > pending) {
                    totalEarned = totalEarned - pending;
                } else {
                    totalEarned = 0;
                }
                paidRewards = paidRewards + pending;
            }

            for (uint256 i = 0; i < dividendTokens.length; i++) {
                uint256 pendingReflection =
                    (user.amount * accDividendPerShare[i]) / PRECISION_FACTOR_REFLECTION[i] - user.reflectionDebt[i];
                pendingReflection = estimateDividendAmount(i, pendingReflection);
                if (pendingReflection > 0) {
                    if (address(dividendTokens[i]) == address(0x0)) {
                        payable(msg.sender).transfer(pendingReflection);
                    } else {
                        IERC20(dividendTokens[i]).safeTransfer(address(msg.sender), pendingReflection);
                    }
                    totalReflections[i] = totalReflections[i] - pendingReflection;
                }
            }
        }

        uint256 realAmount = _amount;
        if (user.amount < _amount) {
            realAmount = user.amount;
        }

        user.amount = user.amount - realAmount;
        totalStaked = totalStaked - realAmount;

        if (withdrawFee > 0) {
            uint256 fee = (realAmount * withdrawFee) / 10000;
            if (fee > 0) {
                stakingToken.safeTransfer(walletA, fee);
                realAmount = realAmount - fee;
            }
        }

        stakingToken.safeTransfer(address(msg.sender), realAmount);

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
        for (uint256 i = 0; i < dividendTokens.length; i++) {
            user.reflectionDebt[i] = (user.amount * accDividendPerShare[i]) / PRECISION_FACTOR_REFLECTION[i];
        }

        emit Withdraw(msg.sender, _amount);
    }

    function claimReward() external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();
        _updatePool();

        if (user.amount == 0) return;

        uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
        if (pending > 0) {
            require(availableRewardTokens() >= pending, "Insufficient reward tokens");
            earnedToken.safeTransfer(address(msg.sender), pending);

            if (totalEarned > pending) {
                totalEarned = totalEarned - pending;
            } else {
                totalEarned = 0;
            }
            paidRewards = paidRewards + pending;
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
    }

    function claimDividend() external payable nonReentrant {
        if (startBlock == 0) return;

        _transferPerformanceFee();
        _updatePool();

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) return;

        for (uint256 i = 0; i < dividendTokens.length; i++) {
            uint256 pendingReflection =
                (user.amount * accDividendPerShare[i]) / PRECISION_FACTOR_REFLECTION[i] - user.reflectionDebt[i];
            pendingReflection = estimateDividendAmount(i, pendingReflection);
            if (pendingReflection > 0) {
                if (address(dividendTokens[i]) == address(0x0)) {
                    payable(msg.sender).transfer(pendingReflection);
                } else {
                    IERC20(dividendTokens[i]).safeTransfer(address(msg.sender), pendingReflection);
                }
                totalReflections[i] = totalReflections[i] - pendingReflection;
            }

            user.reflectionDebt[i] = (user.amount * accDividendPerShare[i]) / PRECISION_FACTOR_REFLECTION[i];
        }
    }

    function compoundReward() external payable nonReentrant {
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

            if (address(stakingToken) != address(earnedToken)) {
                uint256 beforeAmount = stakingToken.balanceOf(address(this));
                _safeSwap(pending, earnedToStakedPath, address(this));
                uint256 afterAmount = stakingToken.balanceOf(address(this));
                pending = afterAmount - beforeAmount;
            }

            if (hasUserLimit) {
                require(pending + user.amount <= poolLimitPerUser, "User amount above limit");
            }

            totalStaked = totalStaked + pending;
            user.amount = user.amount + pending;
            for (uint256 i = 0; i < dividendTokens.length; i++) {
                user.reflectionDebt[i] =
                    user.reflectionDebt[i] + (pending * accDividendPerShare[i]) / PRECISION_FACTOR_REFLECTION[i];
            }

            emit Deposit(msg.sender, pending);
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
    }

    function compoundDividend() external nonReentrant {}

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "should pay small gas to compound or harvest");

        payable(buyBackWallet).transfer(performanceFee);
        if (msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value - performanceFee);
        }
    }

    /*
    * @notice Withdraw staked tokens without caring about rewards
    * @dev Needs to be for emergency.
    */

    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        for (uint256 i = 0; i < dividendTokens.length; i++) {
            user.reflectionDebt[i] = 0;
        }

        if (amountToTransfer > 0) {
            stakingToken.safeTransfer(address(msg.sender), amountToTransfer);
            totalStaked = totalStaked - amountToTransfer;
        }

        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    /**
     * @notice Available amount of reward token
     */
    function availableRewardTokens() public view returns (uint256) {
        uint256 _amount = earnedToken.balanceOf(address(this));
        if (address(earnedToken) == address(stakingToken)) {
            if (_amount < totalStaked) return 0;
            return _amount - totalStaked;
        }

        return _amount;
    }

    /**
     * @notice Available amount of reflection token
     */
    function availableDividendTokens(uint256 index) public view returns (uint256) {
        if (address(dividendTokens[index]) == address(0x0)) {
            return address(this).balance;
        }

        uint256 _amount = IERC20(dividendTokens[index]).balanceOf(address(this));

        if (address(dividendTokens[index]) == address(earnedToken)) {
            if (_amount < totalEarned) return 0;
            _amount = _amount - totalEarned;
        }

        if (address(dividendTokens[index]) == address(stakingToken)) {
            if (_amount < totalStaked) return 0;
            _amount = _amount - totalStaked;
        }

        return _amount;
    }

    function insufficientRewards() external view returns (uint256) {
        uint256 adjustedShouldTotalPaid = shouldTotalPaid;
        uint256 remainRewards = availableRewardTokens() + paidRewards;

        if (startBlock == 0) {
            adjustedShouldTotalPaid = adjustedShouldTotalPaid + rewardPerBlock * duration * 28800;
        } else {
            uint256 remainBlocks = _getMultiplier(lastRewardBlock, bonusEndBlock);
            adjustedShouldTotalPaid = adjustedShouldTotalPaid + rewardPerBlock * remainBlocks;
        }

        if (remainRewards >= adjustedShouldTotalPaid) return 0;

        return adjustedShouldTotalPaid - remainRewards;
    }

    /*
    * @notice View function to see pending reward on frontend.
    * @param _user: user address
    * @return Pending reward for a given user
    */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        uint256 adjustedTokenPerShare = accTokenPerShare;
        if (block.number > lastRewardBlock && totalStaked != 0 && lastRewardBlock > 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 rewards = multiplier * rewardPerBlock;

            adjustedTokenPerShare = accTokenPerShare + ((rewards * PRECISION_FACTOR) / totalStaked);
        }
        return (user.amount * adjustedTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
    }

    function pendingDividends(address _user) external view returns (uint256[] memory data) {
        data = new uint256[](dividendTokens.length);
        if (totalStaked == 0) return data;

        UserInfo storage user = userInfo[_user];
        if (user.amount == 0) return data;

        for (uint256 i = 0; i < dividendTokens.length; i++) {
            uint256 reflectionAmount = availableDividendTokens(i);
            if (reflectionAmount < totalReflections[i]) {
                reflectionAmount = totalReflections[i];
            }

            uint256 sTokenBal = totalStaked;
            uint256 eTokenBal = availableRewardTokens();
            if (address(stakingToken) == address(earnedToken)) {
                sTokenBal = sTokenBal + eTokenBal;
            }

            uint256 adjustedReflectionPerShare = accDividendPerShare[i]
                + (((reflectionAmount - totalReflections[i]) * PRECISION_FACTOR_REFLECTION[i]) / sTokenBal);

            uint256 pendingReflection =
                (user.amount * adjustedReflectionPerShare) / PRECISION_FACTOR_REFLECTION[i] - user.reflectionDebt[i];
            data[i] = pendingReflection;
        }

        return data;
    }

    /**
     *
     * Admin Methods
     *
     */
    function harvest() external onlyOwner {
        _updatePool();

        for (uint256 i = 0; i < dividendTokens.length; i++) {
            reflections[i] = estimateDividendAmount(i, reflections[i]);
            if (reflections[i] > 0) {
                if (address(dividendTokens[i]) == address(0x0)) {
                    payable(walletA).transfer(reflections[i]);
                } else {
                    IERC20(dividendTokens[i]).safeTransfer(walletA, reflections[i]);
                }

                totalReflections[i] = totalReflections[i] - reflections[i];
                reflections[i] = 0;
            }
        }
    }

    /*
    * @notice Deposit reward token
    * @dev Only call by owner. Needs to be for deposit of reward token when reflection token is same with reward token.
    */
    function depositRewards(uint256 _amount) external onlyOwner nonReentrant {
        require(_amount > 0, "invalid amount");

        uint256 beforeAmt = earnedToken.balanceOf(address(this));
        earnedToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = earnedToken.balanceOf(address(this));

        totalEarned = totalEarned + afterAmt - beforeAmt;
    }

    function increaseEmissionRate(uint256 _amount) external onlyOwner {
        require(startBlock > 0, "pool is not started");
        require(bonusEndBlock > block.number, "pool was already finished");
        require(_amount > 0, "invalid amount");

        _updatePool();

        uint256 beforeAmt = earnedToken.balanceOf(address(this));
        earnedToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = earnedToken.balanceOf(address(this));

        totalEarned = totalEarned + afterAmt - beforeAmt;

        uint256 remainRewards = availableRewardTokens() + paidRewards;
        if (remainRewards > shouldTotalPaid) {
            remainRewards = remainRewards - shouldTotalPaid;

            uint256 remainBlocks = bonusEndBlock - block.number;
            rewardPerBlock = remainRewards / remainBlocks;
            emit NewRewardPerBlock(rewardPerBlock);
        }
    }

    /*
    * @notice Withdraw reward token
    * @dev Only callable by owner. Needs to be for emergency.
    */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(block.number > bonusEndBlock, "Pool is running");
        require(availableRewardTokens() >= _amount, "Insufficient reward tokens");

        earnedToken.safeTransfer(address(msg.sender), _amount);

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
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(earnedToken), "Cannot be reward token");

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

    function startReward() external onlyOwner {
        require(startBlock == 0, "Pool was already started");

        startBlock = block.number + 100;
        bonusEndBlock = startBlock + duration * 28800;
        lastRewardBlock = startBlock;

        emit NewStartAndEndBlocks(startBlock, bonusEndBlock);
    }

    function stopReward() external onlyOwner {
        _updatePool();

        uint256 remainRewards = availableRewardTokens() + paidRewards;
        if (remainRewards > shouldTotalPaid) {
            remainRewards = remainRewards - shouldTotalPaid;
            earnedToken.transfer(msg.sender, remainRewards);

            if (totalEarned > remainRewards) {
                totalEarned = totalEarned - remainRewards;
            } else {
                totalEarned = 0;
            }
        }

        bonusEndBlock = block.number;
        emit RewardsStop(bonusEndBlock);
    }

    function updateEndBlock(uint256 _endBlock) external onlyOwner {
        require(startBlock > 0, "Pool is not started");
        require(bonusEndBlock > block.number, "Pool was already finished");
        require(_endBlock > block.number && _endBlock > startBlock, "Invalid end block");
        bonusEndBlock = _endBlock;
        emit EndBlockUpdated(_endBlock);
    }

    /*
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

    /*
    * @notice Update reward per block
    * @dev Only callable by owner.
    * @param _rewardPerBlock: the reward per block
    */
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        // require(block.number < startBlock, "Pool was already started");

        rewardPerBlock = _rewardPerBlock;
        emit NewRewardPerBlock(_rewardPerBlock);
    }

    function setServiceInfo(address _buyBackWallet, uint256 _fee) external {
        require(msg.sender == buyBackWallet, "setServiceInfo: FORBIDDEN");
        require(_buyBackWallet != address(0x0), "Invalid address");

        buyBackWallet = _buyBackWallet;
        performanceFee = _fee;

        emit ServiceInfoUpadted(_buyBackWallet, _fee);
    }

    function updateWalletA(address _walletA) external onlyOwner {
        require(_walletA != address(0x0) || _walletA != walletA, "Invalid address");

        walletA = _walletA;
        emit WalletAUpdated(_walletA);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(startBlock == 0, "Pool was already started");
        require(_duration >= 30, "lower limit reached");

        duration = _duration;
        emit DurationUpdated(_duration);
    }

    function setSettings(
        uint256 _depositFee,
        uint256 _withdrawFee,
        uint256 _slippageFactor,
        address _uniRouter,
        address[] memory _earnedToStakedPath
    ) external onlyOwner {
        require(_depositFee < MAX_FEE, "Invalid deposit fee");
        require(_withdrawFee < MAX_FEE, "Invalid withdraw fee");
        require(_slippageFactor <= slippageFactorUL, "_slippageFactor too high");

        depositFee = _depositFee;
        withdrawFee = _withdrawFee;

        slippageFactor = _slippageFactor;
        uniRouterAddress = _uniRouter;
        earnedToStakedPath = _earnedToStakedPath;

        emit SetSettings(_depositFee, _withdrawFee, _slippageFactor, _uniRouter, _earnedToStakedPath);
    }

    /*
    * @notice Update reward variables of the given pool to be up-to-date.
    */
    function _updatePool() internal {
        // calc reflection rate
        if (totalStaked > 0) {
            uint256 sTokenBal = totalStaked;
            uint256 eTokenBal = availableRewardTokens();
            if (address(stakingToken) == address(earnedToken)) {
                sTokenBal = sTokenBal + eTokenBal;
            }

            for (uint256 i = 0; i < dividendTokens.length; i++) {
                uint256 reflectionAmount = availableDividendTokens(i);
                if (reflectionAmount < totalReflections[i]) {
                    reflectionAmount = totalReflections[i];
                }

                accDividendPerShare[i] = accDividendPerShare[i]
                    + (((reflectionAmount - totalReflections[i]) * PRECISION_FACTOR_REFLECTION[i]) / sTokenBal);

                if (address(stakingToken) == address(earnedToken)) {
                    reflections[i] = reflections[i] + ((reflectionAmount - totalReflections[i]) * eTokenBal) / sTokenBal;
                }
                totalReflections[i] = reflectionAmount;
            }
        }

        if (block.number <= lastRewardBlock || lastRewardBlock == 0) {
            return;
        }

        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 _reward = multiplier * rewardPerBlock;
        accTokenPerShare = accTokenPerShare + ((_reward * PRECISION_FACTOR) / totalStaked);

        lastRewardBlock = block.number;
        shouldTotalPaid = shouldTotalPaid + _reward;
    }

    function estimateDividendAmount(uint256 index, uint256 amount) internal view returns (uint256) {
        uint256 dTokenBal = availableDividendTokens(index);
        if (amount > totalReflections[index]) amount = totalReflections[index];
        if (amount > dTokenBal) amount = dTokenBal;
        return amount;
    }

    /*
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

    function _safeSwap(uint256 _amountIn, address[] memory _path, address _to) internal {
        uint256[] memory amounts = IUniRouter02(uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length - 1];

        IERC20(_path[0]).safeApprove(uniRouterAddress, _amountIn);
        IUniRouter02(uniRouterAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn, (amountOut * slippageFactor) / 1000, _path, _to, block.timestamp + 600
        );
    }

    receive() external payable {}
}
