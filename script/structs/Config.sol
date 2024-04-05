// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

struct NetworkConfig {
    address[] tokensAllowed;
    address[] priceFeeds;
    string pkSelector;
}
