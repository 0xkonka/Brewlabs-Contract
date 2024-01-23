// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBrewlabsSwapFeeManager} from "../libs/IBrewlabsSwapFeeManager.sol";
import "../libs/IWETH.sol";

contract BrewlabsDualFarmImpl is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool private isInitialized;

    uint256 private BLOCKS_PER_DAY;
    uint256 private PERCENT_PRECISION;
    uint256 public PRECISION_FACTOR;
    uint256 public MAX_FEE;
    address internal constant WETH_ADDRESS = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    // The staked token
    IERC20 public lpToken;
    IERC20[2] public rewardTokens;

    uint256 public duration;
    // The block number when staking starts.
    uint256 public startBlock;
    // The block number when staking ends.
    uint256 public bonusEndBlock;
    // tokens created per block.
    uint256[2] public rewardsPerBlock;
    // The block number of the last pool update
    uint256 public lastRewardBlock;
    // Accrued token per share
    uint256[2] public accTokensPerShare;
    // The deposit & withdraw fee
    uint256 public depositFee;
    uint256 public withdrawFee;

    // service fees
    address public feeAddress;
    address public treasury;
    uint256 public performanceFee;
    uint256 public rewardFee;

    address feeManager;
    address public deployer;
    address public operator;

    struct UserInfo {
        uint256 amount; // How many staked lp the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 rewardDebt1; // Reflection debt
    }

    // Info of each user that stakes lpToken
    mapping(address => UserInfo) public userInfo;

    uint256 public totalStaked;
    uint256[2] private totalEarned;
    uint256[2] private totalRewardStaked;

    uint256[2] public paidRewards;
    uint256[2] private shouldTotalPaid;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256[2] amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);

    event NewRewardsPerBlock(uint256[2] rewardsPerBlock);
    event RewardsStart(uint256 startBlock, uint256 endBlock);
    event RewardsStop(uint256 blockNumber);
    event EndBlockChanged(uint256 blockNumber);

    event DurationChanged(uint256 duration);
    event FeeManagerChanged(address newMgr);
    event ServiceInfoChanged(address addr, uint256 fee);
    event SetAutoAdjustableForRewardRate(bool status);
    event SetRewardFee(uint256 fee);
    event OperatorTransferred(address oldOperator, address newOperator);

    event SetSettings(uint256 depositFee, uint256 withdrawFee, address feeAddr);

    modifier onlyAdmin() {
        require(
            msg.sender == owner() || msg.sender == operator,
            "Caller is not owner or operator"
        );
        _;
    }

    constructor() {}

    /**
     * @notice Initialize the contract
     * @param _lpToken: LP address
     * @param _rewardTokens: reward token addresses
     * @param _rewardsPerBlock: rewards per block (in rewardToken)
     * @param _depositFee: deposit fee
     * @param _withdrawFee: withdraw fee
     * @param _feeManager: withdraw fee
     * @param _owner: owner address
     * @param _deployer: owner address
     */
    function initialize(
        IERC20 _lpToken,
        IERC20[2] memory _rewardTokens,
        uint256[2] memory _rewardsPerBlock,
        uint256 _depositFee,
        uint256 _withdrawFee,
        uint256 _duration,
        address _owner,
        address _feeManager,
        address _deployer
    ) external {
        require(!isInitialized, "Already initialized");
        require(
            owner() == address(0x0) || msg.sender == owner(),
            "Not allowed"
        );

        // Make this contract initialized
        isInitialized = true;

        PERCENT_PRECISION = 10000;
        BLOCKS_PER_DAY = 39723;
        MAX_FEE = 2000;
        PRECISION_FACTOR = 10 ** 18;

        duration = _duration;
        treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
        performanceFee = 1.3 ether;

        lpToken = _lpToken;
        rewardTokens = _rewardTokens;
        rewardsPerBlock = _rewardsPerBlock;

        feeManager = _feeManager;
        deployer = _deployer;
        operator = _deployer;

        feeAddress = _deployer;

        require(_depositFee <= MAX_FEE, "Invalid deposit fee");
        require(_withdrawFee <= MAX_FEE, "Invalid withdraw fee");
        depositFee = _depositFee;
        withdrawFee = _withdrawFee;

        _transferOwnership(_owner);
    }

    /**
     * @notice Deposit LP tokens and collect reward tokens (if any)
     * @param _amount: amount to stake (in lp token)
     */
    function deposit(uint256 _amount) external payable nonReentrant {
        require(
            startBlock > 0 && startBlock < block.number,
            "Farming hasn't started yet"
        );
        require(_amount > 0, "Amount should be greator than 0");

        _transferPerformanceFee();
        _claimReward();

        UserInfo storage user = userInfo[msg.sender];

        uint256 beforeAmt = lpToken.balanceOf(address(this));
        lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 afterAmt = lpToken.balanceOf(address(this));
        uint256 realAmount = afterAmt - beforeAmt;

        if (depositFee > 0) {
            uint256 fee = (realAmount * depositFee) / PERCENT_PRECISION;
            lpToken.safeTransfer(feeAddress, fee);
            realAmount -= fee;
        }
        totalStaked += realAmount;

        user.amount = user.amount + realAmount;
        user.rewardDebt =
            (user.amount * accTokensPerShare[0]) /
            PRECISION_FACTOR;
        user.rewardDebt1 =
            (user.amount * accTokensPerShare[1]) /
            PRECISION_FACTOR;

        emit Deposit(msg.sender, realAmount);

        if (rewardFee > 0) _updateRewardRate();
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
        _claimReward();

        if (withdrawFee > 0) {
            uint256 fee = (_amount * withdrawFee) / PERCENT_PRECISION;
            lpToken.safeTransfer(feeAddress, fee);
            lpToken.safeTransfer(msg.sender, _amount - fee);
        } else {
            lpToken.safeTransfer(msg.sender, _amount);
        }
        totalStaked -= _amount;

        user.amount = user.amount - _amount;
        user.rewardDebt =
            (user.amount * accTokensPerShare[0]) /
            PRECISION_FACTOR;
        user.rewardDebt1 =
            (user.amount * accTokensPerShare[1]) /
            PRECISION_FACTOR;
        emit Withdraw(msg.sender, _amount);

        if (rewardFee > 0) _updateRewardRate();
    }

    function claimReward() external payable nonReentrant {
        _transferPerformanceFee();
        _claimReward();

        UserInfo storage user = userInfo[msg.sender];
        user.rewardDebt =
            (user.amount * accTokensPerShare[0]) /
            PRECISION_FACTOR;
        user.rewardDebt1 =
            (user.amount * accTokensPerShare[1]) /
            PRECISION_FACTOR;
    }

    function _claimReward() internal {
        _claimLpFees();
        _updatePool();
        _updateRewardRate();

        UserInfo memory user = userInfo[msg.sender];
        if (user.amount == 0) return;

        uint256[2] memory pending;
        pending[0] =
            (user.amount * accTokensPerShare[0]) /
            PRECISION_FACTOR -
            user.rewardDebt;
        pending[1] =
            (user.amount * accTokensPerShare[1]) /
            PRECISION_FACTOR -
            user.rewardDebt1;
        if (pending[0] > 0 || pending[1] > 0) {
            if (pending[0] > 0) _claimRewardToken(0, pending[0]);
            if (pending[1] > 0) _claimRewardToken(1, pending[1]);
            emit Claim(msg.sender, pending);
        }
    }

    function _claimRewardToken(uint8 idx, uint256 pending) internal {
        require(
            availableRewardTokens(idx) >= pending,
            "Insufficient reward tokens"
        );
        paidRewards[idx] = paidRewards[idx] + pending;
        pending =
            (pending * (PERCENT_PRECISION - rewardFee)) /
            PERCENT_PRECISION;
        totalEarned[idx] = (totalEarned[idx] > pending)
            ? totalEarned[idx] - pending
            : 0;
        if (address(rewardTokens[idx]) == WETH_ADDRESS) {
            IWETH(WETH_ADDRESS).withdraw(pending);
            payable(msg.sender).transfer(pending);
        } else rewardTokens[idx].safeTransfer(msg.sender, pending);
    }

    function _transferPerformanceFee() internal {
        require(
            msg.value >= performanceFee,
            "should pay small gas to compound or harvest"
        );

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
        if (user.amount == 0) return;

        uint256 amountToTransfer = user.amount;
        lpToken.safeTransfer(address(msg.sender), amountToTransfer);
        totalStaked -= amountToTransfer;

        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardDebt1 = 0;
        emit EmergencyWithdraw(msg.sender, amountToTransfer);
    }

    /**
     * @notice Available amount of reward token
     */
    function availableRewardTokens(uint8 idx) public view returns (uint256) {
        return rewardTokens[idx].balanceOf(address(this));
    }

    function insufficientRewards(uint8 idx) public view returns (uint256) {
        uint256 adjustedShouldTotalPaid = shouldTotalPaid[idx];
        uint256 remainRewards = availableRewardTokens(idx) + paidRewards[idx];

        if (startBlock == 0) {
            adjustedShouldTotalPaid =
                adjustedShouldTotalPaid +
                rewardsPerBlock[idx] *
                duration *
                BLOCKS_PER_DAY;
        } else {
            uint256 remainBlocks = _getMultiplier(
                lastRewardBlock,
                bonusEndBlock
            );
            adjustedShouldTotalPaid =
                adjustedShouldTotalPaid +
                rewardsPerBlock[idx] *
                remainBlocks;
        }

        if (remainRewards >= adjustedShouldTotalPaid) return 0;

        return adjustedShouldTotalPaid - remainRewards;
    }

    /**
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingRewards(
        address _user
    ) external view returns (uint256[2] memory) {
        UserInfo memory user = userInfo[_user];

        uint256[2] memory adjustedTokenPerShare = accTokensPerShare;
        if (
            block.number > lastRewardBlock &&
            totalStaked != 0 &&
            lastRewardBlock > 0
        ) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);

            adjustedTokenPerShare[0] =
                accTokensPerShare[0] +
                ((multiplier * rewardsPerBlock[0] * PRECISION_FACTOR) /
                    totalStaked);
            adjustedTokenPerShare[1] =
                accTokensPerShare[1] +
                ((multiplier * rewardsPerBlock[1] * PRECISION_FACTOR) /
                    totalStaked);
        }

        uint256[2] memory pending;
        pending[0] =
            (user.amount * adjustedTokenPerShare[0]) /
            PRECISION_FACTOR -
            user.rewardDebt;
        pending[1] =
            (user.amount * adjustedTokenPerShare[1]) /
            PRECISION_FACTOR -
            user.rewardDebt1;
        return pending;
    }

    /**
     * Admin Methods
     */

    /**
     * @notice Deposit reward token
     * @dev Only call by owner. Needs to be for deposit of reward token when reflection token is same with reward token.
     */
    function depositRewards(
        uint8 idx,
        uint256 _amount
    ) external onlyAdmin nonReentrant {
        require(_amount > 0, "invalid amount");

        rewardTokens[idx].safeTransferFrom(msg.sender, address(this), _amount);
    }

    function increaseEmissionRate(
        uint8 idx,
        uint256 _amount
    ) external onlyOwner {
        require(_amount > 0, "invalid amount");
        require(startBlock > 0, "pool is not started");
        require(bonusEndBlock > block.number, "pool was already finished");

        _updatePool();

        rewardTokens[idx].safeTransferFrom(msg.sender, address(this), _amount);
        _updateRewardRate();
    }

    function _updateRewardRate() internal {
        if (bonusEndBlock <= block.number) return;

        uint256 remainBlocks = bonusEndBlock - block.number;
        bool bUpdated = false;
        uint256 remainRewards = availableRewardTokens(0) + paidRewards[0];
        if (remainRewards > shouldTotalPaid[0]) {
            remainRewards = remainRewards - shouldTotalPaid[0];
            rewardsPerBlock[0] = remainRewards / remainBlocks;
            bUpdated = true;
        }

        remainRewards = availableRewardTokens(1) + paidRewards[1];
        if (remainRewards > shouldTotalPaid[1]) {
            remainRewards = remainRewards - shouldTotalPaid[1];
            rewardsPerBlock[1] = remainRewards / remainBlocks;
            bUpdated = true;
        }

        if (bUpdated) emit NewRewardsPerBlock(rewardsPerBlock);
    }

    /**
     * @notice Withdraw reward token
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(
        uint8 idx,
        uint256 _amount
    ) external onlyOwner {
        require(block.number > bonusEndBlock, "Pool is running");
        require(
            availableRewardTokens(idx) >= _amount,
            "Insufficient reward tokens"
        );

        if (_amount == 0) _amount = availableRewardTokens(idx);
        rewardTokens[idx].safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address _token) external onlyOwner {
        require(
            _token != address(rewardTokens[0]) &&
                _token != address(rewardTokens[1]),
            "cannot recover reward tokens"
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
        require(
            insufficientRewards(0) == 0 && insufficientRewards(1) == 0,
            "All reward tokens have not been deposited"
        );

        startBlock = block.number + 100;
        bonusEndBlock = startBlock + duration * BLOCKS_PER_DAY;
        lastRewardBlock = startBlock;

        emit RewardsStart(startBlock, bonusEndBlock);
    }

    function stopReward() external onlyAdmin {
        _updatePool();

        uint256 remainRewards = availableRewardTokens(0) + paidRewards[0];
        if (remainRewards > shouldTotalPaid[0]) {
            remainRewards = remainRewards - shouldTotalPaid[0];
            rewardTokens[0].transfer(msg.sender, remainRewards);
        }

        remainRewards = availableRewardTokens(1) + paidRewards[1];
        if (remainRewards > shouldTotalPaid[1]) {
            remainRewards = remainRewards - shouldTotalPaid[1];
            rewardTokens[1].transfer(msg.sender, remainRewards);
        }

        bonusEndBlock = block.number;
        emit RewardsStop(bonusEndBlock);
    }

    function updateEndBlock(uint256 _endBlock) external onlyAdmin {
        require(startBlock > 0, "Pool is not started");
        require(bonusEndBlock > block.number, "Pool was already finished");
        require(
            _endBlock > block.number && _endBlock > startBlock,
            "Invalid end block"
        );
        bonusEndBlock = _endBlock;
        emit EndBlockChanged(_endBlock);
    }

    /**
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardsPerBlock: the reward per block
     */
    function updateEmissionRate(
        uint256[2] memory _rewardsPerBlock
    ) external onlyOwner {
        _updatePool();

        rewardsPerBlock = _rewardsPerBlock;
        emit NewRewardsPerBlock(_rewardsPerBlock);
    }

    function setServiceInfo(address _treasury, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_treasury != address(0x0), "Invalid address");

        treasury = _treasury;
        performanceFee = _fee;

        emit ServiceInfoChanged(_treasury, _fee);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(_duration >= 30, "lower limit reached");

        duration = _duration;
        emit DurationChanged(_duration);

        if (startBlock > 0) {
            bonusEndBlock = startBlock + duration * BLOCKS_PER_DAY;
            require(bonusEndBlock > block.number, "invalid duration");
            emit EndBlockChanged(bonusEndBlock);
        }
    }

    function setRewardFee(uint256 _fee) external onlyOwner {
        require(_fee < PERCENT_PRECISION, "setRewardFee: invalid percentage");

        rewardFee = _fee;
        emit SetRewardFee(_fee);
    }

    function setFeeManager(address _feeManager) external onlyOwner {
        feeManager = _feeManager;
    }

    function transferOperator(address _operator) external onlyAdmin {
        require(_operator != address(0x0), "invalid address");
        emit OperatorTransferred(operator, _operator);
        operator = _operator;
    }

    function setSettings(
        uint256 _depositFee,
        uint256 _withdrawFee,
        address _feeAddr
    ) external onlyOwner {
        require(
            _feeAddr != address(0x0) || _feeAddr != feeAddress,
            "Invalid address"
        );
        require(_depositFee <= MAX_FEE, "Invalid deposit fee");
        require(_withdrawFee <= MAX_FEE, "Invalid withdraw fee");

        depositFee = _depositFee;
        withdrawFee = _withdrawFee;

        feeAddress = _feeAddr;
        emit SetSettings(_depositFee, _withdrawFee, _feeAddr);
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

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        lastRewardBlock = block.number;

        uint256 _reward = multiplier * rewardsPerBlock[0];
        accTokensPerShare[0] += (_reward * PRECISION_FACTOR) / totalStaked;
        shouldTotalPaid[0] = shouldTotalPaid[0] + _reward;

        _reward = multiplier * rewardsPerBlock[1];
        accTokensPerShare[1] += (_reward * PRECISION_FACTOR) / totalStaked;
        shouldTotalPaid[1] = shouldTotalPaid[1] + _reward;
    }

    function _claimLpFees() internal {
        if (feeManager == address(0x0)) return;

        try
            IBrewlabsSwapFeeManager(feeManager).claim(address(lpToken))
        {} catch {}
    }

    /**
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(
        uint256 _from,
        uint256 _to
    ) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to - _from;
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock - _from;
        }
    }

    /**
     * @notice Retrun reward per block for first reward token
     * @dev so it supports interface same as original farm
     */
    function rewardPerBlock() public view returns (uint256) {
        return rewardsPerBlock[0];
    }

    receive() external payable {}
}
