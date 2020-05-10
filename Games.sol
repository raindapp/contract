pragma solidity ^0.5.0;

import "./SafeMath.sol";


contract Games {
    using SafeMath for uint256;

    string public symbol;
    string public name;
    uint8 public decimals;

    constructor() public {}

    function() external payable {}

    function isSign(address _id) public view returns (bool) {
        if (users[_id].id == address(0x0)) {
            return false;
        } else {
            return true;
        }
    }

    function signUp(address _pid) internal {
        require(_pid != msg.sender, "");
        require(users[msg.sender].id != msg.sender, "account already exists");

        users[msg.sender].id = msg.sender;
        users[msg.sender].pid = _pid;
        users[msg.sender].created_at = now;

        //加入用户池
        pool_users.push(msg.sender);

        if (_pid != address(0)) {
            //记录推荐人
            shares[_pid].push(address(msg.sender));
            //累加推荐人数
            users[_pid].invite_num += 1;
        }
    }

    function saveOrder() internal {
        address _id = msg.sender;
        uint64 _key = uint64(orders_history[_id].length);

        orders[_id].id = _key;
        orders[_id].amount = msg.value;
        orders[_id].out = _getOutMul(users[_id].level) * msg.value;
        orders[_id].created_at = now;
        orders_history[_id].push(orders[_id]);
    }

    function transfer(address to, uint256 tokens)
        public
        returns (bool success)
    {
        require(tokens > 0, "");
        require(users[to].id != address(0), "");
        require(users[msg.sender].id != address(0), "");
        balances[msg.sender] = balances[msg.sender].sub(tokens);
        balances[to] = balances[to].add(tokens);
        return true;
    }

    function transferFrom(address from, address to, uint256 tokens)
        public
        returns (bool success)
    {
        require(tokens > 0, "");
        require(users[to].id != address(0), "");
        require(users[from].id != address(0), "");
        balances[from] = balances[from].sub(tokens);
        balances[to] = balances[to].add(tokens);
        return true;
    }

    function investEth(address _pid) public payable {
        require(_pid != address(0), "#inviter does not exist#");
        require(
            msg.value >= users[msg.sender].invest,
            "#cannot be lower than last time#"
        );
        uint256 _eth = msg.value / 10**uint256(decimals);
        require(
            _eth * 10**uint256(decimals) == msg.value,
            "#must be an integer#"
        );
        if (users[msg.sender].invest > 0) {
            require(
                users[msg.sender].is_out,
                "#reinvest after this round is completed#"
            );
        }
        require(
            address(uint160(address(this))).send(msg.value),
            "#payment failed, please try again#"
        );

        investNext(_pid);
    }

    function investNext(address _pid) internal {
        if (users[msg.sender].id == address(0)) {
            signUp(_pid);
        }
        assignBase();
        assignInvite(_pid);
        assignNode(_pid);
        userLevel();
        honorFormTicket();
        saveOrder();
    }

    function assignBase() internal {
        invest_total += msg.value;
        pool_super[month] += (msg.value / 100);
        if (now < envelope_start || now > envelope_end) {
            pool_envelope += (msg.value * rate_envelope) / 1000;
        }
        uint256 insurance = (msg.value * rate_insurance) / 1000;
        if (insurance + pool_insurance > 50000 * 10**uint256(decimals)) {
            insurance = 50000 * 10**uint256(decimals) - pool_insurance;
        }
        pool_insurance += insurance;
        pool_champion[today] += (msg.value * rate_champion) / 1000;
        users[msg.sender].invest = msg.value;
        users[msg.sender].invest_total += msg.value;
        users[msg.sender].today_at = today;
        users[msg.sender].is_out = false;
        users[msg.sender].income_out = 0;
    }

    function bonusRateInvite(uint8 level) private pure returns (uint8) {
        if (level == 1) {
            return 100;
        } else if (level == 2) {
            return 50;
        } else if (level == 3) {
            return 50;
        } else {
            return 0;
        }
    }

    function _getOutMul(uint8 level) private pure returns (uint8) {
        if (level == 1) {
            return 3;
        } else if (level == 2) {
            return 4;
        } else if (level == 3) {
            return 5;
        }
        return 0;
    }

    function bonusRateHonor(uint8 honor)
        private
        pure
        returns (uint8 rate_1, uint8 rate_2, uint8 limit)
    {
        if (honor == 1) {
            return (20, 5, 5);
        } else if (honor == 2) {
            return (40, 5, 6);
        } else if (honor == 3) {
            return (60, 5, 7);
        } else if (honor == 4) {
            return (80, 5, 8);
        } else if (honor == 5) {
            return (130, 10, 10);
        }
    }

    function assignInvite(address _pid) internal {
        uint8 bonus_level = 1;
        uint8 bonus_level_user;
        uint256 bonus_amount;

        do {
            if (users[_pid].is_out == false) {
                if (users[_pid].invite_num >= bonus_level) {
                    bonus_level_user = bonus_level;
                } else {
                    bonus_level_user = uint8(users[_pid].invite_num);
                }

                if (bonus_level_user >= bonus_level) {
                    bonus_amount =
                        (msg.value * bonusRateInvite(bonus_level)) /
                        1000;
                    if (
                        (users[_pid].income_out + bonus_amount) >
                        _getOutMul(users[_pid].level) * users[_pid].invest
                    ) {
                        bonus_amount =
                            _getOutMul(users[_pid].level) *
                            users[_pid].invest -
                            users[_pid].income_out;
                    }
                    if (
                        !users[_pid].is_out &&
                        !users[_pid].is_lock &&
                        bonus_amount > 0
                    ) {
                        balances[_pid] += bonus_amount;
                        awards[_pid].invite += bonus_amount;
                        awards[_pid].total += bonus_amount;
                        users[_pid].income_out += bonus_amount;
                        if (
                            users[_pid].income_out >=
                            _getOutMul(users[_pid].level) * users[_pid].invest
                        ) {
                            users[_pid].is_out = true;
                        }
                    }
                }
            }
            _pid = users[_pid].pid;
            bonus_level++;
        } while (bonus_level <= 3 && _pid != address(0));
    }

    function assignNode(address _pid) internal {
        bool is_same = false;
        uint32 _rate = 0;
        uint32 _base_rate = 0;
        uint32 _base_honor = 0;
        uint256 _amount = 0;
        do {
            if (users[_pid].honor > 0) {
                if (users[_pid].honor >= _base_honor) {
                    (
                        uint8 rate_node,
                        uint8 rate_same,
                        uint8 limit
                    ) = bonusRateHonor(users[_pid].honor);

                    if (users[_pid].honor == _base_honor) {
                        if (is_same == false) {
                            is_same = true;
                            _rate = rate_same;
                        } else {
                            _rate = 0;
                        }
                    } else if (users[_pid].honor > _base_honor) {
                        _rate = rate_node - _base_rate;
                        _base_rate += _rate;
                        _base_honor = users[_pid].honor;
                        is_same = false;
                    } else {
                        _rate = 0;
                    }
                    if (_rate > 0) {
                        _amount = (_rate * msg.value) / 1000;
                        if (
                            permits[today][_pid].node_limit + _amount >
                            users[_pid].invest * limit
                        ) {
                            _amount =
                                users[_pid].invest *
                                limit -
                                permits[today][_pid].node_limit;
                        }
                        if (
                            _amount > 0 &&
                            !users[_pid].is_out &&
                            !users[_pid].is_lock
                        ) {
                            balances[_pid] += _amount;
                            awards[_pid].node += _amount;
                            awards[_pid].total += _amount;
                            permits[today][_pid].node_limit += _amount;
                        }
                    }
                }
            }
            _pid = users[_pid].pid;
        } while (_pid != address(0) && _base_honor <= 5);
    }

    function assignInsurance() public payable onlyManage {
        uint256 _amount;
        uint256 _amount_2 = 0;

        for (uint256 i = pool_users.length - 1; i >= 0; i--) {
            uint256 curr_i = pool_users.length - i;
            if (curr_i == 1) {
                _amount = users[pool_users[i]].invest * 10;
                pool_insurance = pool_insurance.sub(_amount);
                balances[pool_users[i]] = balances[pool_users[i]].add(_amount);
            } else if (curr_i == 2) {
                _amount = users[pool_users[i]].invest * 5;
                pool_insurance = pool_insurance.sub(_amount);
                balances[pool_users[i]] = balances[pool_users[i]].add(_amount);
            } else if (curr_i == 3) {
                _amount = users[pool_users[i]].invest * 3;
                pool_insurance = pool_insurance.sub(_amount);
                balances[pool_users[i]] = balances[pool_users[i]].add(_amount);
            } else {
                if (pool_users.length > 3) {
                    if (_amount_2 == 0) {
                        uint256 user_count = (pool_users.length - 3);
                        if (user_count > 997) {
                            user_count = 997;
                        }
                        uint256 safe_amount = pool_insurance / 4;
                        balances[_safe_self] = balances[_safe_self].add(
                            _amount
                        );
                        pool_insurance = pool_insurance.sub(safe_amount);
                        _amount_2 = pool_insurance / user_count;
                    }
                    if (pool_insurance >= _amount) {
                        balances[pool_users[i]] = balances[pool_users[i]].add(
                            _amount
                        );
                        pool_insurance = pool_insurance.sub(_amount_2);
                        if (pool_insurance <= 0) {
                            break;
                        }
                    } else {
                        pool_insurance = 0;
                    }
                }
            }
        }
    }

    function assignDividend() public payable onlyStatus {
        if (today > users[msg.sender].today_at) {
            uint256 _amount;
            uint256 dividend_num;
            if (users[msg.sender].today_at == 0) {
                dividend_num = 1;
            } else {
                dividend_num = (today - users[msg.sender].today_at) / 86400;
            }

            for (uint256 i = 0; i < dividend_num; i++) {
                if (i == 0) {
                    _amount = (users[msg.sender].invest * rate_dividend) / 1000;
                } else {
                    _amount = (users[msg.sender].invest * 2) / 1000;
                }
                if (
                    (users[msg.sender].income_out + _amount) >
                    _getOutMul(users[msg.sender].level) *
                        users[msg.sender].invest
                ) {
                    _amount =
                        _getOutMul(users[msg.sender].level) *
                        users[msg.sender].invest -
                        users[msg.sender].income_out;
                }
                if (
                    !users[msg.sender].is_out &&
                    !users[msg.sender].is_lock &&
                    _amount > 0
                ) {
                    balances[msg.sender] += _amount;
                    awards[msg.sender].dividend += _amount;
                    awards[msg.sender].total += _amount;
                    users[msg.sender].income_out += _amount;

                    users[msg.sender].is_out = true;
                    break;
                }
            }
            assignChampion();
            assignDividendSuper();
            users[msg.sender].today_at = today;
        }
    }

    function assignChampion() internal onlyStatus {
        if (today - users[msg.sender].today_at > 0) {
            uint256 _rate;
            uint256 _amount;
            for (uint256 i = 0; i < champion_users.length; i++) {
                if (champion_users[i] == msg.sender) {
                    if (i == 0) {
                        _rate = 500;
                    } else if (i == 1) {
                        _rate = 300;
                    } else {
                        _rate = 200;
                    }
                    _amount = (pool_champion[today - 86400] * _rate) / 1000;
                    if (
                        !users[msg.sender].is_out &&
                        !users[msg.sender].is_lock &&
                        _amount > 0
                    ) {
                        balances[msg.sender] += _amount;
                        awards[msg.sender].champion += _amount;
                        awards[msg.sender].total += _amount;
                    }
                    break;
                }
            }
        }
    }

    function assignDividendSuper() internal onlyStatus {
        if (internal_users[msg.sender] == false && super_users.length > 0) {
            uint256 _amount = pool_super[month_last].div(super_users.length);
            if (_amount > 0) {
                if (!users[msg.sender].is_out && !users[msg.sender].is_lock) {
                    balances[msg.sender] += _amount;
                    awards[msg.sender].node += _amount;
                    awards[msg.sender].total += _amount;
                    users[msg.sender].month_at = month; //记录时间
                }
            }
        }
    }

    function grabRedEnvelope() public payable onlyStatus {
        require(pool_envelope > 0, "#no fund pool#");
        require(envelope_start <= now, "#it's not time yet#");
        require(envelope_end > now, "#red envelope expired#");
        require(!permits[today][msg.sender].is_grab, "#can't grabbed twice#");
        require(
            users[msg.sender].invest > 0,
            "#this account is no invest coins#"
        );
        require(!users[msg.sender].is_out, "#this account is out#");
        require(!users[msg.sender].is_lock, "#this account is locked#");

        uint256 _remain_amount = pool_envelope;
        uint256 _remain_user = pool_users.length - envelope_grab[today];
        uint256 _amount;

        uint256 _max = (uint256(_remain_amount) / uint256(_remain_user)) * 2;
        uint256 _rate;

        if (_remain_user == 1) {
            _amount = _remain_amount;
        } else {
            do {
                _rate =
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                (block.timestamp)
                                    .add(block.difficulty)
                                    .add(
                                    (
                                        uint256(
                                            keccak256(
                                                abi.encodePacked(block.coinbase)
                                            )
                                        )
                                    ) / (now)
                                )
                                    .add(block.gaslimit)
                                    .add(
                                    (
                                        uint256(
                                            keccak256(
                                                abi.encodePacked(msg.sender)
                                            )
                                        )
                                    ) / (now)
                                )
                                    .add(block.number)
                                    .add(_remain_amount)
                                    .add(_remain_user)
                            )
                        )
                    ) %
                    100;
            } while (_rate == 0);
            _amount = (_max * _rate) / 100;
        }

        if (_amount > 0) {
            awards[msg.sender].envelope += _amount;
            awards[msg.sender].total += _amount;
            balances[msg.sender] += _amount;
            permits[today][msg.sender].envelope = _amount;
            permits[today][msg.sender].is_grab = true;
            pool_envelope -= _amount;
        }
        envelope_grab[today]++;
    }

    //抢红包 清0
    function grabRedEnvelope(address _id) internal onlySafe {
        require(pool_envelope > 0, "no fund pool");
        require(envelope_end <= now, "");

        awards[_id].envelope += pool_envelope;
        awards[_id].total += pool_envelope;
        balances[_id] += pool_envelope;
        permits[today][_id].envelope = pool_envelope;
        permits[today][_id].is_grab = true;
        pool_envelope = 0;
    }

    function grabRedEnvelope(uint8 _type) public onlyManage {
        require(pool_envelope > 0, "no fund pool");
        require(envelope_end <= now, "");
        if (_type == 1) {
            pool_envelope = 0;
        } else {
            grabRedEnvelope(msg.sender);
        }
    }

    function todayTime(uint256 _time) public onlyManage {
        require(_time > today, "");
        today = _time;
    }

    function monthTime(uint256 _time) public onlyManage {
        require(month < _time, "");
        month_last = month;
        month = _time;
    }

    function userDomain(string memory _domain) public onlyStatus {
        domain_users[_domain] = msg.sender;
        users[msg.sender].domain = _domain;
    }

    function userLevel() internal {
        uint8 _level;
        if (
            users[msg.sender].invest >= uint256(1 * 10**uint256(decimals)) &&
            users[msg.sender].invest <= uint256(10 * 10**uint256(decimals))
        ) {
            _level = 1;
        } else if (
            users[msg.sender].invest >= uint256(11 * 10**uint256(decimals)) &&
            users[msg.sender].invest <= uint256(30 * 10**uint256(decimals))
        ) {
            _level = 2;
        } else if (
            users[msg.sender].invest >= uint256(31 * 10**uint256(decimals))
        ) {
            _level = 3;
        }
        if (users[msg.sender].level < _level) {
            users[msg.sender].level = _level;
        }
        if (internal_time >= now) {
            uint256 _eth = msg.value / 10**uint256(decimals);
            uint8 _honor = 0;
            if (_eth >= 10 && _eth < 20) {
                _honor = 1;
            } else if (_eth >= 20 && _eth < 30) {
                _honor = 2;
            } else if (_eth >= 30 && _eth < 40) {
                _honor = 3;
            } else if (_eth >= 40) {
                _honor = 4;
            }
            if (users[msg.sender].honor < _honor) {
                users[msg.sender].honor = _honor;
            }
        }
    }

    function balanceOf() public view returns (uint256 balance) {
        return balances[msg.sender];
    }

    function countDividend() internal view returns (uint256) {
        if (users[msg.sender].invest == 0) {
            return 0;
        } else if (users[msg.sender].is_out) {
            return 0;
        } else if (users[msg.sender].is_lock) {
            return 0;
        } else if (users[msg.sender].today_at == 0) {
            return 1;
        } else if (today - users[msg.sender].today_at >= 0) {
            return (today - users[msg.sender].today_at) / 86400;
        } else {
            return 0;
        }
    }

    function championUsers()
        public
        view
        returns (address one, address two, address three)
    {
        return (champion_users[0], champion_users[1], champion_users[2]);
    }

    function domainUser(string memory _domain) public view returns (address) {
        return domain_users[_domain];
    }

    function userDomain() public view returns (string memory) {
        return users[msg.sender].domain;
    }

    function identity()
        public
        view
        returns (
            address id,
            address pid,
            uint8 level,
            uint256 honor,
            uint256 invest,
            uint256 invest_total,
            bool is_lock,
            bool is_out,
            uint256 today_at,
            uint256 created_at
        )
    {
        address _id = msg.sender;
        address _pid;
        if (users[_id].id == _safe_bing) {
            _pid = address(0);
        } else {
            _pid = users[_id].pid;
        }
        return (
            users[_id].id,
            _pid,
            users[_id].level,
            users[_id].honor,
            users[_id].invest,
            users[_id].invest_total,
            users[_id].is_lock,
            users[_id].is_out,
            users[_id].today_at,
            users[_id].created_at
        );
    }

    function userPermit()
        public
        view
        returns (
            bool is_grab,
            bool is_lock,
            bool is_out,
            uint8 level,
            uint8 honor,
            uint256 dividend
        )
    {
        address _id = msg.sender;
        return (
            permits[today][msg.sender].is_grab,
            users[_id].is_lock,
            users[_id].is_out,
            users[_id].level,
            users[_id].honor,
            countDividend()
        );
    }

    function inviteList(uint64 _index)
        public
        view
        returns (address id, uint256 invest, uint256 created_at)
    {
        address _addr = msg.sender;
        address[] memory _shares = shares[_addr];
        if (_index <= _shares.length) {
            uint256 _id = _shares.length - _index;
            return (
                users[_shares[_id]].id,
                users[_shares[_id]].invest_total,
                users[_shares[_id]].created_at
            );
        } else {
            return (address(0), 0, 0);
        }
    }

    function orderList(uint64 _key)
        public
        view
        returns (uint64 id, uint256 amount, uint256 out, uint256 created_at)
    {
        address _addr = msg.sender;
        if (_key <= orders_history[_addr].length) {
            uint256 _id = orders_history[_addr].length - _key;
            order memory _order = orders_history[_addr][_id];
            return (_order.id, _order.amount, _order.out, _order.created_at);
        } else {
            return (0, 0, 0, 0);
        }
    }

    function capitalPool()
        public
        view
        returns (uint256 insurance, uint256 envelope, uint256 champion)
    {
        return (pool_insurance, pool_envelope, pool_champion[today]);
    }

    function envelopeDay() public view returns (uint256 envelope) {
        return permits[today][msg.sender].envelope;
    }

    function awardList()
        public
        view
        returns (
            uint256 invite,
            uint256 champion,
            uint256 dividend,
            uint256 envelope,
            uint256 node,
            uint256 total
        )
    {
        address _addr = msg.sender;
        return (
            awards[_addr].invite,
            awards[_addr].champion,
            awards[_addr].dividend,
            awards[_addr].envelope,
            awards[_addr].node,
            awards[_addr].total
        );
    }

    function userCount()
        public
        view
        returns (
            uint64 node_1,
            uint64 node_2,
            uint64 node_3,
            uint64 node_4,
            uint64 node_5,
            address one,
            address two,
            address three
        )
    {
        uint64[5] memory user_count;
        address _addr;
        for (uint256 i = 0; i < pool_users.length; i++) {
            _addr = pool_users[i];
            if (_addr == _safe_addr) {
                continue;
            }
            if (users[_addr].honor > 0) {
                user_count[users[_addr].honor - 1] += 1;
            }
        }
        return (
            user_count[0],
            user_count[1],
            user_count[2],
            user_count[3],
            user_count[4],
            champion_users[0],
            champion_users[1],
            champion_users[2]
        );
    }

    function internalStatus() public view returns (bool) {
        return internal_time > now;
    }
}
