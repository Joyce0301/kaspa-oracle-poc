// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Day1PartyA {
    address public partyA;
    bytes32 public commitment;
    bool public committed;

    bool public dataRequested;

    event DataRequested(address indexed partyA);

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
}
