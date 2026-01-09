// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Day1PartyA_vMulti {
    address public partyA;
    bytes32 public commitment;
    bool public committed;

    // 当前是否有未完成的请求
    bool public dataRequested;

    // 最近一次回写的数据
    bytes32 public latestData;

    // 用轮次来让 PoC 可重复测试
    uint256 public roundId; // 从 0 开始，每次 request +1

    event DataRequested(address indexed partyA, uint256 indexed roundId);
    event DataFulfilled(bytes32 data, uint256 indexed roundId);

    constructor(bytes32 _commitment) {
        partyA = msg.sender;
        commitment = _commitment;
    }

    function commit() external {
        require(msg.sender == partyA, "Not PartyA");
        require(!committed, "Already committed");
        committed = true;
    }

    /// @notice 发起一次新的数据请求（多轮：每次 request 都是新 round）
    function requestData() external {
        require(msg.sender == partyA, "Not PartyA");
        require(committed, "Commit first");
        require(!dataRequested, "Previous request not fulfilled");

        // 开启新一轮
        roundId += 1;
        dataRequested = true;

        emit DataRequested(partyA, roundId);
    }

    /// @notice Oracle 回写数据（多轮：每轮只能 fulfill 一次）
    function fulfillData(bytes32 data) external {
        require(dataRequested, "No active request");

        // 写入结果并关闭本轮请求
        latestData = data;
        dataRequested = false;

        emit DataFulfilled(data, roundId);
    }
}
