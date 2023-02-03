// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721, ERC721Enumerable, IERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DefaultOperatorFilterer} from "operator-filter-registry/src/DefaultOperatorFilterer.sol";

interface IBrewlabsIndexes {
    function NUM_TOKENS() external returns (uint256);
    function tokens(uint256 index) external returns (address);
    function nftInfo(uint256 _tokenId) external view returns (uint256[] memory, uint256);
}

contract BrewlabsIndexesNft is ERC721Enumerable, DefaultOperatorFilterer, Ownable {
    using Strings for uint256;

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

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(_baseURI(), _tokenURI));
        }

        return super.tokenURI(tokenId);
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
}
