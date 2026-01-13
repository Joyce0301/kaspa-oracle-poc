// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title Day1 PartyA Two-Oracle Aggregator (production-friendly PoC)
/// @notice PartyA requests data; two whitelisted oracles submit uint256; contract aggregates by arithmetic mean.
/// @dev Chinese comments are used; require() messages stay English to avoid Solidity Unicode string issues.
contract PartyA_multiOracle {
    /* ========== 基本角色 ========== */

    /// @notice PartyA 地址（合约部署者/请求发起方）
    address public immutable partyA;

    /// @notice Oracle 白名单（两个）
    address public oracle1;
    address public oracle2;

    /* ========== 可选的提交门控（保留你原本的设计） ========== */

    bytes32 public commitment;
    bool public committed;

    /* ========== 轮次控制 ========== */

    /// @notice 当前轮次 ID（从 1 开始；每次 requestData +1）
    uint256 public roundId;

    /// @notice 当前是否存在未完成的数据请求（防止同一时间多轮并发）
    bool public dataRequested;

    /// @notice 当前轮请求发起时间（用于超时控制，防止系统卡死）
    uint256 public requestTimestamp;

    /// @notice 超时时间（默认 30 分钟，可调）
    uint256 public timeoutSeconds = 30 minutes;

    /* ========== 聚合结果 ========== */

    /// @notice 最近一次聚合完成的数值结果（算术平均）
    uint256 public latestAggregated;

    /// @notice 最近一次聚合完成的 bytes32 结果（可选：兼容你之前 bytes32 风格）
    bytes32 public latestDataBytes32;

    /// @notice 最近一次聚合对应的轮次
    uint256 public latestAggregatedRound;

    /* ========== 每轮数据结构 ========== */

    struct RoundSubmission {
        uint256 v1;       // oracle1 提交的值
        uint256 v2;       // oracle2 提交的值
        bool s1;          // oracle1 是否已提交
        bool s2;          // oracle2 是否已提交
        bool finalized;   // 本轮是否已聚合完成
        uint8 count;      // 已提交数量（0/1/2）
    }

    /// @notice roundId => 本轮提交情况
    mapping(uint256 => RoundSubmission) public submissions;

    /* ========== 事件 ========== */

    event Committed(address indexed partyA);
    event OraclesUpdated(address indexed oracle1, address indexed oracle2);
    event TimeoutUpdated(uint256 timeoutSeconds);

    event DataRequested(address indexed partyA, uint256 indexed roundId);
    event OracleSubmitted(address indexed oracle, uint256 indexed roundId, uint256 value);
    event DataAggregated(uint256 indexed roundId, uint256 avgValue);
    event RequestCancelled(uint256 indexed roundId, string reason);

    /* ========== 修饰器 ========== */

    modifier onlyPartyA() {
        require(msg.sender == partyA, "Not PartyA");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle1 || msg.sender == oracle2, "Not whitelisted oracle");
        _;
    }

    /* ========== 构造函数 ========== */

    /// @param _commitment 你原本的承诺值（可选门控）
    /// @param _oracle1 第一个 oracle 地址
    /// @param _oracle2 第二个 oracle 地址
    constructor(bytes32 _commitment, address _oracle1, address _oracle2) {
        require(_oracle1 != address(0) && _oracle2 != address(0), "Oracle is zero");
        require(_oracle1 != _oracle2, "Oracles must differ");

        partyA = msg.sender;
        commitment = _commitment;
        oracle1 = _oracle1;
        oracle2 = _oracle2;

        emit OraclesUpdated(_oracle1, _oracle2);
    }

    /* ========== PartyA 管理接口 ========== */

    /// @notice PartyA 提交一次承诺（如果你想保留 commit-gate）
    function commit() external onlyPartyA {
        require(!committed, "Already committed");
        committed = true;
        emit Committed(msg.sender);
    }

    /// @notice 修改 oracle 地址（工程落地常见：换机器/换 key）
    function setOracles(address _oracle1, address _oracle2) external onlyPartyA {
        require(_oracle1 != address(0) && _oracle2 != address(0), "Oracle is zero");
        require(_oracle1 != _oracle2, "Oracles must differ");

        oracle1 = _oracle1;
        oracle2 = _oracle2;

        emit OraclesUpdated(_oracle1, _oracle2);
    }

    /// @notice 修改超时时间（防卡死）
    function setTimeoutSeconds(uint256 _timeoutSeconds) external onlyPartyA {
        require(_timeoutSeconds >= 60 && _timeoutSeconds <= 7 days, "Timeout out of range");
        timeoutSeconds = _timeoutSeconds;
        emit TimeoutUpdated(_timeoutSeconds);
    }

    /* ========== 请求流程 ========== */

    /// @notice PartyA 发起新一轮数据请求（多轮可重复测试）
    function requestData() external onlyPartyA {
        require(committed, "Commit first");
        require(!dataRequested, "Previous request still active");

        roundId += 1;
        dataRequested = true;
        requestTimestamp = block.timestamp;

        emit DataRequested(partyA, roundId);
    }

    /// @notice Oracle 回写数据（每个 oracle 每轮只能提交一次）
    /// @dev 两个 oracle 都提交后，合约自动聚合（平均值）
    function fulfillData(uint256 value) external onlyOracle {
        require(dataRequested, "No active request");

        RoundSubmission storage r = submissions[roundId];
        require(!r.finalized, "Round already finalized");

        if (msg.sender == oracle1) {
            require(!r.s1, "Oracle1 already submitted");
            r.v1 = value;
            r.s1 = true;
            r.count += 1;
        } else {
            require(!r.s2, "Oracle2 already submitted");
            r.v2 = value;
            r.s2 = true;
            r.count += 1;
        }

        emit OracleSubmitted(msg.sender, roundId, value);

        // 两个 oracle 都提交后，自动聚合
        if (r.count == 2) {
            _finalizeRound(roundId);
        }
    }

    /// @notice 超时取消本轮请求（防止一个 oracle 掉线导致系统永久卡住）
    /// @dev 这里采取“取消并终止本轮”，不对部分数据进行聚合
    function cancelIfTimeout() external {
        require(dataRequested, "No active request");
        require(block.timestamp > requestTimestamp + timeoutSeconds, "Not timed out yet");

        dataRequested = false;

        // 标记为已结束，避免后续再提交
        submissions[roundId].finalized = true;

        emit RequestCancelled(roundId, "timeout");
    }

    /* ========== 内部聚合逻辑 ========== */

    function _finalizeRound(uint256 _rid) internal {
        RoundSubmission storage r = submissions[_rid];
        require(r.count == 2, "Need two submissions");
        require(!r.finalized, "Already finalized");

        // 算术平均：avg = (v1 + v2) / 2
        uint256 avg = (r.v1 + r.v2) / 2;

        latestAggregated = avg;
        latestDataBytes32 = bytes32(avg); // 可选：兼容 bytes32
        latestAggregatedRound = _rid;

        r.finalized = true;
        dataRequested = false;

        emit DataAggregated(_rid, avg);
    }

    /* ========== 查询接口（前端/脚本用） ========== */

    function currentRoundStatus()
        external
        view
        returns (
            uint256 currentRound,
            bool active,
            uint256 ts,
            uint8 count,
            bool oracle1Submitted,
            bool oracle2Submitted,
            bool finalized
        )
    {
        RoundSubmission storage r = submissions[roundId];
        return (
            roundId,
            dataRequested,
            requestTimestamp,
            r.count,
            r.s1,
            r.s2,
            r.finalized
        );
    }
}

