// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title PartyA_OCR（把 Chainlink OCR 的“线下聚合机制规则”建模到合约里）
/// @notice 流程：PartyA 发起 round -> 多个 oracle 提交 observation -> 合约计算 report（median）
///         -> oracle 对 report 进行 confirm（认可）-> 达到 K-of-N 阈值后 finalize 落地
/// @dev 这是“机制建模版”：不做真正 P2P 共识，只把 OCR 的 report+quorum 规则写进合约
contract PartyA_OCR {
    /* ========== 角色与配置 ========== */

    /// @notice PartyA 管理员（部署者）
    address public immutable partyA;

    /// @notice oracle 白名单
    mapping(address => bool) public isOracle;

    /// @notice oracle 总数（建议 3 或 5）
    uint256 public oracleCount;

    /// @notice 阈值 K（至少多少个 oracle confirm 才 finalize）
    uint256 public thresholdK;

    /// @notice 超时（防卡死）
    uint256 public timeoutSeconds = 30 minutes;

    /* ========== 轮次与状态 ========== */

    uint256 public roundId;        // 从 1 开始递增
    bool public dataRequested;     // 是否存在活跃 round（避免并发）
    uint256 public requestTimestamp;

    /// @notice 最新落地结果
    uint256 public latestValue;
    uint256 public latestRound;

    /* ========== 每轮数据结构 ========== */

    struct RoundData {
        bool reportReady;      // report 是否已生成
        bool finalized;        // 是否已 finalize
        uint256 obsCount;      // observation 数量
        uint256 confirmCount;  // confirm 数量
        uint256 reportValue;   // 本轮 report（median）
        uint256[] obsValues;   // 仅用于计算 median（把所有 observation 收齐）
        mapping(address => bool) obsSubmitted; // 该 oracle 是否已提交 observation
        mapping(address => bool) confirmed;    // 该 oracle 是否已确认 report
    }

    mapping(uint256 => RoundData) private rounds;

    /* ========== 事件（链下监控/触发用） ========== */

    event OraclesConfigured(uint256 oracleCount, uint256 thresholdK);
    event TimeoutUpdated(uint256 timeoutSeconds);

    event DataRequested(uint256 indexed roundId);
    event ObservationSubmitted(address indexed oracle, uint256 indexed roundId, uint256 value);

    event ReportComputed(uint256 indexed roundId, uint256 reportValue);
    event ReportConfirmed(address indexed oracle, uint256 indexed roundId);
    event Finalized(uint256 indexed roundId, uint256 value);

    event RequestCancelled(uint256 indexed roundId, string reason);

    /* ========== 修饰器 ========== */

    modifier onlyPartyA() {
        require(msg.sender == partyA, "Not PartyA");
        _;
    }

    modifier onlyOracle() {
        require(isOracle[msg.sender], "Not whitelisted oracle");
        _;
    }

    /* ========== 构造函数 ========== */

    /// @param oracles oracle 地址列表（建议奇数：3/5）
    /// @param _thresholdK confirm 阈值（K-of-N）
    constructor(address[] memory oracles, uint256 _thresholdK) {
        require(oracles.length >= 3, "Need >=3 oracles");
        require(oracles.length % 2 == 1, "Oracle count must be odd");
        require(_thresholdK >= 1 && _thresholdK <= oracles.length, "Bad threshold");

        partyA = msg.sender;

        for (uint256 i = 0; i < oracles.length; i++) {
            address o = oracles[i];
            require(o != address(0), "Zero oracle");
            require(!isOracle[o], "Duplicate oracle");
            isOracle[o] = true;
        }
        oracleCount = oracles.length;
        thresholdK = _thresholdK;

        emit OraclesConfigured(oracleCount, thresholdK);
    }

    /* ========== 管理接口 ========== */

    function setTimeoutSeconds(uint256 _timeoutSeconds) external onlyPartyA {
        require(_timeoutSeconds >= 60 && _timeoutSeconds <= 7 days, "Timeout out of range");
        timeoutSeconds = _timeoutSeconds;
        emit TimeoutUpdated(_timeoutSeconds);
    }

    /* ========== 轮次流程 ========== */

    function requestData() external onlyPartyA {
        require(!dataRequested, "Previous round active");

        roundId += 1;
        dataRequested = true;
        requestTimestamp = block.timestamp;

        emit DataRequested(roundId);
    }

    /// @notice oracle 提交 observation（各自独立拉到的数据）
    function submitObservation(uint256 value) external onlyOracle {
        require(dataRequested, "No active request");

        RoundData storage r = rounds[roundId];
        require(!r.finalized, "Round finalized");
        require(!r.obsSubmitted[msg.sender], "Observation already submitted");

        r.obsSubmitted[msg.sender] = true;
        r.obsCount += 1;
        r.obsValues.push(value);

        emit ObservationSubmitted(msg.sender, roundId, value);

        // 收齐 N 个 observation 后，自动计算 report（median）
        if (r.obsCount == oracleCount && !r.reportReady) {
            uint256 med = _median(r.obsValues);
            r.reportValue = med;
            r.reportReady = true;
            emit ReportComputed(roundId, med);
        }
    }

    /// @notice oracle 确认（认可）本轮 report
    function confirmReport() external onlyOracle {
        require(dataRequested, "No active request");

        RoundData storage r = rounds[roundId];
        require(r.reportReady, "Report not ready");
        require(!r.finalized, "Round finalized");
        require(!r.confirmed[msg.sender], "Already confirmed");

        r.confirmed[msg.sender] = true;
        r.confirmCount += 1;

        emit ReportConfirmed(msg.sender, roundId);

        if (r.confirmCount >= thresholdK) {
            _finalize(roundId);
        }
    }

    function cancelIfTimeout() external {
        require(dataRequested, "No active request");
        require(block.timestamp > requestTimestamp + timeoutSeconds, "Not timed out yet");

        dataRequested = false;
        RoundData storage r = rounds[roundId];
        r.finalized = true;

        emit RequestCancelled(roundId, "timeout");
    }

    /* ========== 内部逻辑 ========== */

    function _finalize(uint256 _rid) internal {
        RoundData storage r = rounds[_rid];
        require(r.reportReady, "Report not ready");
        require(!r.finalized, "Already finalized");
        require(r.confirmCount >= thresholdK, "Quorum not reached");

        r.finalized = true;
        dataRequested = false;

        latestValue = r.reportValue;
        latestRound = _rid;

        emit Finalized(_rid, r.reportValue);
    }

    function _median(uint256[] storage valuesStorage) internal view returns (uint256) {
        uint256 n = valuesStorage.length;
        require(n == oracleCount, "Need full observations");

        uint256[] memory a = new uint256[](n);
        for (uint256 i = 0; i < n; i++) a[i] = valuesStorage[i];

        // 插入排序（N 很小，足够）
        for (uint256 i = 1; i < n; i++) {
            uint256 key = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > key) {
                a[j] = a[j - 1];
                j--;
            }
            a[j] = key;
        }

        return a[n / 2];
    }

    /* ========== 查询接口（调试/前端用） ========== */

    function getRoundStatus(uint256 _rid)
        external
        view
        returns (
            bool active,
            bool reportReady,
            bool finalized,
            uint256 obsCount,
            uint256 confirmCount,
            uint256 reportValue
        )
    {
        RoundData storage r = rounds[_rid];
        bool isActive = (dataRequested && _rid == roundId);
        return (isActive, r.reportReady, r.finalized, r.obsCount, r.confirmCount, r.reportValue);
    }

    function hasSubmittedObservation(uint256 _rid, address oracle) external view returns (bool) {
        return rounds[_rid].obsSubmitted[oracle];
    }

    function hasConfirmedReport(uint256 _rid, address oracle) external view returns (bool) {
        return rounds[_rid].confirmed[oracle];
    }
}
