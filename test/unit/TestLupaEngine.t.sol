// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {DeployLupaEngine} from "../../script/DeployLupaEngine.s.sol";
import {LupaEngine} from "../../src/LupaEngine.sol";
import {LupaStablecoin} from "../../src/LupaStablecoin.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {NetworkConfig} from "../../script/structs/Config.sol";
import {CustomMockAggregatorV3} from "../../script/mocks/CustomMockAggregatorV3.sol";

contract TestLupa is Test {
    LupaEngine public lupaEngine;
    LupaStablecoin public lupaStablecoin;
    NetworkConfig public activeNetworkConfig;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    CustomMockAggregatorV3 public wethFeed;
    CustomMockAggregatorV3 public wbtcFeed;
    address public TEST_USER = address(1);
    address public LIQUIDATOR = address(2);
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant DEPOSIT_WETH_WEI = 1 ether;
    uint256 private constant LUPA_MINT_AMOUNT = 1500 ether;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    event LupaMinted(address indexed to, uint256 indexed amount);
    event TokenAdded(address indexed token);
    event Redeemed(address indexed user, address indexed _token, uint256 _amount);
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        address indexed collateralToken,
        uint256 totalCollateral,
        uint256 amount
    );

    function setUp() public {
        DeployLupaEngine deployLupaEngine = new DeployLupaEngine();
        (lupaEngine, lupaStablecoin, activeNetworkConfig) = deployLupaEngine.run();

        weth = ERC20Mock(activeNetworkConfig.tokensAllowed[0]);
        wbtc = ERC20Mock(activeNetworkConfig.tokensAllowed[1]);
        weth.mint(TEST_USER, STARTING_USER_BALANCE);
        wbtc.mint(TEST_USER, STARTING_USER_BALANCE);

        wethFeed = CustomMockAggregatorV3(activeNetworkConfig.priceFeeds[0]);
        wbtcFeed = CustomMockAggregatorV3(activeNetworkConfig.priceFeeds[1]);
    }

    modifier deposited() {
        vm.startPrank(address(TEST_USER));
        weth.approve(address(lupaEngine), DEPOSIT_WETH_WEI);
        lupaEngine.depositCollateral(address(weth), DEPOSIT_WETH_WEI);
        vm.stopPrank();
        _;
    }

    modifier depositedAndMinted() {
        vm.startPrank(address(TEST_USER));
        weth.approve(address(lupaEngine), DEPOSIT_WETH_WEI);
        vm.expectEmit(true, true, false, false, address(lupaEngine));
        emit LupaMinted(TEST_USER, LUPA_MINT_AMOUNT);
        lupaEngine.depositCollateralAndMintLupa(address(weth), DEPOSIT_WETH_WEI, LUPA_MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        address[] memory tokens = new address[](2);
        tokens[0] = 0xdd13E55209Fd76AfE204dBda4007C227904f0a81; // weth
        tokens[1] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063; //wbtc

        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        vm.expectRevert(LupaEngine.LupaEngine__PriceFeedAndTokensAreNotTheSameLength.selector);
        new LupaEngine(address(1), tokens, priceFeeds);
    }

    function testAddAllowedToken() public {
        uint256 deployerPrivateKey = vm.envUint(activeNetworkConfig.pkSelector);
        address deployer = vm.addr(deployerPrivateKey);
        vm.startPrank(deployer);
        vm.expectEmit(true, false, false, false, address(lupaEngine));
        emit TokenAdded(address(2));
        lupaEngine.addAllowedTokens(address(2));
    }

    function testAddAllowedTokenRevert() public {
        uint256 deployerPrivateKey = vm.envUint(activeNetworkConfig.pkSelector);
        address deployer = vm.addr(deployerPrivateKey);
        vm.startPrank(deployer);
        vm.expectRevert(LupaEngine.LupaEngine__TokenNotAllowed.selector);
        lupaEngine.addAllowedTokens(address(0));
    }

    function testdepositCollateralAndMintLupa() public {
        vm.startPrank(address(TEST_USER));
        weth.approve(address(lupaEngine), DEPOSIT_WETH_WEI);
        vm.expectEmit(true, true, false, false, address(lupaEngine));
        emit LupaMinted(TEST_USER, LUPA_MINT_AMOUNT);
        lupaEngine.depositCollateralAndMintLupa(address(weth), DEPOSIT_WETH_WEI, LUPA_MINT_AMOUNT);
        vm.stopPrank();
    }

    function testDepositCollateral() public deposited {
        uint256 totValue = lupaEngine.getTotalValueOfCollaterInUSDByUser(TEST_USER);
        (, int256 price,,,) = wethFeed.latestRoundData();
        uint256 calculatedValue = ((uint256(price) * ADDITIONAL_FEED_PRECISION) * DEPOSIT_WETH_WEI) / PRECISION;
        assertEq(totValue, calculatedValue);
    }

    function testUserTokenBalance() public view {
        assertEq(weth.balanceOf(address(TEST_USER)), STARTING_USER_BALANCE);
        assertEq(wbtc.balanceOf(address(TEST_USER)), STARTING_USER_BALANCE);
    }

    function testCanGetLupaAddress() public view {
        assumeNotZeroAddress(address(lupaEngine));
    }

    function testMintLupa() public deposited {
        vm.prank(address(TEST_USER));
        vm.expectEmit(true, true, false, false, address(lupaEngine));
        emit LupaMinted(TEST_USER, LUPA_MINT_AMOUNT);
        lupaEngine.mintLupa(LUPA_MINT_AMOUNT);
    }

    function testMintRevert() public {
        vm.startPrank(address(TEST_USER));
        weth.approve(address(lupaEngine), DEPOSIT_WETH_WEI); // 1 ether
        /**
         * 1 ETH = 3000 $
         *     I should be able to mint withot revert up to  1500LN
         */
        lupaEngine.depositCollateral(address(weth), DEPOSIT_WETH_WEI);
        uint256 mintAmount = 2000 ether;

        bytes4 selector = bytes4(keccak256("LupaEngine__HealthFactorIsTooLow(uint256,address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 750000000000000000, TEST_USER));
        lupaEngine.mintLupa(mintAmount);
    }

    function testRedeemCollateralForLupa() public depositedAndMinted {
        vm.startPrank(address(TEST_USER));
        lupaStablecoin.approve(address(lupaEngine), LUPA_MINT_AMOUNT);
        vm.expectEmit(true, true, false, false, address(lupaEngine));
        emit Redeemed(TEST_USER, address(weth), DEPOSIT_WETH_WEI);
        lupaEngine.redeemCollateralForLupa(address(weth), LUPA_MINT_AMOUNT, DEPOSIT_WETH_WEI);
    }

    function testRedeemCollateralForLupaRevertNotEnoughCollateral() public depositedAndMinted {
        vm.startPrank(address(TEST_USER));
        lupaStablecoin.approve(address(lupaEngine), LUPA_MINT_AMOUNT);
        vm.expectRevert(LupaEngine.LupaEngine__NotEnoughCollateral.selector);
        lupaEngine.redeemCollateralForLupa(address(weth), LUPA_MINT_AMOUNT, DEPOSIT_WETH_WEI + 1);
    }

    function testRedeemCollateraRevert() public depositedAndMinted {
        vm.startPrank(address(TEST_USER));
        bytes4 selector = bytes4(keccak256("LupaEngine__HealthFactorIsTooLow(uint256,address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, 0, address(TEST_USER)));
        lupaEngine.redeemCollateral(address(weth), DEPOSIT_WETH_WEI);
    }

    function testGetTotalValueOfCollaterInUSDByUser() public view {
        uint256 totValue = lupaEngine.getTotalValueOfCollaterInUSDByUser(TEST_USER);
        assertEq(totValue, 0);
    }

    function testLiquidateUser() public depositedAndMinted {
        // make the value of collateral drop
        // impersonate another account and call liquidateUser
        vm.startPrank(address(LIQUIDATOR));

        weth.mint(address(LIQUIDATOR), 10000 ether);
        weth.approve(address(lupaEngine), type(uint256).max);
        lupaEngine.depositCollateralAndMintLupa(address(weth), DEPOSIT_WETH_WEI + 1 ether, LUPA_MINT_AMOUNT);

        wethFeed.setNewAnswer(2000e8);

        lupaStablecoin.approve(address(lupaEngine), type(uint256).max);

        vm.expectEmit(true, true, true, false, address(lupaEngine));
        emit Liquidated(LIQUIDATOR, TEST_USER, address(weth), DEPOSIT_WETH_WEI + 1 ether, LUPA_MINT_AMOUNT);
        lupaEngine.liquidateUser(TEST_USER, address(weth), 1500e18);
    }

    function testGetHealthFactor() public depositedAndMinted {
        uint256 hf = lupaEngine.getHealtFactor(TEST_USER);
        assertEq(hf, 1e18);
    }

    function testGetHealthFactorNotRevertIfETHPriceChangeAndMintMoreETH() public depositedAndMinted {
        vm.startPrank(address(LIQUIDATOR));

        weth.mint(address(LIQUIDATOR), 10000 ether);
        weth.approve(address(lupaEngine), type(uint256).max);
        lupaEngine.depositCollateralAndMintLupa(address(weth), DEPOSIT_WETH_WEI + 1 ether, LUPA_MINT_AMOUNT);

        wethFeed.setNewAnswer(2000e8);

        uint256 hf = lupaEngine.getHealtFactor(LIQUIDATOR);
        /**
         * 1500 * 50 / 100 = 750
         *     750 *1e18 / 1500e18
         */
        assertEq(hf, 1333333333333333333);
    }
}
