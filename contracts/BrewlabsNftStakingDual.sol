// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BrewlabsNftStakingDual is Ownable, IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    uint256 private constant BLOCKS_PER_DAY = 28800;
    uint256 private PRECISION_FACTOR;

    // Whether it is initialized
    bool public isInitialized;
    uint256 public duration = 365; // 365 days

    // The block number when staking starts.
    uint256 public startBlock;
    // The block number when staking ends.
    uint256 public bonusEndBlock;
    // tokens created per block.
    uint256[2] public rewardsPerBlock;
    // The block number of the last pool update
    uint256 public lastRewardBlock;

    address public treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
    uint256 public performanceFee = 0.0035 ether;
    bool public autoAdjustableForRewardRate = true;

    // The staked token
    IERC721 public stakingNft;
    // The earned token
    address[2] public earnedTokens;
    // Accrued token per share
    uint256[2] public accTokenPerShares;
    uint256 public oneTimeLimit = 40;

    uint256 public totalStaked;
    uint256[2] private paidRewards;
    uint256[2] private shouldTotalPaid;

    struct UserInfo {
        uint256 amount; // number of staked NFTs
        uint256[] tokenIds; // staked tokenIds
        uint256[2] rewardDebt; // Reward debt
    }
    // Info of each user that stakes tokenIds

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256[] tokenIds);
    event Withdraw(address indexed user, uint256[] tokenIds);
    event Claim(address indexed user, address indexed token, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256[] tokenIds);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);

    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardsPerBlock(uint256[2] rewardsPerBlock);
    event RewardsStop(uint256 blockNumber);
    event EndBlockUpdated(uint256 blockNumber);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event DurationUpdated(uint256 duration);
    event SetAutoAdjustableForRewardRate(bool status);

    constructor() {}

    /**
     * @notice Initialize the contract
     * @param _stakingNft: nft address to stake
     * @param _earnedTokens: earned token addresses
     * @param _rewardsPerBlock: rewards per block (in earnedToken)
     */
    function initialize(IERC721 _stakingNft, address[2] memory _earnedTokens, uint256[2] memory _rewardsPerBlock)
        external
        onlyOwner
    {
        require(!isInitialized, "Already initialized");

        // Make this contract initialized
        isInitialized = true;

        stakingNft = _stakingNft;
        earnedTokens = _earnedTokens;
        rewardsPerBlock = _rewardsPerBlock;

        PRECISION_FACTOR = uint256(10 ** 30);
    }

    /**
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _tokenIds: list of tokenIds to stake
     */
    function deposit(uint256[] memory _tokenIds) external payable nonReentrant {
        require(startBlock > 0 && startBlock < block.number, "Staking hasn't started yet");
        require(_tokenIds.length > 0, "must add at least one tokenId");
        require(_tokenIds.length <= oneTimeLimit, "cannot exceed one-time limit");

        _transferPerformanceFee();
        _updatePool();

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount > 0) {
            _transferRewards(msg.sender, 0);
            _transferRewards(msg.sender, 1);
        }

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];
            stakingNft.safeTransferFrom(msg.sender, address(this), tokenId);
            user.tokenIds.push(tokenId);
        }
        user.amount += _tokenIds.length;
        user.rewardDebt[0] = (user.amount * accTokenPerShares[0]) / PRECISION_FACTOR;
        user.rewardDebt[1] = (user.amount * accTokenPerShares[1]) / PRECISION_FACTOR;

        totalStaked = totalStaked + _tokenIds.length;
        emit Deposit(msg.sender, _tokenIds);

        // update rate for block rewards
        if (autoAdjustableForRewardRate) _updateRewardRate();
    }

    /**
     * @notice Withdraw staked tokenIds and collect reward tokens
     * @param _amount: number of tokenIds to unstake
     */
    function withdraw(uint256 _amount) external payable nonReentrant {
        require(_amount > 0, "Amount should be greator than 0");
        require(_amount <= oneTimeLimit, "cannot exceed one-time limit");

        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _transferPerformanceFee();
        _updatePool();

        if (user.amount > 0) {
            _transferRewards(msg.sender, 0);
            _transferRewards(msg.sender, 1);
        }

        uint256[] memory _tokenIds = new uint256[](_amount);
        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = user.tokenIds[user.tokenIds.length - 1];
            user.tokenIds.pop();

            _tokenIds[i] = tokenId;
            stakingNft.safeTransferFrom(address(this), msg.sender, tokenId);
        }
        user.amount = user.amount - _amount;
        user.rewardDebt[0] = (user.amount * accTokenPerShares[0]) / PRECISION_FACTOR;
        user.rewardDebt[1] = (user.amount * accTokenPerShares[1]) / PRECISION_FACTOR;

        totalStaked = totalStaked - _amount;
        emit Withdraw(msg.sender, _tokenIds);

        if (autoAdjustableForRewardRate) _updateRewardRate();
    }

    function claimReward(uint8 _index) external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();
        _updatePool();

        if (user.amount > 0) {
            _transferRewards(msg.sender, _index);
            user.rewardDebt[_index] = (user.amount * accTokenPerShares[_index]) / PRECISION_FACTOR;
        }
        if (autoAdjustableForRewardRate) _updateRewardRate();
    }

    function claimRewardAll() external payable nonReentrant {
        _transferPerformanceFee();
        _updatePool();

        if (userInfo[msg.sender].amount > 0) {
            _transferRewards(msg.sender, 0);
            _transferRewards(msg.sender, 1);

            UserInfo storage user = userInfo[msg.sender];
            user.rewardDebt[0] = (user.amount * accTokenPerShares[0]) / PRECISION_FACTOR;
            user.rewardDebt[1] = (user.amount * accTokenPerShares[1]) / PRECISION_FACTOR;
        }
        if (autoAdjustableForRewardRate) _updateRewardRate();
    }

    function _transferRewards(address _user, uint8 _index) internal {
        UserInfo storage user = userInfo[_user];
        uint256 pending = (user.amount * accTokenPerShares[_index]) / PRECISION_FACTOR - user.rewardDebt[_index];
        if (pending == 0) return;

        require(availableRewardTokens(_index) >= pending, "Insufficient reward tokens");
        paidRewards[_index] += pending;

        _transferTokens(earnedTokens[_index], _user, pending);
        emit Claim(_user, earnedTokens[_index], pending);
    }

    function _transferTokens(address _token, address _to, uint256 _amount) internal {
        if (_token == address(0x0)) {
            payable(_to).transfer(_amount);
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    function _updateRewardRate() internal {
        if (bonusEndBlock <= block.number) return;

        bool bUpdated = false;
        uint256 remainBlocks = bonusEndBlock - block.number;
        for (uint8 i = 0; i < 2; i++) {
            uint256 remainRewards = availableRewardTokens(i) + paidRewards[i];
            if (remainRewards > shouldTotalPaid[i]) {
                remainRewards = remainRewards - shouldTotalPaid[i];
                rewardsPerBlock[i] = remainRewards / remainBlocks;
                bUpdated = true;
            }
        }
        if (bUpdated) {
            emit NewRewardsPerBlock(rewardsPerBlock);
        }
    }

    /**
     * @notice Withdraw staked NFTs without caring about rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 _amount = user.amount;
        if (_amount > oneTimeLimit) _amount = oneTimeLimit;

        uint256[] memory _tokenIds = new uint256[](_amount);
        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = user.tokenIds[user.tokenIds.length - 1];
            user.tokenIds.pop();

            _tokenIds[i] = tokenId;
            stakingNft.safeTransferFrom(address(this), msg.sender, tokenId);
        }
        user.amount = user.amount - _amount;
        user.rewardDebt[0] = (user.amount * accTokenPerShares[0]) / PRECISION_FACTOR;
        user.rewardDebt[1] = (user.amount * accTokenPerShares[1]) / PRECISION_FACTOR;
        totalStaked = totalStaked - _amount;

        emit EmergencyWithdraw(msg.sender, _tokenIds);
    }

    function stakedInfo(address _user) external view returns (uint256, uint256[] memory) {
        return (userInfo[_user].amount, userInfo[_user].tokenIds);
    }

    /**
     * @notice Available amount of reward token
     */
    function availableRewardTokens(uint8 _index) public view returns (uint256) {
        if (earnedTokens[_index] == address(0x0)) return address(this).balance;
        return IERC20(earnedTokens[_index]).balanceOf(address(this));
    }

    function insufficientRewards() external view returns (uint256) {
        uint256 adjustedShouldTotalPaid = shouldTotalPaid[0];
        uint256 remainRewards = availableRewardTokens(0) + paidRewards[0];

        if (startBlock == 0) {
            adjustedShouldTotalPaid += rewardsPerBlock[0] * duration * BLOCKS_PER_DAY;
        } else {
            uint256 remainBlocks = _getMultiplier(lastRewardBlock, bonusEndBlock);
            adjustedShouldTotalPaid += rewardsPerBlock[0] * remainBlocks;
        }

        if (remainRewards >= adjustedShouldTotalPaid) return 0;
        return adjustedShouldTotalPaid - remainRewards;
    }

    /**
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @param _index: index of earning token (0 - earning token, 1 - eth)
     * @return Pending reward for a given user
     */
    function pendingReward(address _user, uint8 _index) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        uint256 adjustedTokenPerShare = accTokenPerShares[_index];
        if (block.number > lastRewardBlock && totalStaked > 0 && lastRewardBlock > 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 rewards = multiplier * rewardsPerBlock[_index];

            adjustedTokenPerShare += (rewards * PRECISION_FACTOR) / totalStaked;
        }

        return (user.amount * adjustedTokenPerShare) / PRECISION_FACTOR - user.rewardDebt[_index];
    }

    /**
     * Admin Methods
     */
    function increaseEmissionRate(uint8 _index, uint256 _amount) external payable onlyOwner {
        require(startBlock > 0, "pool is not started");
        require(bonusEndBlock > block.number, "pool was already finished");
        require(_amount > 0, "invalid amount");

        _updatePool();

        if (earnedTokens[_index] != address(0x0)) {
            IERC20(earnedTokens[1]).safeTransferFrom(msg.sender, address(this), _amount);
        }

        uint256 remainRewards = availableRewardTokens(_index) + paidRewards[_index];
        if (remainRewards > shouldTotalPaid[_index]) {
            remainRewards = remainRewards - shouldTotalPaid[_index];

            uint256 remainBlocks = bonusEndBlock - block.number;
            rewardsPerBlock[_index] = remainRewards / remainBlocks;
            emit NewRewardsPerBlock(rewardsPerBlock);
        }
    }

    /*
    * @notice Withdraw reward token
    * @dev Only callable by owner. Needs to be for emergency.
    */
    function emergencyRewardWithdraw(uint256 _amount, uint8 _index) external onlyOwner {
        require(block.number > bonusEndBlock, "Pool is running");
        if (_index == 0) {
            require(availableRewardTokens(0) >= _amount, "Insufficient reward tokens");
            if (_amount == 0) _amount = availableRewardTokens(0);
            IERC20(earnedTokens[0]).safeTransfer(msg.sender, _amount);
        } else {
            if (earnedTokens[1] == address(0x0)) {
                payable(msg.sender).transfer(address(this).balance);
            } else {
                IERC20(earnedTokens[1]).safeTransfer(msg.sender, IERC20(earnedTokens[1]).balanceOf(address(this)));
            }
        }
    }

    function startReward() external onlyOwner {
        require(startBlock == 0, "Pool was already started");

        startBlock = block.number + 100;
        bonusEndBlock = startBlock + duration * BLOCKS_PER_DAY;
        lastRewardBlock = startBlock;

        emit NewStartAndEndBlocks(startBlock, bonusEndBlock);
    }

    function stopReward() external onlyOwner {
        _updatePool();

        uint256 remainRewards = availableRewardTokens(0) + paidRewards[0];
        if (remainRewards > shouldTotalPaid[0]) {
            remainRewards = remainRewards - shouldTotalPaid[0];
            IERC20(earnedTokens[0]).transfer(msg.sender, remainRewards);
        }

        remainRewards = address(this).balance;
        if (earnedTokens[1] != address(0x0)) {
            remainRewards = IERC20(earnedTokens[1]).balanceOf(address(this));
        }

        remainRewards += paidRewards[1];
        if (remainRewards > shouldTotalPaid[1]) {
            remainRewards = remainRewards - shouldTotalPaid[1];
            _transferTokens(earnedTokens[1], msg.sender, remainRewards);
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

    /**
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardsPerBlock: the reward per block
     * @param _index: index of reward token
     */
    function updateRewardsPerBlock(uint256 _rewardsPerBlock, uint8 _index) external onlyOwner {
        _updatePool();
        rewardsPerBlock[_index] = _rewardsPerBlock;
        emit NewRewardsPerBlock(rewardsPerBlock);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(_duration >= 30, "lower limit reached");

        _updatePool();
        duration = _duration;
        if (startBlock > 0) {
            bonusEndBlock = startBlock + duration * BLOCKS_PER_DAY;
            require(bonusEndBlock > block.number, "invalid duration");
        }
        emit DurationUpdated(_duration);
    }

    function setAutoAdjustableForRewardRate(bool _status) external onlyOwner {
        autoAdjustableForRewardRate = _status;
        emit SetAutoAdjustableForRewardRate(_status);
    }

    function setServiceInfo(address _treasury, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_treasury != address(0x0), "Invalid address");

        treasury = _treasury;
        performanceFee = _fee;
        emit ServiceInfoUpadted(_treasury, _fee);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address _token) external onlyOwner {
        require(_token != address(earnedTokens[0]), "Cannot be reward token");
        require(_token != address(earnedTokens[1]), "Cannot be reward token");

        uint256 amount = address(this).balance;
        if (_token == address(0x0)) {
            payable(msg.sender).transfer(amount);
        } else {
            amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(address(msg.sender), amount);
        }

        emit AdminTokenRecovered(_token, amount);
    }

    /*
    * @notice Update reward variables of the given pool to be up-to-date.
    */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock || lastRewardBlock == 0) return;
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 _reward = multiplier * rewardsPerBlock[0];
        accTokenPerShares[0] += (_reward * PRECISION_FACTOR) / totalStaked;
        shouldTotalPaid[0] += _reward;

        _reward = multiplier * rewardsPerBlock[1];
        accTokenPerShares[1] += (_reward * PRECISION_FACTOR) / totalStaked;
        shouldTotalPaid[1] += _reward;

        lastRewardBlock = block.number;
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

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "should pay small gas");

        payable(treasury).transfer(performanceFee);
        if (msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value - performanceFee);
        }
    }

    /**
     * onERC721Received(address operator, address from, uint256 tokenId, bytes data) → bytes4
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external view override returns (bytes4) {
        require(msg.sender == address(stakingNft), "not enabled NFT");
        return _ERC721_RECEIVED;
    }

    receive() external payable {}
}
