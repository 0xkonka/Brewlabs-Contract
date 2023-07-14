// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BrewlabsTeamLocker is Ownable {
    using SafeERC20 for IERC20;

    address[] public distributors;
    mapping(address => uint256) public rates;
    uint256 public rateDenominator;

    event SetDistributor(address distributor, uint256 position);
    event RemoveDistribution(address distributor);
    event Distributed(address distributor, address token, uint256 amount);

    constructor() {}

    function addDistribution(address distributor, uint256 rate) external onlyOwner {
        require(rates[distributor] == 0, "already set");

        distributors.push(distributor);
        rates[distributor] = rate;
        rateDenominator += rate;

        emit SetDistributor(distributor, rate);
    }

    function removeDistribution(address distributor) external onlyOwner {
        require(rates[distributor] > 0, "Not found");

        for (uint256 i = 0; i < distributors.length; i++) {
            if (distributors[i] == distributor) {
                distributors[i] = distributors[distributors.length - 1];
                distributors.pop();
                break;
            }
        }

        rateDenominator -= rates[distributor];
        rates[distributor] = 0;

        emit RemoveDistribution(distributor);
    }

    function updateDistribution(address distributor, uint256 rate) external onlyOwner {
        require(rates[distributor] > 0, "Not found");

        rateDenominator = rateDenominator - rates[distributor] + rate;
        rates[distributor] = rate;

        emit SetDistributor(distributor, rate);
    }

    function numDistributors() external view returns (uint256) {
        return distributors.length;
    }

    function rateOfDistributor(address distributor) external view returns (uint256 numerator, uint256 denominator) {
        return (rates[distributor], rateDenominator);
    }

    function distribute(address[] memory tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            _distributeTokens(tokens[i]);
        }
    }

    function _distributeTokens(address token) internal {
        uint256 amount;
        if (token == address(0x0)) {
            amount = address(this).balance;
        } else {
            amount = IERC20(token).balanceOf(address(this));
        }

        for (uint256 i = 0; i < distributors.length; i++) {
            address user = distributors[i];
            uint256 _amount = amount * rates[user] / rateDenominator;
            _transferToken(token, user, _amount);

            emit Distributed(user, token, _amount);
        }
    }

    function _transferToken(address token, address to, uint256 amount) internal {
        if (token == address(0x0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    receive() external payable {}
}
