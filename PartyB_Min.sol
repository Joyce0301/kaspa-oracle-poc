// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPartyA_v3 {
    function dataRequested() external view returns (bool);
    function fulfillData(bytes32 data) external;
}

contract Day1PartyB_Min {
    address public partyB;
    address public partyA;

    event Submitted(bytes32 data);

    constructor(address _partyA) {
        partyB = msg.sender;
        partyA = _partyA;
    }

    function submit(bytes32 data) external {
        require(msg.sender == partyB, "Not PartyB");
        require(IPartyA_v3(partyA).dataRequested(), "PartyA not requested");

        IPartyA_v3(partyA).fulfillData(data);
        emit Submitted(data);
    }
}
