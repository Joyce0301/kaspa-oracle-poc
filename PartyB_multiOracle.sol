// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice 对齐新版 PartyA：dataRequested() + fulfillData(uint256)
interface IPartyA_TwoOracle {
    function dataRequested() external view returns (bool);
    function fulfillData(uint256 value) external;
}

/// @title Day1 PartyB Minimal Relay (production-friendly PoC)
/// @notice Oracle operator calls PartyB.submit(value), PartyB forwards to PartyA.fulfillData(value).
/// @dev Chinese comments are used; require() messages stay English to avoid Solidity Unicode string issues.
contract PartyB_multiOracle {
    /* ========== 基本角色 ========== */

    /// @notice PartyB 合约管理员（部署者）
    address public partyB;

    /// @notice 对接的 PartyA 合约地址
    address public partyA;

    /// @notice 允许调用 submit 的 oracle 操作员地址（建议：对应 oracle 的 EOA）
    address public oracleOperator;

    event Submitted(address indexed operator, uint256 value);

    constructor(address _partyA, address _oracleOperator) {
        require(_partyA != address(0), "PartyA is zero");
        require(_oracleOperator != address(0), "Operator is zero");

        partyB = msg.sender;
        partyA = _partyA;
        oracleOperator = _oracleOperator;
    }

    modifier onlyPartyB() {
        require(msg.sender == partyB, "Not PartyB admin");
        _;
    }

    modifier onlyOracleOperator() {
        require(msg.sender == oracleOperator, "Not oracle operator");
        _;
    }

    /* ========== 管理接口（可选但很实用） ========== */

    /// @notice 更换 PartyA 地址（工程上可能会重新部署 PartyA）
    function setPartyA(address _partyA) external onlyPartyB {
        require(_partyA != address(0), "PartyA is zero");
        partyA = _partyA;
    }

    /// @notice 更换 oracle operator（工程上常见：换机器/换 key）
    function setOracleOperator(address _newOperator) external onlyPartyB {
        require(_newOperator != address(0), "Operator is zero");
        oracleOperator = _newOperator;
    }

    /* ========== 提交流程 ========== */

    /// @notice Oracle 操作员提交数据（uint256）给 PartyA
    function submit(uint256 value) external onlyOracleOperator {
        // 必须确保 PartyA 处于“已请求但未完成”的状态
        require(IPartyA_TwoOracle(partyA).dataRequested(), "PartyA not requested");

        // 由 PartyB 转发到 PartyA（注意：PartyA 还会做 oracle 白名单校验）
        IPartyA_TwoOracle(partyA).fulfillData(value);

        emit Submitted(msg.sender, value);
    }
}

