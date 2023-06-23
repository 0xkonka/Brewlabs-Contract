// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {ERC721, ERC721Enumerable, IERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DefaultOperatorFilterer} from "operator-filter-registry/src/DefaultOperatorFilterer.sol";

interface IBrewlabsMirrorNft is IERC721 {
    function mint(address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external;
    function setNftStakingContract(address staking) external;
}

interface IBrewlabsNftStaking {
    function forceUnstake(address from, uint256 tokenId) external;
}

contract BrewlabsFlaskNft is ERC721Enumerable, ERC721Holder, DefaultOperatorFilterer, Ownable {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using Strings for address;

    bool public mintAllowed;
    uint256 public maxSupply = 5000;

    IBrewlabsMirrorNft public mirrorNft;
    mapping(uint256 => bool) public locked;

    address public nftStaking;

    mapping(address => bool) public tokenAllowed;
    IERC20 public brews = IERC20(0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7);

    uint256 public mintFee = 100 ether;
    uint256 public brewsMintFee = 3500 * 10 ** 9;
    uint256 public upgradeFee = 25 ether;
    uint256 public brewsUpgradeFee = 1500 * 10 ** 9;
    uint256 public performanceFee = 0.01 ether;
    uint256 public oneTimeLimit = 30;

    address public stakingAddr = 0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F;
    address public brewsWallet = 0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F;
    address public treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;

    uint256 private tokenIndex;
    string private _tokenBaseURI = "";

    // generated by alias method algorithm
    uint256[] private probabilities = [100, 98, 50, 10, 1];
    uint256[] private aliases = [0, 0, 0, 1, 0];

    string[6] public rarityNames = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mod"];
    string[5] public featureAccesses = ["Basic", "Improved", "Brewer", "Premium", "Premium Brewer"];
    uint256[5] public feeReductions = [5, 10, 15, 20, 30];
    mapping(uint256 => uint256) private rarities;

    mapping(address => uint256) public whitelist;

    event BaseURIUpdated(string uri);
    event MintEnabled();

    event ItemUpgraded(uint256[3] tokenIds, uint256 newTokenId);
    event MirrorNftMinted(address user, uint256 tokenId);
    event MirrorNftBurned(address user, uint256 tokenId);

    event SetBrewlabsToken(address token);
    event SetFeeToken(address token, bool enabled);
    event SetMintPrice(uint256 tokenFee, uint256 brewsFee);
    event SetUpgradePrice(uint256 tokenFee, uint256 brewsFee);
    event SetMaxSupply(uint256 supply);
    event SetOneTimeLimit(uint256 limit);
    event SetMirrorNft(address nftAddr);
    event SetNftStakingContract(address staking);
    event SetBrewlabsWallet(address addr);
    event SetStakingAddress(address addr);
    event ServiceInfoChanged(address addr, uint256 fee);
    event Whitelisted(address indexed account, uint256 count);

    modifier onlyMintable() {
        require(mintAllowed, "Mint is disabled");
        _;
    }

    constructor() ERC721("Brewlabs Flask NFT", "BLF") {}

    function mint(uint256 numToMint, IERC20 payingToken) external onlyMintable {
        require(numToMint > 0, "Invalid amount");
        require(numToMint <= oneTimeLimit, "Cannot exceed one-time limit");
        require(totalSupply() + numToMint <= maxSupply, "Cannot exceed maxSupply");
        require(tokenAllowed[address(payingToken)], "Not allowed for mint");

        // process mint fee
        if (whitelist[msg.sender] < numToMint) {
            uint256 precision = 10 ** (18 - IERC20Metadata(address(payingToken)).decimals());
            uint256 feeAmount = (mintFee / precision) * (numToMint - whitelist[msg.sender]);
            require(payingToken.balanceOf(msg.sender) >= feeAmount, "Insufficient fee");

            brews.safeTransferFrom(msg.sender, treasury, brewsMintFee * (numToMint - whitelist[msg.sender]));
            payingToken.safeTransferFrom(msg.sender, address(this), feeAmount);

            payingToken.safeTransfer(brewsWallet, feeAmount / 4);
            payingToken.safeTransfer(treasury, feeAmount / 4);
            payingToken.safeTransfer(stakingAddr, feeAmount / 2);

            whitelist[msg.sender] = 0;
        } else {
            whitelist[msg.sender] = whitelist[msg.sender] - numToMint;
        }

        // mint NFT
        for (uint256 i = 0; i < numToMint; i++) {
            tokenIndex++;
            rarities[tokenIndex] = _getRarity(tokenIndex, numToMint);

            _safeMint(msg.sender, tokenIndex);
        }
    }

    function mintTo(address to, uint256 rarity, uint256 numToMint) external onlyOwner {
        require(numToMint > 0, "Invalid amount");
        require(numToMint <= oneTimeLimit, "Cannot exceed one-time limit");
        require(rarity > 0 && rarity <= rarityNames.length, "Invalid rarity");
        require(totalSupply() + numToMint <= maxSupply, "Cannot exceed maxSupply");

        for (uint256 i = 0; i < numToMint; i++) {
            tokenIndex++;
            rarities[tokenIndex] = rarity;

            _safeMint(to, tokenIndex);
        }
    }

    function upgradeNFT(uint256[3] memory tokenIds, IERC20 payingToken) external returns (uint256) {
        require(rarities[tokenIds[0]] < 3, "Only common or uncommon NFT can be upgraded");
        require(
            rarities[tokenIds[0]] == rarities[tokenIds[1]] && rarities[tokenIds[1]] == rarities[tokenIds[2]],
            "Rarities should be same"
        );
        require(tokenAllowed[address(payingToken)], "Not allowed for upgrade NFT");

        // process upgrade fee
        uint256 precision = 10 ** (18 - IERC20Metadata(address(payingToken)).decimals());
        uint256 feeAmount = upgradeFee / precision;
        require(payingToken.balanceOf(msg.sender) >= feeAmount, "Insufficient fee");

        brews.safeTransferFrom(msg.sender, brewsWallet, brewsUpgradeFee);
        payingToken.safeTransferFrom(msg.sender, stakingAddr, feeAmount);

        uint256 newRarity = rarities[tokenIds[0]] + 1;
        for (uint256 i = 0; i < 3; i++) {
            _safeTransfer(msg.sender, address(this), tokenIds[i], "");
            _burn(tokenIds[i]);
        }
        tokenIndex++;
        rarities[tokenIndex] = newRarity;

        _safeMint(msg.sender, tokenIndex);
        emit ItemUpgraded(tokenIds, tokenIndex);
        return tokenIndex;
    }

    function mintMirrorNft(uint256 tokenId) external payable {
        require(ownerOf(tokenId) == msg.sender, "Caller is not holder");
        require(locked[tokenId] == false, "Mirror token already mint");
        require(rarities[tokenId] > 2, "Cannot mint mirror token for uncommon and common");

        _transferPerformanceFee();

        locked[tokenId] = true;
        mirrorNft.mint(msg.sender, tokenId);
        emit MirrorNftMinted(msg.sender, tokenId);
    }

    function burnMirrorNft(uint256 tokenId) external payable {
        require(mirrorNft.ownerOf(tokenId) == msg.sender, "Caller is not holder");

        _transferPerformanceFee();
        mirrorNft.safeTransferFrom(msg.sender, address(this), tokenId);
        mirrorNft.burn(tokenId);

        locked[tokenId] = false;
        emit MirrorNftBurned(msg.sender, tokenId);
    }

    function removeModerator(uint256 tokenId) external onlyOwner {
        require(rarities[tokenId] == 6, "can remove only Mod token");

        if (locked[tokenId]) {
            address from = ownerOf(tokenId);
            IBrewlabsNftStaking(nftStaking).forceUnstake(from, tokenId);

            mirrorNft.burn(tokenId);
            locked[tokenId] = false;
        }

        _burn(tokenId);
        rarities[tokenId] = 0;
    }

    function _getRarity(uint256 tokenId, uint256 num) internal view returns (uint256) {
        uint256 randomNum = uint256(
            keccak256(
                abi.encode(
                    msg.sender,
                    tx.gasprice,
                    block.number,
                    block.timestamp,
                    blockhash(block.number - 1),
                    num,
                    num + tokenId
                )
            )
        );

        uint256 seed = randomNum % probabilities.length;

        uint256 index = seed % probabilities.length;
        uint256 rarity = seed * 100 / maxSupply;
        if (rarity < probabilities[index]) {
            rarity = index;
        } else {
            rarity = aliases[index];
        }

        return rarity + 1;
    }

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "Should pay small gas to call method");
        payable(treasury).transfer(performanceFee);
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override(ERC721, IERC721)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override
    {
        require(rarities[firstTokenId] < 6 || from == address(0x0) || to == address(0x0), "Cannot transfer Mod item");
        require(locked[firstTokenId] == false, "Locked due to mirror token");

        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function rarityOf(uint256 tokenId) external view returns (uint256) {
        return rarities[tokenId];
    }

    function baseURI() public view returns (string memory) {
        return _tokenBaseURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "BrewlabsFlaskNft: URI query for nonexistent token");

        string memory base = baseURI();
        string memory description = string(
            abi.encodePacked(
                '"description": "Brewlabs Flask NFT collection provides fee reductions and benefits across various Brewlabs products as well as access to exclusive NFT staking pools."'
            )
        );

        uint256 rarity = rarities[tokenId] - 1;
        string memory rarityName = rarityNames[rarity];
        if (rarity == 5) rarity = 4;

        string memory attributes = '"attributes":[';
        attributes = string(
            abi.encodePacked(
                attributes,
                '{"trait_type":"Network", "value":"BNB Chain"}, {"trait_type":"Rarity", "value":"',
                rarityName,
                '"}, {"trait_type":"Fee Reduction", "value":"',
                feeReductions[rarity].toString(),
                '"}, {"trait_type":"Feature Access", "value":"',
                featureAccesses[rarity],
                '"}]'
            )
        );

        // If both are set, concatenate the baseURI (via abi.encodePacked).
        string memory metadata = string(
            abi.encodePacked(
                '{"name": "',
                name(),
                " #",
                tokenId.toString(),
                '", ',
                description,
                ', "image": "',
                base,
                "/",
                rarityName,
                ".mp4",
                '", ',
                attributes,
                "}"
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", _base64(bytes(metadata))));
    }

    function addToWhitelist(address _addr, uint256 _count) external onlyOwner {
        whitelist[_addr] = _count;
        emit Whitelisted(_addr, _count);
    }

    function removeFromWhitelist(address _addr) external onlyOwner {
        whitelist[_addr] = 0;
        emit Whitelisted(_addr, 0);
    }

    function enableMint() external onlyOwner {
        require(!mintAllowed, "Already enabled");

        mintAllowed = true;
        emit MintEnabled();
    }

    function setBrewlabsToken(IERC20 token) external onlyOwner {
        require(address(token) != address(0x0), "Invalid token");
        brews = token;
        emit SetBrewlabsToken(address(token));
    }

    function setFeeToken(address token, bool enabled) external onlyOwner {
        require(token != address(0x0), "Invalid token");
        tokenAllowed[token] = enabled;
        emit SetFeeToken(token, enabled);
    }

    function setMintPrice(uint256 tokenFee, uint256 brewsFee) external onlyOwner {
        mintFee = tokenFee;
        brewsMintFee = brewsFee;
        emit SetMintPrice(tokenFee, brewsFee);
    }

    function setUpgradePrice(uint256 tokenFee, uint256 brewsFee) external onlyOwner {
        upgradeFee = tokenFee;
        brewsUpgradeFee = brewsFee;
        emit SetUpgradePrice(tokenFee, brewsFee);
    }

    function setOneTimeMintLimit(uint256 limit) external onlyOwner {
        oneTimeLimit = limit;
        emit SetOneTimeLimit(limit);
    }

    function setMaxSupply(uint256 supply) external onlyOwner {
        require(supply > maxSupply, "Small amount");
        maxSupply = supply;
        emit SetMaxSupply(supply);
    }

    function setMirrorNft(address nft) external onlyOwner {
        mirrorNft = IBrewlabsMirrorNft(nft);
        emit SetMirrorNft(nft);
    }

    function setNftStakingContract(address staking) external onlyOwner {
        require(staking != address(0x0), "Invalid address");

        IBrewlabsNftStaking(staking).forceUnstake(address(this), 1);
        nftStaking = staking;
        mirrorNft.setNftStakingContract(staking);

        emit SetNftStakingContract(staking);
    }

    function setBrewlabsWallet(address wallet) external onlyOwner {
        require(wallet != address(0x0), "Invalid address");
        brewsWallet = wallet;
        emit SetBrewlabsWallet(wallet);
    }

    function setStakingAddress(address wallet) external onlyOwner {
        require(wallet != address(0x0), "Invalid address");
        stakingAddr = wallet;
        emit SetStakingAddress(wallet);
    }

    function setServiceInfo(address _addr, uint256 _fee) external {
        require(msg.sender == treasury, "setServiceInfo: FORBIDDEN");
        require(_addr != address(0x0), "Invalid address");

        treasury = _addr;
        performanceFee = _fee;
        emit ServiceInfoChanged(_addr, _fee);
    }

    function setTokenBaseUri(string memory _uri) external onlyOwner {
        _tokenBaseURI = _uri;
        emit BaseURIUpdated(_uri);
    }

    function rescueTokens(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            uint256 _ethAmount = address(this).balance;
            payable(msg.sender).transfer(_ethAmount);
        } else {
            uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
        }
    }

    function _base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        // load the table into memory
        string memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory result = new string(encodedLen + 32);

        assembly {
            // set the actual output length
            mstore(result, encodedLen)

            // prepare the lookup table
            let tablePtr := add(table, 1)

            // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

            // result ptr, jump over length
            let resultPtr := add(result, 32)

            // run over the input, 3 bytes at a time
            for {} lt(dataPtr, endPtr) {} {
                dataPtr := add(dataPtr, 3)

                // read 3 bytes
                let input := mload(dataPtr)

                // write 4 characters
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(input, 0x3F)))))
                resultPtr := add(resultPtr, 1)
            }

            // padding with '='
            switch mod(mload(data), 3)
            case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
            case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
        }

        return result;
    }

    /**
     * onERC721Received(address operator, address from, uint256 tokenId, bytes data) → bytes4
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data)
        public
        override
        returns (bytes4)
    {
        require(msg.sender == address(this) || msg.sender == address(mirrorNft), "not enabled NFT");
        return super.onERC721Received(operator, from, tokenId, data);
    }

    receive() external payable {}
}
