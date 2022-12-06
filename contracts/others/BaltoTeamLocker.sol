// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract BaltoTeamLocker is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public isActive = false;
    bool private initialized = false;

    IERC20 public token;
    address public reflectionToken;

    uint256 public dividendPercent = 9800;
    uint256 private PRECISION_FACTOR = 1 ether;

    mapping(address => bool) isUsed;
    mapping(address => bool) public isDistributor;
    address[] public distributors;
    uint256 public totalDistributors;

    event AddDistribution(address distributor);
    event RemoveDistribution(address distributor);
    event UpdateDividendPercent(uint256 percent);

    event Harvested(uint256 amount);
    event EmergencyWithdrawn();
    event EmergencyDividendWithdrawn();

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

    function addDistribution(address distributor) external onlyOwner {
        require(isDistributor[distributor] == false, "already set");

        isDistributor[distributor] = true;
        if (!isUsed[distributor]) {
            distributors.push(distributor);
            isUsed[distributor] = true;
        }
        totalDistributors = totalDistributors.add(1);

        emit AddDistribution(distributor);
    }

    function removeDistribution(address distributor) external onlyOwner {
        require(isDistributor[distributor] == true, "Not found");

        isDistributor[distributor] = false;
        totalDistributors = totalDistributors.sub(1);

        emit RemoveDistribution(distributor);
    }

    function harvest() public onlyActive {
        require(isDistributor[msg.sender] == true || msg.sender == owner(), "only distributor");

        uint256 reflectionTokens = 0;
        if (reflectionToken == address(0x0)) {
            reflectionTokens = address(this).balance;
        } else {
            reflectionTokens = IERC20(reflectionToken).balanceOf(address(this));
        }

        uint256 dAmt = reflectionTokens.mul(dividendPercent).div(10000).div(totalDistributors);
        if (dAmt == 0) return;

        for (uint256 i = 0; i < distributors.length; i++) {
            address distributor = distributors[i];
            if (!isDistributor[distributor]) continue;

            if (reflectionToken == address(0x0)) {
                payable(distributor).transfer(dAmt);
            } else {
                IERC20(reflectionToken).safeTransfer(distributor, dAmt);
            }
        }

        emit Harvested(dAmt);
    }

    function pendingReflection(address _user) external view returns (uint256) {
        if (isDistributor[_user] == false) return 0;

        uint256 reflectionTokens = 0;
        if (reflectionToken == address(0x0)) {
            reflectionTokens = address(this).balance;
        } else {
            reflectionTokens = IERC20(reflectionToken).balanceOf(address(this));
        }

        return reflectionTokens.mul(dividendPercent).div(10000).div(totalDistributors);
    }

    function setStatus(bool _isActive) external onlyOwner {
        isActive = _isActive;
    }

    function setDividendPercent(uint256 _percent) external onlyOwner {
        require(_percent <= 10000, "Invalid percentage");
        dividendPercent = _percent;
        emit UpdateDividendPercent(_percent);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 tokenAmt = token.balanceOf(address(this));
        if (tokenAmt > 0) {
            token.transfer(msg.sender, tokenAmt);
        }
        emit EmergencyWithdrawn();
    }

    function emergencyDividendWithdraw() external onlyOwner {
        if (reflectionToken == address(0x0)) {
            uint256 reflectionTokens = address(this).balance;
            payable(msg.sender).transfer(reflectionTokens);
        } else {
            uint256 reflectionTokens = IERC20(reflectionToken).balanceOf(address(this));
            IERC20(reflectionToken).transfer(msg.sender, reflectionTokens);
        }

        emit EmergencyDividendWithdrawn();
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueToken(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            uint256 _tokenAmount = address(this).balance;
            payable(msg.sender).transfer(_tokenAmount);
        } else {
            uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
        }
    }

    receive() external payable {}
}
