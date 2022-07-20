// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/proxy/Clones.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import './libs/IBrewlabsPairLocker.sol';
import './libs/IUniFactory.sol';
import './libs/IUniPair.sol';

contract BrewlabsPairFreezer is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct FeeStruct {
        uint256 mintFee;
        uint256 editFee;
        uint256 defrostFee;
    }
    FeeStruct public gFees;

    address public implementation;
    mapping (address => address) public liquidityLockers;

    address public treasury = 0x408c4aDa67aE1244dfeC7D609dea3c232843189A;
    address private devAddr;
    uint256 private devRate = 0;

    event LiquidityLockerCreated(address locker, address factory, address token);
    event FeeUpdated(uint256 mintFee, uint256 editFee, uint256 defrostFee);
    event UpdateImplementation(address impl);

    constructor (address _implementation) {
        implementation = _implementation;

        devAddr = msg.sender;

        gFees.mintFee = 0.5 ether;
        gFees.editFee = 0.3 ether;
        gFees.defrostFee = 5 ether;
    }

    function createLiquidityLocker(address _op, address _uniFactory, address _pair, uint256 _amount, uint256 _unlockTime) external payable returns (address locker) {
        require(msg.value >= gFees.mintFee, "not enough fee");
        
        _checkPair(_uniFactory, _pair);
        _transferFee(gFees.mintFee);

        uint256 beforeAmt = IERC20(_pair).balanceOf(address(this));
        IERC20(_pair).transferFrom(msg.sender, address(this), _amount);
        uint256 afterAmt = IERC20(_pair).balanceOf(address(this));

        uint256 amountIn = afterAmt.sub(beforeAmt);

        locker = liquidityLockers[_pair];
        if(locker == address(0x0)) {
            bytes32 salt = keccak256(abi.encodePacked(_op, _pair, amountIn, _unlockTime, block.timestamp));
            locker = Clones.cloneDeterministic(implementation, salt);
            IBrewlabsPairLocker(locker).initialize(_pair, treasury, gFees.editFee, gFees.defrostFee, devAddr, devRate, address(this));

            liquidityLockers[_pair] = locker;
            emit LiquidityLockerCreated(locker, _uniFactory, _pair);
        }

        IERC20(_pair).approve(locker, amountIn);
        IBrewlabsPairLocker(locker).newLock(_op, amountIn, _unlockTime);
    }

    function setImplementation(address _implementation) external onlyOwner {
        require(_implementation != address(0x0), "invalid address");

        implementation = _implementation;
        emit UpdateImplementation(_implementation);
    }

    function forceUnlockLP(address _locker, uint256 _lockID) external onlyOwner {
        IBrewlabsPairLocker(_locker).defrost(_lockID);
    }

    function updateTreasuryOfLocker(address _locker, address _treasury) external onlyOwner {
        require(_locker != address(0x0), "invalid locker");
        IBrewlabsPairLocker(_locker).setTreasury(_treasury);
    }

    function transferOwnershipOfLocker( address payable _locker, address _newOwner) external onlyOwner {
        IBrewlabsPairLocker(_locker).transferOwnership(_newOwner);
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

    function setDevAddress(address _devAddr) external {
        require(msg.sender == devAddr, "not dev");
        devAddr = _devAddr;
    }

    function _checkPair(address _uniFactory, address _lpToken) internal view {
        // ensure this pair is a univ2 pair by querying the factory
        IUniPair lpair = IUniPair(_lpToken);
        address factoryPairAddress = IUniV2Factory(_uniFactory).getPair(lpair.token0(), lpair.token1());
        require(factoryPairAddress == _lpToken, 'invalid pair');
    }

    function _transferFee(uint256 _fee) internal {
        if(msg.value > _fee) {
            payable(msg.sender).transfer(msg.value.sub(_fee));
        }

        uint256 _devFee = _fee.mul(devRate).div(10000);
        if(_devFee > 0) {
            payable(devAddr).transfer(_devFee);
        }

        payable(treasury).transfer(_fee.sub(_devFee));
    }

    receive() external payable {}
}