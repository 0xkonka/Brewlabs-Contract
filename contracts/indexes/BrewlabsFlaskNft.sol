// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {ERC721, ERC721Enumerable, IERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DefaultOperatorFilterer} from "operator-filter-registry/src/DefaultOperatorFilterer.sol";

contract BrewlabsFlaskNft is ERC721Enumerable, ERC721Holder, DefaultOperatorFilterer, Ownable {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using Strings for address;

    uint256 private tokenIndex;
    string private _tokenBaseURI = "";

    string[5] rarityNames = ["Common", "Uncommon", "Rare", "Epic", "Legendary"];
    mapping(uint256 => uint256) private rarities;

    bool public mintAllowed;
    uint256 public ethMintFee;
    uint256 public brewsMintFee;
    IERC20 public feeToken = IERC20(0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7);
    address public feeWallet = 0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F;

    mapping(address => uint256) public whitelist;

    event BaseURIUpdated(string uri);
    event MintEnabled();
    event ItemUpgraded(uint256[3] tokenIds, uint256 newTokenId);
    event SetFeeToken(address token);
    event SetFeeWallet(address wallet);
    event SetMintPrice(uint256 ethFee, uint256 brewsFee);
    event Whitelisted(address indexed account, uint256 count);

    modifier onlyMintable() {
        require(mintAllowed, "Mint is disabled");
        _;
    }

    constructor() ERC721("Brewlabs Flask Nft", "BFL") {}

    function mint() external payable onlyMintable returns (uint256) {
        if (whitelist[msg.sender] == 0) {
            require(msg.value >= ethMintFee, "Insufficient BNB fee");

            // process mint fee
            payable(feeWallet).transfer(ethMintFee);
            if (msg.value > ethMintFee) {
                payable(msg.sender).transfer(msg.value - ethMintFee);
            }
            feeToken.safeTransferFrom(msg.sender, feeWallet, brewsMintFee);
        } else {
            whitelist[msg.sender] = whitelist[msg.sender] - 1;
        }

        // mint NFT
        tokenIndex++;
        rarities[tokenIndex] = _randomRarity(tokenIndex);

        _safeMint(msg.sender, tokenIndex);
        return tokenIndex;
    }

    function _randomRarity(uint256 tokenId) internal view returns (uint256) {
        uint256 randomNum = uint256(
            keccak256(
                abi.encode(msg.sender, tx.gasprice, block.number, block.timestamp, blockhash(block.number - 1), tokenId)
            )
        );

        return randomNum % rarityNames.length;
    }

    function upgradeItem(uint256[3] memory tokenIds) external returns (uint256) {
        require(rarities[tokenIds[0]] < 2, "Only common or uncommon NFT can be upgraded");
        require(
            rarities[tokenIds[0]] == rarities[tokenIds[1]] && rarities[tokenIds[1]] == rarities[tokenIds[2]],
            "Rarities should be same"
        );

        uint256 newRarity = rarities[tokenIds[0]] + 1;
        for (uint256 i = 0; i < 3; i++) {
            _safeTransfer(msg.sender, address(this), tokenIds[i], "");
            _burn(tokenIds[i]);
        }

        // mint NFT
        tokenIndex++;
        rarities[tokenIndex] = newRarity;

        _safeMint(msg.sender, tokenIndex);
        emit ItemUpgraded(tokenIds, tokenIndex);
        return tokenIndex;
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override (ERC721, IERC721)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        override (ERC721, IERC721)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId)
        public
        override (ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override (ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override (ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function rarityOf(uint256 tokenId) external view returns (uint256) {
        return rarities[tokenId];
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "BrewlabsFlaskNft: URI query for nonexistent token");

        string memory base = _baseURI();
        string memory description = string(
            abi.encodePacked(
                '"description": "Brewlabs Flask NFTs represent users fractionalised ownership of a particular basket of tokens(Index)."'
            )
        );

        string memory attributes = '"attributes":[';
        attributes = string(
            abi.encodePacked(attributes, '{"trait_type":"Rarity", "value":"', rarityNames[rarities[tokenId]], '"}]')
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
                rarityNames[rarities[tokenId]],
                ".png",
                '", ',
                attributes,
                "}"
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", _base64(bytes(metadata))));
    }

    function enableMint() external onlyOwner {
        require(!mintAllowed, "Already enabled");

        mintAllowed = true;
        emit MintEnabled();
    }

    function setTokenBaseUri(string memory _uri) external onlyOwner {
        _tokenBaseURI = _uri;
        emit BaseURIUpdated(_uri);
    }

    function setFeeToken(IERC20 token) external onlyOwner {
        require(address(token) != address(0x0), "Invalid token");
        feeToken = token;
        emit SetFeeToken(address(token));
    }

    function setFeeWallet(address wallet) external onlyOwner {
        require(wallet != address(0x0), "Invalid address");
        feeWallet = wallet;
        emit SetFeeWallet(wallet);
    }

    function setMintPrice(uint256 ethFee, uint256 brewsFee) external onlyOwner {
        ethMintFee = ethFee;
        brewsMintFee = brewsFee;
        emit SetMintPrice(ethFee, brewsFee);
    }

    function addToWhitelist(address _addr, uint256 _count) external onlyOwner {
        whitelist[_addr] = _count;
        emit Whitelisted(_addr, _count);
    }

    function removeFromWhitelist(address _addr) external onlyOwner {
        whitelist[_addr] = 0;
        emit Whitelisted(_addr, 0);
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

    function _baseURI() internal view override returns (string memory) {
        return _tokenBaseURI;
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
        require(msg.sender == address(this), "not enabled NFT");
        return super.onERC721Received(operator, from, tokenId, data);
    }

    receive() external payable {}
}
