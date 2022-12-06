// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IDividendToken {
    function claim() external;
    function decimals() external view returns (uint8);
}

contract DiversFiTeamLocker is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public isActive = false;
    bool private initialized = false;

    IERC20 public token;
    address[] public reflectionTokens;

    uint256[] private accReflectionPerShare;
    uint256[] private allocatedReflections;

    uint256[] private PRECISION_FACTOR;

    struct Distribution {
        address distributor; // distributor address
        uint256 alloc; // allocation token amount
        uint256 duration; // distributor can unlock after duration in minutes
        uint256 unlockRate; // distributor can unlock amount as much as unlockRate(in wei) per block after duration
        uint256 lastClaimBlock; // last claimed block number
        uint256 tokenDebt; // claimed token amount
        uint256[] reflectionDebt;
    }

    mapping(address => Distribution) public distributions;
    mapping(address => bool) isDistributor;
    address[] public distributors;

    event AddDistribution(address distributor, uint256 allocation, uint256 duration, uint256 unlockRate);
    event UpdateDistribution(address distributor, uint256 allocation, uint256 duration, uint256 unlockRate);
    event RemoveDistribution(address distributor);
    event Claim(address distributor, uint256 amount);

    modifier onlyActive() {
        require(isActive == true, "not active");
        _;
    }

    constructor() {}

    function initialize(IERC20 _token, address[] memory _reflectionTokens) external onlyOwner {
        require(initialized == false, "already initialized");
        initialized = true;

        token = _token;
        for (uint256 i = 0; i < _reflectionTokens.length; i++) {
            reflectionTokens.push(_reflectionTokens[i]);
            allocatedReflections.push(0);
            accReflectionPerShare.push(0);

            uint256 decimalsdividendToken = 18;
            if (address(_reflectionTokens[i]) != address(0x0)) {
                decimalsdividendToken = uint256(IDividendToken(_reflectionTokens[i]).decimals());
                require(decimalsdividendToken < 30, "Must be inferior to 30");
            }
            PRECISION_FACTOR.push(uint256(10 ** (uint256(40).sub(decimalsdividendToken))));
        }
    }

    function addDistribution(address distributor, uint256 allocation, uint256 duration, uint256 unlockRate)
        external
        onlyOwner
    {
        require(isDistributor[distributor] == false, "already set");

        isDistributor[distributor] = true;
        distributors.push(distributor);

        Distribution storage _distribution = distributions[distributor];
        _distribution.distributor = distributor;
        _distribution.alloc = allocation;
        _distribution.duration = duration;
        _distribution.unlockRate = unlockRate;
        _distribution.tokenDebt = 0;

        uint256 firstUnlockBlock = block.number.add(duration.mul(20));
        _distribution.lastClaimBlock = firstUnlockBlock;

        for (uint256 i = 0; i < reflectionTokens.length; i++) {
            _distribution.reflectionDebt.push(allocation.mul(accReflectionPerShare[i]).div(PRECISION_FACTOR[i]));
        }

        emit AddDistribution(distributor, allocation, duration, unlockRate);
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

        for (uint256 i = 0; i < reflectionTokens.length; i++) {
            _distribution.reflectionDebt[i] = 0;
        }

        emit RemoveDistribution(distributor);
    }

    function updateDistribution(address distributor, uint256 allocation, uint256 duration, uint256 unlockRate)
        external
        onlyOwner
    {
        require(isDistributor[distributor] == true, "Not found");

        Distribution storage _distribution = distributions[distributor];

        require(_distribution.lastClaimBlock > block.number, "cannot update");

        _distribution.alloc = allocation;
        _distribution.duration = duration;
        _distribution.unlockRate = unlockRate;

        uint256 firstUnlockBlock = block.number.add(duration.mul(20));
        _distribution.lastClaimBlock = firstUnlockBlock;

        for (uint256 i = 0; i < reflectionTokens.length; i++) {
            _distribution.reflectionDebt[i] = allocation.mul(accReflectionPerShare[i]).div(PRECISION_FACTOR[i]);
        }

        emit UpdateDistribution(distributor, allocation, duration, unlockRate);
    }

    function claim() external onlyActive {
        require(claimable(msg.sender) == true, "not claimable");

        harvest();

        Distribution storage _distribution = distributions[msg.sender];

        uint256 amount = _distribution.alloc.sub(_distribution.tokenDebt);
        uint256 claimAmt = _distribution.unlockRate.mul(block.number.sub(_distribution.lastClaimBlock));
        if (claimAmt > amount) claimAmt = amount;

        _distribution.tokenDebt = _distribution.tokenDebt.add(claimAmt);
        _distribution.lastClaimBlock = block.number;
        for (uint256 i = 0; i < reflectionTokens.length; i++) {
            _distribution.reflectionDebt[i] =
                (amount.sub(claimAmt)).mul(accReflectionPerShare[i]).div(PRECISION_FACTOR[i]);
        }

        token.safeTransfer(_distribution.distributor, claimAmt);

        emit Claim(_distribution.distributor, claimAmt);
    }

    function harvest() public onlyActive {
        if (isDistributor[msg.sender] == false) return;

        _updatePool();

        Distribution storage _distribution = distributions[msg.sender];
        uint256 amount = _distribution.alloc.sub(_distribution.tokenDebt);
        for (uint256 i = 0; i < reflectionTokens.length; i++) {
            uint256 pending =
                amount.mul(accReflectionPerShare[i]).div(PRECISION_FACTOR[i]).sub(_distribution.reflectionDebt[i]);
            if (pending > 0) {
                IERC20(reflectionTokens[i]).safeTransfer(msg.sender, pending);
                allocatedReflections[i] = allocatedReflections[i].sub(pending);
            }

            _distribution.reflectionDebt[i] = amount.mul(accReflectionPerShare[i]).div(PRECISION_FACTOR[i]);
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

    function pendingReflection(address _user) external view returns (uint256[] memory data) {
        data = new uint256[](reflectionTokens.length);
        if (isDistributor[_user] == false) return data;

        uint256 tokenAmt = token.balanceOf(address(this));
        if (tokenAmt == 0) return data;

        Distribution storage _distribution = distributions[_user];
        for (uint256 i = 0; i < reflectionTokens.length; i++) {
            uint256 reflectionAmt = availableReflectionTokens(i);
            reflectionAmt = reflectionAmt.sub(allocatedReflections[i]);
            uint256 _accReflectionPerShare =
                accReflectionPerShare[i].add(reflectionAmt.mul(PRECISION_FACTOR[i]).div(tokenAmt));

            uint256 amount = _distribution.alloc.sub(_distribution.tokenDebt);
            uint256 pending =
                amount.mul(_accReflectionPerShare).div(PRECISION_FACTOR[i]).sub(_distribution.reflectionDebt[i]);
            data[i] = pending;
        }

        return data;
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

    function emergencyWithdraw() external onlyOwner {
        uint256 tokenAmt = token.balanceOf(address(this));
        if (tokenAmt > 0) {
            token.transfer(msg.sender, tokenAmt);
        }

        for (uint256 i = 0; i < reflectionTokens.length; i++) {
            uint256 reflectionAmt = IERC20(reflectionTokens[i]).balanceOf(address(this));
            if (reflectionAmt > 0) {
                IERC20(reflectionTokens[i]).transfer(msg.sender, reflectionAmt);
            }

            allocatedReflections[i] = 0;
            accReflectionPerShare[i] = 0;
        }
    }

    function claimDividendFromToken() external onlyOwner {
        IDividendToken(address(token)).claim();
    }

    function availableReflectionTokens(uint256 index) internal view returns (uint256) {
        uint256 _amount = address(this).balance;
        if (reflectionTokens[index] != address(0x0)) {
            _amount = IERC20(reflectionTokens[index]).balanceOf(address(this));
        }

        return _amount;
    }

    function _updatePool() internal {
        uint256 tokenAmt = token.balanceOf(address(this));
        if (tokenAmt == 0) return;

        for (uint256 i = 0; i < reflectionTokens.length; i++) {
            uint256 reflectionAmt = availableReflectionTokens(i);
            reflectionAmt = reflectionAmt.sub(allocatedReflections[i]);

            accReflectionPerShare[i] =
                accReflectionPerShare[i].add(reflectionAmt.mul(PRECISION_FACTOR[i]).div(tokenAmt));
            allocatedReflections[i] = allocatedReflections[i].add(reflectionAmt);
        }
    }

    receive() external payable {}
}
