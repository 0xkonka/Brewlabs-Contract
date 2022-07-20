 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenVesting is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool public isInitialized;
    uint256 public duration = 99 * 365; // 99 years

    // The block number when claim starts.
    uint256 public startBlock;
    // The block number when claim ends.
    uint256 public claimEndBlock;
    // tokens created per block.
    uint256 public claimPerBlock;
    // The block number of the last update
    uint256 public lastClaimBlock;

    // The vested token
    IERC20 public vestedToken;
    // The dividend token of vested token
    address public dividendToken;


    event Claimed(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);

    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event ClaimEndBlockUpdated(uint256 endBlock);
    event NewclaimPerBlock(uint256 claimPerBlock);
    event DurationUpdated(uint256 _duration);

    constructor() {}

    /*
     * @notice Initialize the contract
     * @param _vestedToken: vested token address
     * @param _dividendToken: reflection token address
     * @param _claimPerBlock: claim amount per block (in vestedToken)
     */
    function initialize(
        IERC20 _vestedToken,
        address _dividendToken,
        uint256 _claimPerBlock
    ) external onlyOwner {
        require(!isInitialized, "Already initialized");

        // Make this contract initialized
        isInitialized = true;

        vestedToken = _vestedToken;
        dividendToken = _dividendToken;

        claimPerBlock = _claimPerBlock;
    }

    function claim() external nonReentrant onlyOwner {
        if(startBlock == 0) return;

        uint256 multiplier = _getMultiplier(lastClaimBlock, block.number);
        uint256 amount = multiplier.mul(claimPerBlock);
        if(amount > 0) {
            vestedToken.safeTransfer(msg.sender, amount);
            emit Claimed(msg.sender, amount);
        }

        lastClaimBlock = block.number;
    }

    function harvest() external onlyOwner {      
        uint256 amount = 0;
        if(address(dividendToken) == address(0x0)) {
            amount = address(this).balance;
            if(amount > 0) {
                payable(msg.sender).transfer(amount);
            }
        } else {
            amount = IERC20(dividendToken).balanceOf(address(this));
            if(amount > 0) {
                IERC20(dividendToken).safeTransfer(msg.sender, amount);
            }
        }
    }

    function emergencyWithdraw() external nonReentrant onlyOwner{
        uint256 amount = vestedToken.balanceOf(address(this));
        if(amount > 0) {
            vestedToken.safeTransfer(msg.sender, amount);
        }

        emit EmergencyWithdraw(msg.sender, amount);
    }

    function pendingClaim() external view returns (uint256) {
        if(startBlock == 0) return 0;
        uint256 multiplier = _getMultiplier(lastClaimBlock, block.number);
        uint256 amount = multiplier.mul(claimPerBlock);
        
        return amount;
    }

    function pendingDividends() external view returns (uint256) {
        uint256 amount = 0;
        if(address(dividendToken) == address(0x0)) {
            amount = address(this).balance;
        } else {
            amount = IERC20(dividendToken).balanceOf(address(this));
        }
        
        return amount;
    }


    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(
            _tokenAddress != address(vestedToken) && _tokenAddress != address(dividendToken),
            "Cannot be vested or dividend token address"
        );

        if(_tokenAddress == address(0x0)) {
            payable(msg.sender).transfer(_tokenAmount);
        } else {
            IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
        }

        emit AdminTokenRecovered(_tokenAddress, _tokenAmount);
    }

    function startClaim() external onlyOwner {
        require(startBlock == 0, "Pool was already started");

        startBlock = block.number.add(100);
        claimEndBlock = startBlock.add(duration * 28800);
        lastClaimBlock = startBlock;
        
        emit NewStartAndEndBlocks(startBlock, claimEndBlock);
    }

    function stopClaim() external onlyOwner {
        claimEndBlock = block.number;
    }

    function updateEndBlock(uint256 _endBlock) external onlyOwner {
        require(startBlock > 0, "startBlock is not set");
        require(_endBlock > block.number && _endBlock > startBlock, "Invalid end block");

        claimEndBlock = _endBlock;
        emit ClaimEndBlockUpdated(_endBlock);
    }

    function updateClaimPerBlock(uint256 _claimPerBlock) external onlyOwner {
        // require(block.number < startBlock, "Claim was already started");

        if(startBlock > 0) {
            uint256 multiplier = _getMultiplier(lastClaimBlock, block.number);
            uint256 amount = multiplier.mul(claimPerBlock);
            if(amount > 0) {
                vestedToken.safeTransfer(msg.sender, amount);
                emit Claimed(msg.sender, amount);
            }

            lastClaimBlock = block.number;
        }

        claimPerBlock = _claimPerBlock;
        emit NewclaimPerBlock(_claimPerBlock);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(startBlock == 0, "Pool was already started");
        require(_duration >= 30, "lower limit reached");

        duration = _duration;
        emit DurationUpdated(_duration);
    }

    /*
     * @notice Return multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= claimEndBlock) {
            return _to.sub(_from);
        } else if (_from >= claimEndBlock) {
            return 0;
        } else {
            return claimEndBlock.sub(_from);
        }
    }

    receive() external payable {}
}