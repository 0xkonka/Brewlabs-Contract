// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

interface IPegSwap {
    function swap(uint256 amount, address source, address target) external;
    function getSwappableAmount(address source, address target) external view returns (uint256);
}

contract RandomSeedGenerator is VRFConsumerBaseV2, Ownable {
    using SafeERC20 for IERC20;

    VRFCoordinatorV2Interface COORDINATOR;
    LinkTokenInterface LINKTOKEN;
    uint64 public s_subscriptionId;

    // BSC Mainnet ERC20_LINK_ADDRESS
    address public constant ERC20_LINK_ADDRESS = 0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD;
    address public constant PEGSWAP_ADDRESS = 0x1FCc3B22955e76Ca48bF025f1A6993685975Bb9e;
    uint32 callbackGasLimit = 150000;
    uint16 requestConfirmations = 3;

    bytes32 internal keyHash;
    uint256 internal nonce;
    uint256 public randomSeed;

    mapping(address => bool) public admins;

    /**
     * @notice Constructor
     * @dev RandomNumberGenerator must be deployed prior to this contract
     */
    constructor(address _vrfCoordinator, address _link, bytes32 _keyHash) VRFConsumerBaseV2(_vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        s_subscriptionId = COORDINATOR.createSubscription();
        keyHash = _keyHash;

        COORDINATOR.addConsumer(s_subscriptionId, address(this));
        LINKTOKEN = LinkTokenInterface(_link);
        admins[msg.sender] = true;
    }

    function random() public returns (uint256) {
        require(randomSeed != 0, "Invalid seed");
        nonce++;
        return uint256(keccak256(abi.encode(randomSeed, block.timestamp, blockhash(block.number - 1), nonce)));
    }

    /**
     * Requests randomness
     */
    function genRandomNumber() public returns (uint256 requestId) {
        require(admins[msg.sender], "msg.sender isn't an admin");
        return COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, 1);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomWords(uint256, /* requestId */ uint256[] memory randomWords) internal override {
        randomSeed = randomWords[0];
    }

    /**
     * @notice fetch subscription information from the VRF coordinator
     */
    function getSubscriptionInfo()
        external
        view
        returns (uint96 balance, uint64 reqCount, address owner, address[] memory consumers)
    {
        return COORDINATOR.getSubscription(s_subscriptionId);
    }

    /**
     * @notice subscribe to the VRF coordinator
     * @dev This function must be called by the owner of the contract.
     */
    function startSubscription(address _vrfCoordinator) external onlyOwner {
        require(s_subscriptionId == 0, "Subscription already started");

        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        s_subscriptionId = COORDINATOR.createSubscription();
        COORDINATOR.addConsumer(s_subscriptionId, address(this));
    }

    /**
     * @notice cancle subscription from the VRF coordinator
     * @dev This function must be called by the owner of the contract.
     */
    function cancelSubscription() external onlyOwner {
        COORDINATOR.cancelSubscription(s_subscriptionId, msg.sender);
        s_subscriptionId = 0;
    }

    /**
     * @notice Fund link token from the VRF coordinator for subscription
     * @dev This function must be called by the owner of the contract.
     */
    function fundToCoordiator(uint96 _amount) external onlyOwner {
        LINKTOKEN.transferFrom(msg.sender, address(this), _amount);
        LINKTOKEN.transferAndCall(address(COORDINATOR), _amount, abi.encode(s_subscriptionId));
    }

    /**
     * @notice Fund link token from the VRF coordinator for subscription
     * @dev This function must be called by the owner of the contract.
     */
    function fundPeggedLinkToCoordiator(uint256 _amount) external onlyOwner {
        IERC20(ERC20_LINK_ADDRESS).transferFrom(msg.sender, address(this), _amount);
        IERC20(ERC20_LINK_ADDRESS).approve(PEGSWAP_ADDRESS, _amount);
        IPegSwap(PEGSWAP_ADDRESS).swap(_amount, ERC20_LINK_ADDRESS, address(LINKTOKEN));

        uint256 tokenBal = LINKTOKEN.balanceOf(address(this));
        LINKTOKEN.transferAndCall(address(COORDINATOR), tokenBal, abi.encode(s_subscriptionId));
    }

    function setAdmin(address _account, bool _isAdmin) external onlyOwner {
        admins[_account] = _isAdmin;
    }
}
