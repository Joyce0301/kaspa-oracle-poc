// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Day1Party1 {
    address public party1;
    uint256 public agreedValue;
    bool public submitted;

    constructor(uint256 _value) {
        party1 = msg.sender;
        agreedValue = _value;
    }

    function submit() external {
        require(msg.sender == party1, "Not Party1");
        submitted = true;
    }
}
