// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IToken {
    function claim() external;
    function decimals() external view returns (uint256);
}

contract TeamLocker is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public isActive = false;
    bool private initialized = false;

    IERC20 public token;

    address public reflectionToken;
    uint256 private accReflectionPerShare;
    uint256 private allocatedReflections;

    uint256 public vestingDuration = 365;

    uint256 private PRECISION_FACTOR = 1 ether;

    struct Distribution {
        address distributor; // distributor address
        uint256 alloc; // allocation token amount
        uint256 duration; // distributor can unlock after duration in day
        uint256 unlockRate; // distributor can unlock amount as much as unlockRate(in wei) per block after duration
        uint256 lastClaimBlock; // last claimed block number
        uint256 tokenDebt; // claimed token amount
        uint256 reflectionDebt;
    }

    mapping(address => Distribution) public distributions;
    mapping(address => bool) isDistributor;
    address[] public distributors;

    event AddDistribution(address distributor, uint256 allocation, uint256 duration, uint256 unlockRate);
    event UpdateDistribution(address distributor, uint256 allocation, uint256 duration, uint256 unlockRate);
    event RemoveDistribution(address distributor);
    event UpdateVestingDuration(uint256 Days);
    event Claim(address distributor, uint256 amount);

    modifier onlyActive() {
        require(isActive == true, "not active");
        _;
    }

    constructor() {}

    function initialize(IERC20 _token, address _reflectionToken) external onlyOwner {
        require(initialized == false, "already initialized");
        initialized = true;

        token = _token;
        reflectionToken = _reflectionToken;
    }

    function addDistribution(address distributor, uint256 allocation, uint256 duration) external onlyOwner {
        require(isDistributor[distributor] == false, "already set");

        isDistributor[distributor] = true;
        distributors.push(distributor);

        uint256 allocationAmt = allocation.mul(10 ** IToken(address(token)).decimals());

        Distribution storage _distribution = distributions[distributor];
        _distribution.distributor = distributor;
        _distribution.alloc = allocationAmt;
        _distribution.duration = duration;
        _distribution.unlockRate = allocationAmt.div(vestingDuration).div(28800);
        _distribution.tokenDebt = 0;

        uint256 firstUnlockBlock = block.number.add(duration.mul(28800));
        _distribution.lastClaimBlock = firstUnlockBlock;

        _distribution.reflectionDebt = allocationAmt.mul(accReflectionPerShare).div(PRECISION_FACTOR);

        emit AddDistribution(distributor, allocationAmt, duration, _distribution.unlockRate);
    }

    function removeDistribution(address distributor) external onlyOwner {
        require(isDistributor[distributor] == true, "Not found");

        isDistributor[distributor] = false;

        Distribution storage _distribution = distributions[distributor];
        _distribution.distributor = address(0x0);
        _distribution.alloc = 0;
        _distribution.duration = 0;
        _distribution.unlockRate = 0;
        _distribution.lastClaimBlock = 0;
        _distribution.tokenDebt = 0;
        _distribution.reflectionDebt = 0;

        emit RemoveDistribution(distributor);
    }

    function updateDistribution(address distributor, uint256 allocation, uint256 duration) external onlyOwner {
        require(isDistributor[distributor] == true, "Not found");

        uint256 allocationAmt = allocation.mul(10 ** IToken(address(token)).decimals());
        Distribution storage _distribution = distributions[distributor];

        require(_distribution.lastClaimBlock > block.number, "cannot update");
        require(_distribution.tokenDebt < allocationAmt, "Allocation should be greater than claimed amount");

        _distribution.alloc = allocationAmt;
        _distribution.duration = duration;
        _distribution.unlockRate = allocationAmt.div(vestingDuration).div(28800);

        uint256 firstUnlockBlock = block.number.add(duration.mul(28800));
        _distribution.lastClaimBlock = firstUnlockBlock;

        _distribution.reflectionDebt = allocationAmt.mul(accReflectionPerShare).div(PRECISION_FACTOR);

        emit UpdateDistribution(distributor, allocationAmt, duration, _distribution.unlockRate);
    }

    function claim() external onlyActive {
        require(claimable(msg.sender) == true, "not claimable");

        harvest();

        Distribution storage _distribution = distributions[msg.sender];

        uint256 amount = _distribution.alloc.sub(_distribution.tokenDebt);
        uint256 claimAmt = _distribution.unlockRate.mul(block.number.sub(_distribution.lastClaimBlock));
        if (claimAmt > amount) claimAmt = amount;

        _distribution.tokenDebt = _distribution.tokenDebt.add(claimAmt);
        _distribution.reflectionDebt = (amount.sub(claimAmt)).mul(accReflectionPerShare).div(PRECISION_FACTOR);
        _distribution.lastClaimBlock = block.number;

        token.safeTransfer(_distribution.distributor, claimAmt);

        emit Claim(_distribution.distributor, claimAmt);
    }

    function harvest() public onlyActive {
        if (isDistributor[msg.sender] == false) return;

        _updatePool();

        Distribution storage _distribution = distributions[msg.sender];
        uint256 amount = _distribution.alloc.sub(_distribution.tokenDebt);
        uint256 pending = amount.mul(accReflectionPerShare).div(PRECISION_FACTOR).sub(_distribution.reflectionDebt);

        _distribution.reflectionDebt = amount.mul(accReflectionPerShare).div(PRECISION_FACTOR);

        if (pending > 0) {
            IERC20(reflectionToken).safeTransfer(msg.sender, pending);
            allocatedReflections = allocatedReflections.sub(pending);
        }
    }

    function pendingClaim(address _user) external view returns (uint256) {
        if (isDistributor[_user] == false) return 0;

        Distribution storage _distribution = distributions[_user];
        if (_distribution.lastClaimBlock >= block.number) return 0;

        uint256 amount = _distribution.alloc.sub(_distribution.tokenDebt);
        uint256 claimAmt = _distribution.unlockRate.mul(block.number.sub(_distribution.lastClaimBlock));
        if (claimAmt > amount) claimAmt = amount;

        return amount;
    }

    function pendingReflection(address _user) external view returns (uint256) {
        if (isDistributor[_user] == false) return 0;

        uint256 tokenAmt = token.balanceOf(address(this));
        if (tokenAmt == 0) return 0;

        Distribution storage _distribution = distributions[_user];

        uint256 reflectionAmt = IERC20(reflectionToken).balanceOf(address(this));
        reflectionAmt = reflectionAmt.sub(allocatedReflections);
        uint256 _accReflectionPerShare = accReflectionPerShare.add(reflectionAmt.mul(PRECISION_FACTOR).div(tokenAmt));

        uint256 amount = _distribution.alloc.sub(_distribution.tokenDebt);
        uint256 pending = amount.mul(_accReflectionPerShare).div(PRECISION_FACTOR).sub(_distribution.reflectionDebt);

        return pending;
    }

    function claimable(address _user) public view returns (bool) {
        if (isDistributor[_user] == false) return false;
        if (distributions[_user].lastClaimBlock >= block.number) return false;

        Distribution memory _distribution = distributions[_user];
        uint256 amount = _distribution.alloc.sub(_distribution.tokenDebt);
        if (amount > 0) return true;

        return false;
    }

    function setStatus(bool _isActive) external onlyOwner {
        isActive = _isActive;
    }

    function setVestingDuration(uint256 _days) external onlyOwner {
        require(_days > 0, "Invalid duration");

        vestingDuration = _days;
        emit UpdateVestingDuration(_days);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 tokenAmt = token.balanceOf(address(this));
        if (tokenAmt > 0) {
            token.transfer(msg.sender, tokenAmt);
        }

        uint256 reflectionAmt = IERC20(reflectionToken).balanceOf(address(this));
        if (reflectionAmt > 0) {
            IERC20(reflectionToken).transfer(msg.sender, reflectionAmt);
        }
    }

    function claimDividendFromToken() external {
        IToken(address(token)).claim();
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _token) external onlyOwner {
        require(_token != address(token) && _token != address(reflectionToken), "Cannot be token & dividend token");

        if (_token == address(0x0)) {
            uint256 _tokenAmount = address(this).balance;
            payable(msg.sender).transfer(_tokenAmount);
        } else {
            uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
        }
    }

    function _updatePool() internal {
        uint256 tokenAmt = token.balanceOf(address(this));
        if (tokenAmt == 0) return;

        uint256 reflectionAmt = 0;
        reflectionAmt = IERC20(reflectionToken).balanceOf(address(this));
        reflectionAmt = reflectionAmt.sub(allocatedReflections);

        accReflectionPerShare = accReflectionPerShare.add(reflectionAmt.mul(PRECISION_FACTOR).div(tokenAmt));
        allocatedReflections = allocatedReflections.add(reflectionAmt);
    }

    receive() external payable {}
}
