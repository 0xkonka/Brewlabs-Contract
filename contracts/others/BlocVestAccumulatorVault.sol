 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
 
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BlocVestAccumulatorVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // The staked token
    IERC20 public stakingToken;

    // uint256[] public nominated = [7, 14, 30];
    uint256[] public nominated = [1, 2, 3];
    uint256 public bonusRate = 2000;

    struct UserInfo {
        uint256 amount;
        uint256 initialAmount;
        uint256 nominatedCycle;
        uint256 lastDepositTime;
        uint256 lastClaimTime;
        uint256 reward;
        uint256 totalStaked;
        uint256 totalReward;
        bool isNominated;
    }
    mapping(address => UserInfo) public userInfo;
    uint256 public userCount;
    uint256 public totalStaked;

    address public treasury = 0x885A73F551FcC946C688eEFbC10023f4B7Cc48f3;
    // address public treasury = 0x0b7EaCB3EB29B13C31d934bdfe62057BB9763Bb7;
    uint256 public performanceFee = 0.0015 ether;
    // uint256 TIME_UNITS = 1 days;
    uint256 TIME_UNITS = 30 minutes;

    event Deposit(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event CycleNominated(uint256 cycle);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);
    event ServiceInfoUpadted(address addr, uint256 fee);
    event SetBonusRate(uint256 rate);

    constructor(IERC20 _token) {
        stakingToken = _token;
    }

    function deposit(uint256 _amount) external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        require(_amount > 0, "Amount should be greator than 0");
        require(user.nominatedCycle > 0, "not nominate days");
        require(user.lastDepositTime + user.nominatedCycle * TIME_UNITS < block.timestamp, "cannot deposit before pass nominated days");

        _transferPerformanceFee();

        uint256 beforeAmount = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        uint256 afterAmount = stakingToken.balanceOf(address(this));        
        uint256 realAmount = afterAmount - beforeAmount;

        if(user.amount > 0) {
            uint256 claimable = 0;
            if(user.lastClaimTime == user.lastDepositTime) claimable = user.amount; 
            uint256 expireTime = user.lastDepositTime + user.nominatedCycle * TIME_UNITS + TIME_UNITS;
            if(block.timestamp < expireTime && realAmount >= user.initialAmount) {
                claimable = claimable + user.amount * bonusRate / 10000;
            }

            user.reward = user.reward + claimable;
            user.totalReward = user.totalReward + claimable;
        }

        if(user.initialAmount == 0) {
            user.initialAmount = realAmount;
            user.isNominated = true;
            userCount = userCount + 1;
        }

        user.amount = realAmount;
        user.totalStaked = user.totalStaked + realAmount;
        user.lastDepositTime = block.timestamp;
        user.lastClaimTime = block.timestamp;
        totalStaked = totalStaked + realAmount;

        emit Deposit(msg.sender, realAmount);
    }

    function nominatedDays(uint256 _type) external {
        require(_type < nominated.length, "invalid type");
        require(userInfo[msg.sender].isNominated == false, "already nominated");

        UserInfo storage user = userInfo[msg.sender];
        user.nominatedCycle = nominated[_type];

        emit CycleNominated(nominated[_type]);
    }

    function claim() external payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _transferPerformanceFee();

        uint256 expireTime = user.lastDepositTime + user.nominatedCycle * TIME_UNITS;
        if(block.timestamp > expireTime && user.lastClaimTime == user.lastDepositTime) {
            user.reward = user.reward + user.amount;
            user.totalReward = user.totalReward + user.amount;
        }

        uint256 claimable = user.reward;
        uint256 available = stakingToken.balanceOf(address(this));
        if(claimable > available) claimable = available;

        stakingToken.safeTransfer(msg.sender, claimable);

        user.reward = user.reward - claimable;
        user.lastClaimTime = block.timestamp;
        emit Claim(msg.sender, claimable);
    }

    function pendingRewards(address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        
        uint256 expireTime = user.lastDepositTime + user.nominatedCycle * TIME_UNITS;
        if(block.timestamp > expireTime && user.lastClaimTime == user.lastDepositTime) {
            return user.reward + user.amount;
        }
        return user.reward;
    }


    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, 'should pay small gas to compound or harvest');

        payable(treasury).transfer(performanceFee);
        if(msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value - performanceFee);
        }
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @param _amount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if(_token == address(0x0)) {
            payable(msg.sender).transfer(_amount);
        } else {
            IERC20(_token).safeTransfer(address(msg.sender), _amount);
        }

        emit AdminTokenRecovered(_token, _amount);
    }

    function setServiceInfo(address _treasury, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_treasury != address(0x0), "Invalid address");

        treasury = _treasury;
        performanceFee = _fee;

        emit ServiceInfoUpadted(_treasury, _fee);
    }

    function updateBonusRate(uint256 _rate) external onlyOwner {
        require(_rate <= 10000, "Invalid rate");
        bonusRate = _rate;
        emit SetBonusRate(_rate);
    }

    receive() external payable {}
}