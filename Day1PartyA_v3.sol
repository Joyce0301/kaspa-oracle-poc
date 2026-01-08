// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Day1PartyA_v3 {
    address public partyA;
    bytes32 public commitment;
    bool public committed;

    bool public dataRequested;

    // Oracle 回写的数据（最小 PoC：存一个 bytes32）
    bytes32 public latestData;
    bool public dataFulfilled;

    event DataRequested(address indexed partyA);
    event DataFulfilled(bytes32 data);

    constructor(bytes32 _commitment) {
        partyA = msg.sender;
        commitment = _commitment;
    }

    function commit() external {
        require(msg.sender == partyA, "Not PartyA");
        require(!committed, "Already committed");
        committed = true;
    }

    function requestData() external {
        require(msg.sender == partyA, "Not PartyA");
        require(committed, "Commit first");
        require(!dataRequested, "Already requested");

        dataRequested = true;
        emit DataRequested(partyA);
    }

    // ✅ PartyB/Oracle 回写入口：最小版本（先不做权限控制）
    function fulfillData(bytes32 data) external {
        require(dataRequested, "No active request");
        require(!dataFulfilled, "Already fulfilled");

        latestData = data;
        dataFulfilled = true;

        // 如果你希望一次请求只允许一次回写，回写完把 dataRequested 清掉
        dataRequested = false;

        emit DataFulfilled(data);
    }
}
