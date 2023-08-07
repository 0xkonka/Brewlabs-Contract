// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniPair} from "./libs/IUniPair.sol";
import {IUniRouter02} from "./libs/IUniRouter02.sol";

interface IUniV2Pair is IUniPair {
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

contract BrewlabsTeamLocker is Ownable {
    using SafeERC20 for IERC20;

    address[] public members;
    mapping(address => uint256) public rates;
    uint256 public rateDenominator;
    address public swapRouter;

    event SetMember(address member, uint256 rate);
    event RemoveMember(address member);
    event Distributed(address member, address token, uint256 amount);
    event TokenRecovered(address token, uint256 amount);
    event SetSwapRouter(address router);

    constructor() {}

    function addMember(address member, uint256 rate) external onlyOwner {
        require(member != address(0x0), "Invalid address");
        require(rates[member] == 0, "already set");

        members.push(member);
        rates[member] = rate;
        rateDenominator += rate;

        emit SetMember(member, rate);
    }

    function removeMember(address member) external onlyOwner {
        require(rates[member] > 0, "Not found");

        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == member) {
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }

        rateDenominator -= rates[member];
        rates[member] = 0;

        emit RemoveMember(member);
    }

    function updateMember(address member, uint256 rate) external onlyOwner {
        require(rates[member] > 0, "Not found");

        rateDenominator = rateDenominator - rates[member] + rate;
        rates[member] = rate;

        emit SetMember(member, rate);
    }

    function numMembers() external view returns (uint256) {
        return members.length;
    }

    function rateOfMember(address member) external view returns (uint256 numerator, uint256 denominator) {
        return (rates[member], rateDenominator);
    }

    function distribute(address[] memory tokens) external onlyOwner {
        require(tokens.length > 0, "wrong config");
        for (uint256 i = 0; i < tokens.length; i++) {
            _distributeTokens(tokens[i]);
        }
    }

    function _distributeTokens(address token) internal {
        uint256 balance;
        if (token == address(0x0)) {
            balance = address(this).balance;
        } else {
            balance = IERC20(token).balanceOf(address(this));
        }

        for (uint256 i = 0; i < members.length; i++) {
            address user = members[i];
            uint256 _amount = balance * rates[user] / rateDenominator;
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

    function removeLiquidity(address[] memory pairs, uint256 deadline) external onlyOwner {
        require(deadline >= block.timestamp, "EXPIRED");

        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            require(pair != address(0x0), "Invalid pair");

            uint256 amount = IERC20(pair).balanceOf(address(this));
            IERC20(pair).safeTransfer(pair, amount);
            (uint256 amount0, uint256 amount1) = IUniV2Pair(pair).burn(address(this));
            require(amount0 > 0 && amount1 > 0, "removing liquidity failed");
        }
    }

    function setSwapRouter(address router) external onlyOwner {
        require(router != address(0x0), "Invalid router");
        swapRouter = router;
        emit SetSwapRouter(router);
    }

    /**
     * @notice It allows the owner to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @param _amount: withdrawal amount; if _amount is zero, withdrawal amount is equal to token balance
     * @dev This function is only callable by owner.
     */
    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        uint256 balance;
        if (_token == address(0x0)) {
            balance = address(this).balance;
        } else {
            balance = IERC20(_token).balanceOf(address(this));
        }
        if (_amount == 0) _amount = balance;

        require(balance >= _amount, "Insufficient balance");

        _transferToken(_token, msg.sender, _amount);
        emit TokenRecovered(_token, _amount);
    }

    receive() external payable {}
}
