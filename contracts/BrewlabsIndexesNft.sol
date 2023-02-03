// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721, ERC721Enumerable, IERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DefaultOperatorFilterer} from "operator-filter-registry/src/DefaultOperatorFilterer.sol";

interface IBrewlabsIndexes {
    function NUM_TOKENS() external view returns (uint8);
    function tokens(uint256 index) external view returns (address);
    function nftInfo(uint256 _tokenId) external view returns (uint256[] memory, uint256);
}

contract BrewlabsIndexesNft is ERC721Enumerable, DefaultOperatorFilterer, Ownable {
    using Strings for uint256;
    using Strings for address;

    string private _tokenBaseURI = "";
    uint256 private tokenIndex;

    mapping(address => bool) private isMinter;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => address) private indexes;

    event BaseURIUpdated(string uri);
    event SetMinterRole(address minter, bool status);

    modifier onlyMinter() {
        require(isMinter[msg.sender], "BrewlabsIndexesNft: Caller is not minter");
        _;
    }

    constructor() ERC721("Brewlabs Indexes Nft", "BINDEX") {}

    function mint(address to) external onlyMinter returns (uint256) {
        tokenIndex++;
        _safeMint(to, tokenIndex);
        _setTokenURI(tokenIndex, tokenIndex.toString());

        indexes[tokenIndex] = msg.sender;
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

    function setMinterRole(address minter, bool status) external onlyOwner {
        isMinter[minter] = status;
        emit SetMinterRole(minter, status);
    }

    function setTokenBaseURI(string memory _uri) external onlyOwner {
        _tokenBaseURI = _uri;
        emit BaseURIUpdated(_uri);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "BrewlabsIndexesNft: URI query for nonexistent token");

        string memory base = _baseURI();
        string memory description = string(
            abi.encodePacked(
                '"description": "', name(), " #", tokenId.toString(), ': Brewlabs Indexes NFT description"'
            )
        );

        IBrewlabsIndexes _indexes = IBrewlabsIndexes(indexes[tokenId]);
        uint8 numTokens = _indexes.NUM_TOKENS();
        (uint256[] memory amounts, uint256 ethAmount) = _indexes.nftInfo(tokenId);

        string memory attributes = '"attributes":[';
        for (uint8 i = 0; i < numTokens; i++) {
            address _token = _indexes.tokens(i);
            if (i > 0) {
                attributes = string(abi.encodePacked(attributes, ","));
            }

            attributes = string(
                abi.encodePacked(
                    attributes,
                    '{"trait_type":"token',
                    uint256(i).toString(),
                    '", "value":"',
                    _token.toHexString(),
                    '"},',
                    '{"trait_type":"amount',
                    uint256(i).toString(),
                    '", "value":"',
                    amounts[i].toString(),
                    '"}'
                )
            );
        }
        attributes = string(
            abi.encodePacked(attributes, ', {"trait_type":"zapped amount", "value":"', ethAmount.toString(), '"}]')
        );

        // If both are set, concatenate the baseURI (via abi.encodePacked).
        string memory metadata = string(
            abi.encodePacked('{"name": "', name(), '", ', description, ', "image": "', base, '", ', attributes, "}")
        );

        return string(abi.encodePacked("data:application/json;base64,", _base64(bytes(metadata))));
    }

    function _getNftInfo(uint256 tokenId) internal view returns (uint256[] memory, uint256) {
        return IBrewlabsIndexes(indexes[tokenId]).nftInfo(tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _tokenBaseURI;
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal {
        require(_exists(tokenId), "BrewlabsIndexesNft: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
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
}
