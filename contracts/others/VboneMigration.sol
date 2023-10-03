// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract VboneMigration is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MIGRATION_PRECISION = 10000;

    bool public enabled = false;

    IERC20 public vbone;
    IERC20 public vboneWormhole;
    uint8 public vboneDecimals;
    uint8 public vboneWormholeDecimals;
    uint256 public migrationRate = 10000;

    event Enabled();
    event Disabled();
    event Migrated(address indexed user, uint256 amountA, uint256 amountB);
    event MigratedToVbone(address indexed user, uint256 amountA, uint256 amountB);
    event MigrationRateChanged(uint256 rate);

    modifier onlyActive() {
        require(enabled, "cannot migrate");
        _;
    }

    /**
     * @notice constructor
     * @param _vbone: token address
     * @param _vboneWormhole: reflection token address
     */
    constructor(IERC20 _vbone, IERC20 _vboneWormhole) {
        vbone = _vbone;
        vboneWormhole = _vboneWormhole;
        vboneDecimals = IERC20Metadata(address(vbone)).decimals();
        vboneWormholeDecimals = IERC20Metadata(address(vboneWormhole)).decimals();
    }

    function migrate(uint256 _amount) external onlyActive nonReentrant {
        require(_amount > 0, "Invalid amount");
        uint256 beforeBalance = vbone.balanceOf(address(this));
        vbone.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterBalance = vbone.balanceOf(address(this));

        uint256 amount = afterBalance - beforeBalance;

        uint256 mAmount =
            (amount * 10 ** vboneWormholeDecimals * migrationRate) / 10 ** vboneDecimals / MIGRATION_PRECISION;
        vboneWormhole.safeTransfer(msg.sender, mAmount);

        emit Migrated(msg.sender, amount, mAmount);
    }

    function migrateToVBone(uint256 _amount) external onlyActive nonReentrant {
        require(_amount > 0, "Invalid amount");
        uint256 beforeBalance = vboneWormhole.balanceOf(address(this));
        vboneWormhole.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterBalance = vboneWormhole.balanceOf(address(this));

        uint256 amount = afterBalance - beforeBalance;

        uint256 mAmount =
            (amount * 10 ** vboneDecimals * MIGRATION_PRECISION) / 10 ** vboneWormholeDecimals / migrationRate;
        vboneWormhole.safeTransfer(msg.sender, mAmount);

        emit MigratedToVbone(msg.sender, amount, mAmount);
    }

    function enableMigration() external onlyOwner {
        require(!enabled, "already enabled");
        enabled = true;
        emit Enabled();
    }

    function disableMigration() external onlyOwner {
        require(enabled, "not enabled");
        enabled = false;
        emit Disabled();
    }

    function setMigrationRate(uint256 _rate) external onlyOwner {
        require(_rate > 0, "Invalid rate");
        migrationRate = _rate;
        emit MigrationRateChanged(_rate);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @param _amount: the amount to withdraw, if amount is zero, all tokens will be withdrawn
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0x0)) {
            if (_amount > 0) {
                payable(msg.sender).transfer(_amount);
            } else {
                uint256 _tokenAmount = address(this).balance;
                payable(msg.sender).transfer(_tokenAmount);
            }
        } else {
            if (_amount > 0) {
                IERC20(_token).safeTransfer(msg.sender, _amount);
            } else {
                uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
                IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
            }
        }
    }

    receive() external payable {}
}
