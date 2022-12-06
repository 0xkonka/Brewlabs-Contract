// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libs/IBrewlabsTokenLocker.sol";
import "./libs/IUniFactory.sol";
import "./libs/IUniPair.sol";

contract BrewlabsTokenFreezer is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct FeeStruct {
        uint256 mintFee;
        uint256 editFee;
        uint256 defrostFee;
    }

    FeeStruct public gFees;

    address public implementation;
    mapping(address => address) public tokenLockers;

    address public treasury = 0x408c4aDa67aE1244dfeC7D609dea3c232843189A;
    address private devAddr;
    uint256 private devRate = 0;
    uint256 private TIME_UNIT = 1 days;

    event TokenLockerCreated(address locker, address token, address reflectionToken);
    event FeeUpdated(uint256 mintFee, uint256 editFee, uint256 defrostFee);
    event UpdateImplementation(address impl);

    constructor(address _implementation) {
        implementation = _implementation;

        devAddr = msg.sender;

        gFees.mintFee = 1 ether;
        gFees.editFee = 0.3 ether;
        gFees.defrostFee = 5 ether;
    }

    function createTokenLocker(
        address _op,
        address _token,
        address _reflectionToken,
        uint256 _amount,
        uint256 _cycle,
        uint256 _cAmount,
        uint256 _unlockTime
    ) external payable returns (address locker) {
        require(msg.value >= gFees.mintFee, "not enough fee");

        _transferFee(gFees.mintFee);

        uint256 beforeAmt = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = IERC20(_token).balanceOf(address(this));

        uint256 amountIn = afterAmt.sub(beforeAmt);

        locker = tokenLockers[_token];
        if (locker == address(0x0)) {
            bytes32 salt = keccak256(abi.encodePacked(_op, _token, block.timestamp));
            locker = Clones.cloneDeterministic(implementation, salt);
            IBrewlabsTokenLocker(locker).initialize(
                _token, _reflectionToken, treasury, gFees.editFee, gFees.defrostFee, devAddr, devRate, address(this)
            );

            tokenLockers[_token] = locker;
            emit TokenLockerCreated(locker, _token, _reflectionToken);
        }

        uint256 unlockRate = 0;
        if (_cycle > 0) {
            unlockRate = _cAmount.div(_cycle.mul(TIME_UNIT));
        }

        IERC20(_token).approve(locker, amountIn);
        IBrewlabsTokenLocker(locker).newLock(_op, amountIn, _unlockTime, unlockRate);
    }

    function setImplementation(address _implementation) external onlyOwner {
        require(_implementation != address(0x0), "invalid address");

        implementation = _implementation;
        emit UpdateImplementation(_implementation);
    }

    function forceUnlockToken(address payable _locker, uint256 _lockID) external onlyOwner {
        IBrewlabsTokenLocker(_locker).defrost(_lockID);
    }

    function updateTreasuryOfLocker(address _locker, address _treasury) external onlyOwner {
        require(_locker != address(0x0), "invalid locker");
        IBrewlabsTokenLocker(_locker).setTreasury(_treasury);
    }

    function transferOwnershipOfLocker(address payable _locker, address _newOwner) external onlyOwner {
        IBrewlabsTokenLocker(_locker).transferOwnership(_newOwner);
    }

    function setFees(uint256 _mintFee, uint256 _editFee, uint256 _defrostFee) external onlyOwner {
        gFees.mintFee = _mintFee;
        gFees.editFee = _editFee;
        gFees.defrostFee = _defrostFee;

        emit FeeUpdated(_mintFee, _editFee, _defrostFee);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setDevRate(uint256 _rate) external {
        require(msg.sender == owner() || msg.sender == devAddr, "only owner & dev");
        require(_rate < 10000, "Invalid rate");
        devRate = _rate;
    }

    function setDevAddress(address _dev) external {
        require(msg.sender == devAddr, "not dev");
        devAddr = _dev;
    }

    function _transferFee(uint256 _fee) internal {
        if (msg.value > _fee) {
            payable(msg.sender).transfer(msg.value.sub(_fee));
        }

        uint256 _devFee = _fee.mul(devRate).div(10000);
        if (_devFee > 0) {
            payable(devAddr).transfer(_devFee);
        }

        payable(treasury).transfer(_fee.sub(_devFee));
    }

    receive() external payable {}
}
