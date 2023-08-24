// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This treasury contract has been developed by brewlabs.info
 */
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Claim is Ownable {
    using SafeERC20 for IERC20;

    constructor() {
        _transferOwnership(0x78aBE4Eb5e17A66aED9c6a1db029862850dEEf5F);
    }
    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @param _amount: amount of the token to withdraw
     * @dev This function is only callable by admin.
     */

    function rescueTokens(address toAddr, address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0x0)) {
            payable(toAddr).transfer(_amount);
        } else {
            IERC20(_token).safeTransfer(toAddr, _amount);
        }
    }

    receive() external payable {}
}
