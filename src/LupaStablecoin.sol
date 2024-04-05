// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20, ERC20Burnable} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title Decentralized Stablecoin called Lupa
 * @author fabriziogianni7
 * @custom:collateral Exogenous
 * @custom:minting Algorithmic
 * @custom:relativestability Pegged to USD
 *
 * This is an ERC20 goverded by our DSCEngine contract
 */
contract LupaStablecoin is ERC20Burnable, Ownable {
    error DecentralizedStablecoin__BalanceLessThanBurnAmount();
    error DecentralizedStablecoin__AmountMustBeMoreThanZero();
    error DecentralizedStablecoin__MintToZeroAddress();

    constructor() ERC20("Lupa", "LP") Ownable(msg.sender) {}

    // mint
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStablecoin__MintToZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStablecoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
    // burn

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (balance < _amount) {
            revert DecentralizedStablecoin__BalanceLessThanBurnAmount();
        }
        if (_amount <= 0) {
            revert DecentralizedStablecoin__AmountMustBeMoreThanZero();
        }
        super.burn(_amount);
    }
}
