// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

contract CustomMockAggregatorV3 {
    int256 private s_answer;

    constructor(int256 _answer) {
        s_answer = _answer;
    }

    function setNewAnswer(int256 _answer) external {
        s_answer = _answer;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 1;
        answer = s_answer;
        startedAt = 1;
        updatedAt = 1;
        answeredInRound = 1;
    }
}
