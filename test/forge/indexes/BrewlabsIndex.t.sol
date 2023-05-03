// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsIndex, IERC20} from "../../../contracts/indexes/BrewlabsIndex.sol";
import {BrewlabsIndexFactory} from "../../../contracts/indexes/BrewlabsIndexFactory.sol";
import {BrewlabsIndexNft, IERC721} from "../../../contracts/indexes/BrewlabsIndexNft.sol";
import {BrewlabsNftDiscountMgr} from "../../../contracts/BrewlabsNftDiscountMgr.sol";
import {BrewlabsDeployerNft} from "../../../contracts/indexes/BrewlabsDeployerNft.sol";

import {IBrewlabsIndex} from "../../../contracts/indexes/IBrewlabsIndex.sol";
import {MockErc721} from "../../../contracts/mocks/MockErc721WithRarity.sol";

import {Utils} from "../utils/Utils.sol";
import "../../../contracts/libs/IUniRouter02.sol";

contract BrewlabsIndexTest is Test {
    IERC20 internal token0 = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    IERC20 internal token1 = IERC20(0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47);

    address swapRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address internal WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address internal BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address internal USDT = 0x55d398326f99059fF775485246999027B3197955;
    address internal USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    uint256 internal FEE_DENOMINATOR = 10000;

    address internal indexOwner = address(0x111);
    address internal deployer = address(0x123);

    BrewlabsIndexFactory internal factory;
    BrewlabsIndexNft internal indexNft;
    BrewlabsDeployerNft internal deployerNft;
    BrewlabsNftDiscountMgr internal discountMgr;
    IBrewlabsIndex internal index;

    MockErc721 internal nft;

    Utils internal utils;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    event TokenZappedIn(
        address indexed user,
        uint256 ethAmount,
        uint256[] percents,
        uint256[] amountOuts,
        uint256 usdAmount,
        uint256 commission
    );
    event TokenZappedOut(address indexed user, uint256[] amounts, uint256 ethAmount, uint256 commission);
    event TokenClaimed(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 commission);
    event TokenLocked(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 tokenId);
    event TokenUnLocked(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 tokenId);

    event DeployerNftMinted(address indexed user, address nft, uint256 tokenId);
    event DeployerNftStaked(address indexed user, uint256 tokenId);
    event DeployerNftUnstaked(address indexed user, uint256 tokenId);
    event PendingCommissionClaimed(address indexed user);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event SetDeployerFee(uint256 fee);
    event SetSettings(address router, address[][] paths);

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();
        nft = new MockErc721();

        BrewlabsIndex impl = new BrewlabsIndex();
        indexNft = new BrewlabsIndexNft();
        deployerNft = new BrewlabsDeployerNft();
        discountMgr = new BrewlabsNftDiscountMgr();

        factory = new BrewlabsIndexFactory();
        factory.initialize(address(impl), indexNft, deployerNft, BUSD, 0, indexOwner);
        factory.setDiscountManager(address(discountMgr));
        indexNft.setAdmin(address(factory));
        deployerNft.setAdmin(address(factory));

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = address(token0);
        _paths[1][0] = WBNB;
        _paths[1][1] = address(token1);

        vm.startPrank(deployer);
        index = IBrewlabsIndex(factory.createBrewlabsIndex(tokens, swapRouter, _paths, 20)); // 0.2%
        vm.stopPrank();
    }

    function tryAddDicountConfig() internal {
        discountMgr.setCollection(nft);
        discountMgr.setDiscount(0, 500); // 5%
        discountMgr.setDiscount(1, 1000); // 10%
        discountMgr.setDiscount(2, 3000); // 30%
    }

    function test_zapInWithEth() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);

        tryAddDicountConfig();
        assertEq(discountMgr.discountOf(user), 0);
        nft.mint(user, 0);
        assertEq(discountMgr.discountOf(user), 500);
        nft.mint(user, 1);
        assertEq(discountMgr.discountOf(user), 1000);

        vm.startPrank(user);

        uint256 price = index.getPriceFromChainlink();

        uint256 discount = FEE_DENOMINATOR - discountMgr.discountOf(user);
        address feeWallet = factory.brewlabsWallet();

        uint256 ethAmount = 0.5 ether;

        uint256 brewsFee = (ethAmount * factory.brewlabsFee() * discount) / FEE_DENOMINATOR ** 2;
        uint256 deployerFee = (ethAmount * index.fee() * discount) / FEE_DENOMINATOR ** 2;
        uint256 feeWalletBalance = address(feeWallet).balance;
        uint256 deployerBalance = address(index.deployer()).balance;
        uint256 _usdAmount = (ethAmount - (brewsFee + deployerFee)) * price / 1 ether;

        uint256[] memory percents = new uint256[](2);
        percents[0] = 5000;
        percents[1] = 5000;

        uint256[] memory _amounts = new uint256[](2);
        {
            uint256 _ethAmount = (ethAmount - (brewsFee + deployerFee)) * percents[0] / FEE_DENOMINATOR;
            uint256[] memory _amountOuts =
                IUniRouter02(swapRouter).getAmountsOut(_ethAmount, index.getSwapPath(0, true));
            _amounts[0] = _amountOuts[_amountOuts.length - 1];

            _ethAmount = (ethAmount - (brewsFee + deployerFee)) * percents[1] / FEE_DENOMINATOR;
            _amountOuts = IUniRouter02(swapRouter).getAmountsOut(_ethAmount, index.getSwapPath(1, true));
            _amounts[1] = _amountOuts[_amountOuts.length - 1];
        }

        vm.expectEmit(true, false, false, true);
        emit TokenZappedIn(
            user, ethAmount - (brewsFee + deployerFee), percents, _amounts, _usdAmount, brewsFee + deployerFee
            );
        index.zapIn{value: ethAmount}(address(0), 0, percents);

        (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);

        assertEq(usdAmount, _usdAmount);
        assertEq(token0.balanceOf(address(index)), amounts[0]);
        assertEq(token1.balanceOf(address(index)), amounts[1]);
        assertEq(address(feeWallet).balance - feeWalletBalance, brewsFee);
        assertEq(address(index.deployer()).balance - deployerBalance, deployerFee);

        assertEq(index.totalStaked(0), amounts[0]);
        assertEq(index.totalStaked(1), amounts[1]);

        // emit log_named_uint("USD Amount", usdAmount);
        // emit log_named_uint("token0", amounts[0]);
        // emit log_named_uint("token1", amounts[1]);

        vm.stopPrank();
    }

    function trySwapUsdt(address user, uint256 amount) internal returns(uint256) {
        uint256 beforeAmt = IERC20(USDT).balanceOf(user);

        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = USDT;

        IUniRouter02(swapRouter).swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0, path, user, block.timestamp + 600
        );

        return IERC20(USDT).balanceOf(user) - beforeAmt;
    }

    function test_zapInWithUSDT() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);

        uint256 amountIn = trySwapUsdt(user, 1 ether);
        factory.setAllowedToken(USDT, 1);

        vm.startPrank(user);
        uint256 price = index.getPriceFromChainlink();

        uint256 discount = FEE_DENOMINATOR - discountMgr.discountOf(user);
        uint256 ethAmount;
        {
            
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WBNB;
        uint256[] memory amounts = IUniRouter02(swapRouter).getAmountsOut(amountIn, path);
        ethAmount = amounts[amounts.length - 1];
        }

        uint256 brewsFee = (ethAmount * factory.brewlabsFee() * discount) / FEE_DENOMINATOR ** 2;
        uint256 deployerFee = (ethAmount * index.fee() * discount) / FEE_DENOMINATOR ** 2;
        uint256 _usdAmount = (ethAmount - (brewsFee + deployerFee)) * price / 1 ether;

        uint256[] memory percents = new uint256[](2);
        percents[0] = 5000;
        percents[1] = 5000;

        uint256[] memory _amounts = new uint256[](2);
        {
            uint256 _ethAmount = (ethAmount - (brewsFee + deployerFee)) * percents[0] / FEE_DENOMINATOR;
            uint256[] memory _amountOuts =
                IUniRouter02(swapRouter).getAmountsOut(_ethAmount, index.getSwapPath(0, true));
            _amounts[0] = _amountOuts[_amountOuts.length - 1];

            _ethAmount = (ethAmount - (brewsFee + deployerFee)) * percents[1] / FEE_DENOMINATOR;
            _amountOuts = IUniRouter02(swapRouter).getAmountsOut(_ethAmount, index.getSwapPath(1, true));
            _amounts[1] = _amountOuts[_amountOuts.length - 1];
        }

        IERC20(USDT).approve(address(index), amountIn);

        vm.expectEmit(true, false, false, true);
        emit TokenZappedIn(
            user, ethAmount - (brewsFee + deployerFee), percents, _amounts, _usdAmount, brewsFee + deployerFee
            );
        index.zapIn(USDT, amountIn, percents);
        vm.stopPrank();
    }
    
    function test_failZapInWithNotSupportedToken() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);

        uint256 amountIn = trySwapUsdt(user, 1 ether);

        vm.startPrank(user);        

        uint256[] memory percents = new uint256[](2);
        percents[0] = 5000;
        percents[1] = 5000;

        IERC20(USDT).approve(address(index), amountIn);

        vm.expectRevert("Cannot zap in with unsupported token");
        index.zapIn(USDT, amountIn, percents);
        vm.stopPrank();
    } 

    function test_failZapInWithNotEnoughAmount() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);

        uint256 amountIn = trySwapUsdt(user, 100000);
        amountIn = 1000;
        factory.setAllowedToken(USDT, 1);

        vm.startPrank(user);        

        uint256[] memory percents = new uint256[](2);
        percents[0] = 5000;
        percents[1] = 5000;

        IERC20(USDT).approve(address(index), amountIn);

        vm.expectRevert("Not enough amount");
        index.zapIn(USDT, amountIn, percents);
        vm.stopPrank();
    }

    function tryZapIn(address token, uint256 amount) internal {
        uint256[] memory percents = new uint256[](2);
        percents[0] = 5000;
        percents[1] = 5000;
        index.zapIn{value: amount}(token, amount, percents);
    }

    function getClaimAmounts(address user, uint256 percent)
        internal
        view
        returns (uint256[] memory, uint256[] memory, uint256)
    {
        uint256 estimatedEthAmount = index.estimateEthforUser(user);
        uint256 discount = FEE_DENOMINATOR - discountMgr.discountOf(user);
        uint256 price = index.getPriceFromChainlink();

        (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);
        bool bCommission = (estimatedEthAmount * price / 1 ether) > usdAmount;
        uint256 profit = bCommission ? ((estimatedEthAmount * price / 1 ether) - usdAmount) : 0;

        uint256[] memory _claimAmounts = new uint256[](2);
        uint256[] memory _claimFees = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            _claimAmounts[i] = (amounts[i] * percent) / FEE_DENOMINATOR;

            if (bCommission) {
                _claimFees[i] =
                    (_claimAmounts[i] * profit * index.totalFee() * discount) / usdAmount / FEE_DENOMINATOR ** 2;
            }
        }

        uint256 commission = 0;
        if (bCommission) {
            commission = (estimatedEthAmount * percent * profit) / FEE_DENOMINATOR;
            commission = (commission * index.totalFee() * discount) / usdAmount / FEE_DENOMINATOR ** 2;
        }

        return (_claimAmounts, _claimFees, commission);
    }

    function test_claimTokens() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);

        tryAddDicountConfig();
        nft.mint(user, 1);

        vm.startPrank(user);

        tryZapIn(address(0), 0.5 ether);

        (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);
        uint256 percent = 6300; // 63%

        (uint256[] memory _claimAmounts, uint256[] memory _claimFees, uint256 commission) =
            getClaimAmounts(user, percent);
        uint256 claimedUsdAmount = (usdAmount * percent) / FEE_DENOMINATOR;
        uint256 prevBalanceForToken0 = token0.balanceOf(user);
        uint256 prevBalanceForToken1 = token1.balanceOf(user);

        utils.mineBlocks(10);
        vm.expectEmit(true, false, false, true);
        emit TokenClaimed(user, _claimAmounts, claimedUsdAmount, commission);
        index.claimTokens(percent);

        assertEq(_claimAmounts[0] - _claimFees[0], token0.balanceOf(user) - prevBalanceForToken0);
        assertEq(_claimAmounts[1] - _claimFees[1], token1.balanceOf(user) - prevBalanceForToken1);

        assertEq(token0.balanceOf(address(index)), amounts[0] - _claimAmounts[0]);
        assertEq(token1.balanceOf(address(index)), amounts[1] - _claimAmounts[1]);

        assertEq(index.totalStaked(0), amounts[0] - _claimAmounts[0]);
        assertEq(index.totalStaked(1), amounts[1] - _claimAmounts[1]);

        (uint256[] memory _amounts, uint256 _usdAmount) = index.userInfo(user);
        assertEq(_amounts[0], amounts[0] - _claimAmounts[0]);
        assertEq(_amounts[1], amounts[1] - _claimAmounts[1]);
        assertEq(_usdAmount, usdAmount - claimedUsdAmount);
        vm.stopPrank();
    }

    function test_zapOutWithETH() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);

        tryAddDicountConfig();
        nft.mint(user, 0);

        vm.startPrank(user);

        tryZapIn(address(0), 0.5 ether);

        (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);
        // emit log_named_uint("USD Amount", usdAmount);
        // emit log_named_uint("token0", amounts[0]);
        // emit log_named_uint("token1", amounts[1]);

        utils.mineBlocks(10);

        uint256 ethAmount = index.estimateEthforUser(user);
        uint256 userBalance = user.balance;

        uint256 _fee = index.totalFee();
        uint256 discount = FEE_DENOMINATOR - discountMgr.discountOf(user);
        uint256 price = index.getPriceFromChainlink();

        uint256 commission = 0;
        if ((ethAmount * price / 1 ether) > usdAmount) {
            uint256 profit = ((ethAmount * price / 1 ether) - usdAmount) * 1e18 / price;
            commission = (profit * _fee * discount) / FEE_DENOMINATOR ** 2;
            ethAmount -= commission;
        }

        vm.expectEmit(true, false, false, true);
        emit TokenZappedOut(user, amounts, ethAmount, commission);
        index.zapOut(address(0));

        assertEq(token0.balanceOf(address(index)), 0);
        assertEq(token1.balanceOf(address(index)), 0);
        assertEq(user.balance - userBalance, ethAmount);

        assertEq(index.totalStaked(0), 0);
        assertEq(index.totalStaked(1), 0);

        (amounts, usdAmount) = index.userInfo(user);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(usdAmount, 0);
        vm.stopPrank();
    }

    function test_mintNft() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        tryZapIn(address(0), 0.5 ether);
        (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);

        utils.mineBlocks(10);
        vm.expectEmit(true, false, false, false);
        emit TokenLocked(user, amounts, 0, 0);
        uint256 tokenId = index.mintNft{value: index.performanceFee()}();
        assertEq(indexNft.ownerOf(tokenId), user);

        string memory _tokenUri = indexNft.tokenURI(tokenId);
        emit log_named_string("IndexNFT URI: ", _tokenUri);

        (, uint256[] memory _amounts, uint256 _ethAmount) = index.nftInfo(tokenId);
        assertEq(_amounts[0], amounts[0]);
        assertEq(_amounts[1], amounts[1]);
        assertEq(_ethAmount, usdAmount);

        assertEq(index.totalStaked(0), amounts[0]);
        assertEq(index.totalStaked(1), amounts[1]);

        (amounts, usdAmount) = index.userInfo(user);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(usdAmount, 0);
        vm.stopPrank();
    }

    function test_stakeNft() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        tryZapIn(address(0), 0.5 ether);

        utils.mineBlocks(10);
        uint256 tokenId = index.mintNft{value: index.performanceFee()}();

        utils.mineBlocks(10);
        (, uint256[] memory _amounts, uint256 _ethAmount) = index.nftInfo(tokenId);

        indexNft.setApprovalForAll(address(index), true);

        vm.expectEmit(true, false, false, true);
        emit TokenUnLocked(user, _amounts, _ethAmount, tokenId);
        index.stakeNft{value: index.performanceFee()}(tokenId);

        assertEq(index.totalStaked(0), _amounts[0]);
        assertEq(index.totalStaked(1), _amounts[1]);

        (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);
        assertEq(amounts[0], _amounts[0]);
        assertEq(amounts[1], _amounts[1]);
        assertEq(usdAmount, _ethAmount);
        vm.stopPrank();
    }

    function test_mintDeployerNft() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.deal(address(0x1111), 10 ether);

        uint256 pFee = index.performanceFee();

        vm.startPrank(deployer);
        vm.expectEmit(true, false, false, true);
        emit DeployerNftMinted(deployer, address(deployerNft), 1);
        uint256 tokenId = index.mintDeployerNft{value: pFee}();
        assertEq(deployerNft.ownerOf(tokenId), deployer);

        vm.expectRevert(abi.encodePacked("Already Mint"));
        index.mintDeployerNft{value: pFee}();
        vm.stopPrank();

        string memory _tokenUri = deployerNft.tokenURI(tokenId);
        emit log_named_string("DeployerNFT URI: ", _tokenUri);

        tryAddDicountConfig();
        nft.mint(user, 1);

        vm.startPrank(user);
        tryZapIn(address(0), 0.5 ether);

        (, uint256 usdAmount) = index.userInfo(user);
        uint256 ethAmount = index.estimateEthforUser(user);

        uint256 _fee = index.totalFee();
        uint256 discount = FEE_DENOMINATOR - discountMgr.discountOf(user);
        uint256 price = index.getPriceFromChainlink();

        uint256 commission = 0;
        if ((ethAmount * price / 1 ether) > usdAmount) {
            uint256 profit = ((ethAmount * price / 1 ether) - usdAmount) * 1e18 / price;
            commission = (profit * _fee * discount) / FEE_DENOMINATOR ** 2;
            ethAmount -= commission;
        }

        index.zapOut(address(0));

        uint256[] memory _pendingCommissions = index.getPendingCommissions();
        assertEq(_pendingCommissions[0], 0);
        assertEq(_pendingCommissions[1], 0);
        assertEq(_pendingCommissions[2], commission);
        assertEq(index.totalCommissions(), commission * price / 1 ether);
        assertEq(index.commissionWallet(), address(0x0));

        vm.stopPrank();
    }

    function test_failMintDeployerNftInNotDeployer() public {
        vm.deal(address(0x1111), 10 ether);
        uint256 pFee = index.performanceFee();

        vm.startPrank(address(0x1111));
        vm.expectRevert("Caller is not the deployer");
        index.mintDeployerNft{value: pFee}();
        vm.stopPrank();
    }

    function test_failMintDeployerNftWithNoPerformanceFee() public {
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodePacked("Should pay small gas to call method"));
        index.mintDeployerNft();
        vm.stopPrank();
    }

    function test_stakeDeployerNft() public {
        assertEq(index.commissionWallet(), deployer);

        vm.startPrank(deployer);
        uint256 tokenId = index.mintDeployerNft{value: index.performanceFee()}();
        deployerNft.safeTransferFrom(deployer, address(0x12345), tokenId);
        vm.stopPrank();

        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.deal(address(0x12345), 1 ether);

        tryAddDicountConfig();
        nft.mint(user, 1);

        vm.startPrank(user);
        tryZapIn(address(0), 0.5 ether);
        index.zapOut(address(0));
        vm.stopPrank();

        uint256[] memory _pendingCommissions = index.getPendingCommissions();

        uint256 beforeBalance = address(0x12345).balance;

        vm.startPrank(address(0x12345));
        deployerNft.setApprovalForAll(address(index), true);
        vm.expectEmit(true, false, false, true);
        emit DeployerNftStaked(address(0x12345), 1);
        index.stakeDeployerNft{value: index.performanceFee()}();

        assertEq(deployerNft.ownerOf(tokenId), address(index));
        assertEq(index.commissionWallet(), address(0x12345));
        assertEq(address(0x12345).balance + index.performanceFee() - beforeBalance, _pendingCommissions[2]);

        _pendingCommissions = index.getPendingCommissions();
        assertEq(_pendingCommissions[2], 0);
        vm.stopPrank();

        vm.startPrank(user);
        tryZapIn(address(0), 0.5 ether);
        index.zapOut(address(0));
        vm.stopPrank();

        _pendingCommissions = index.getPendingCommissions();
        assertEq(_pendingCommissions[2], 0);
    }

    function test_unstakeDeployerNft() public {
        assertEq(index.commissionWallet(), deployer);
        uint256 pFee = index.performanceFee();

        vm.startPrank(deployer);
        uint256 tokenId = index.mintDeployerNft{value: pFee}();
        deployerNft.safeTransferFrom(deployer, address(0x12345), tokenId);
        vm.stopPrank();

        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.deal(address(0x12345), 1 ether);

        vm.startPrank(address(0x12345));
        deployerNft.setApprovalForAll(address(index), true);
        index.stakeDeployerNft{value: pFee}();
        vm.stopPrank();

        vm.startPrank(address(0x12345));
        vm.expectEmit(true, false, false, true);
        emit DeployerNftUnstaked(address(0x12345), 1);
        index.unstakeDeployerNft{value: pFee}();
        vm.stopPrank();

        tryAddDicountConfig();
        nft.mint(user, 1);

        vm.startPrank(user);
        tryZapIn(address(0), 0.5 ether);
        index.zapOut(address(0));
        vm.stopPrank();

        uint256[] memory _pendingCommissions = index.getPendingCommissions();
        assertEq(_pendingCommissions[0], 0);
        assertEq(_pendingCommissions[1], 0);
        assertGe(_pendingCommissions[2], 0);
        assertEq(index.commissionWallet(), address(0x0));
        assertEq(deployerNft.ownerOf(tokenId), address(0x12345));
    }

    function test_failUnstakeDeployerNftInNotCommissionWallet() public {
        assertEq(index.commissionWallet(), deployer);
        uint256 pFee = index.performanceFee();

        vm.startPrank(deployer);
        uint256 tokenId = index.mintDeployerNft{value: pFee}();
        deployerNft.safeTransferFrom(deployer, address(0x12345), tokenId);
        vm.stopPrank();

        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.deal(address(0x12345), 1 ether);

        vm.startPrank(address(0x12345));
        deployerNft.setApprovalForAll(address(index), true);
        index.stakeDeployerNft{value: pFee}();
        vm.stopPrank();

        vm.deal(address(0x1111), 1 ether);
        vm.startPrank(address(0x1111));
        vm.expectRevert("Caller is not the commission wallet");
        index.unstakeDeployerNft{value: pFee}();
        vm.stopPrank();
    }
}
