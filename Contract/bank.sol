// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract HodlBank {
    address admin;
    uint256 public depositCount;
    uint16 public countryCount;

    constructor() {
        admin = msg.sender;
        depositCount = 0;
        countryCount = 0;
    }

    enum Status {
        PENDING,
        LOCKED,
        UNLOCKED_BY_BUDDY,
        DEBITED_BY_ADMIN,
        DEBITED_BY_BUDDY,
        DEBIT_BY_SELF
    }

    struct Deposit {
        uint256 id;
        address depositor;
        uint256 amount;
        bool isWithdrawn;
        uint256 start;
        uint256 end;
        address buddy;
        uint16 countryId;
        Status status;
    }

    // uint256[] allDepositIds;

    // mapping(address => Deposit[]) depositorToDeposits;
    mapping(uint256 => Deposit) idToDeposit;

    mapping(uint16 => string) countryIdToCountry;

    // mapping(address => Deposit[]) buddyToDeposits;
    // mapping(uint256 => address) idToBuddy;

    modifier onlyAdmin() {
        require(msg.sender == admin, "Unautharised");
        _;
    }

    modifier onlyDepositorHavingId(uint256 _id) {
        require(msg.sender == idToDeposit[_id].depositor, "Unautharised");
        _;
    }

    modifier onlyBuddyForDepositId(uint256 _id) {
        require(
            msg.sender == idToDeposit[_id].buddy,
            "Unautharized to unlock deposit. If in an emergency, ask buddy(if assigned) to unlock the deposit."
        );
        _;
    }

    modifier onlyAdminOrInvestor(uint256 _id) {
        require(
            msg.sender == idToDeposit[_id].depositor || msg.sender == admin,
            "Unautharised"
        );
        _;
    }

    modifier notWithdrawn(uint256 _id) {
        require(
            idToDeposit[_id].isWithdrawn == false,
            "Deposit already cashed out."
        );
        _;
    }

    function setCountry(string memory country) public onlyAdmin {
        countryIdToCountry[++countryCount] = country;
    }

    function getCountry(uint16 _countryId) public view returns (string memory) {
        return countryIdToCountry[_countryId];
    }

    function getTime() public view returns (uint256) {
        return block.timestamp;
    }

    function getTimeLeft(uint256 _id) public view returns (uint256) {
        return idToDeposit[_id].end - block.timestamp;
    }

    function getDepositById(uint256 _id)
        public
        view
        onlyAdminOrInvestor(_id)
        returns (Deposit memory)
    {
        return idToDeposit[_id];
    }

    // function getAllDeposits() public view returns(Deposit[] memory) {
    //     return depositorToDeposits[msg.sender];
    // }

    // function getAllDepositsByAdmin(address addr)
    //     public
    //     view
    //     onlyAdmin
    //     returns(Deposit[] memory)
    // {
    //     return depositorToDeposits[addr];
    // }

    receive() external payable {
        require(msg.value > 0, "Deposit should be more than 0 ether.");

        depositCount++;
        Deposit memory deposit = Deposit({
            id: depositCount,
            depositor: msg.sender,
            amount: msg.value,
            isWithdrawn: false,
            start: block.timestamp,
            end: block.timestamp + (600 seconds),
            buddy: address(this),
            countryId: 0,
            status: Status.PENDING
        });

        idToDeposit[depositCount] = deposit;
        // depositorToDeposits[msg.sender].push(deposit);
        // allDepositIds.push(deposit.id);

        // after this is executed, call deposit function
    }

    function makeDeposit(
        uint256 _id,
        uint256 _sec,
        address _buddy,
        uint16 _countryId
    ) public onlyDepositorHavingId(_id) {
        require(
            _sec >= (600 seconds),
            "Deposit should be for minimum of 10 minutes."
        );
        require(_countryId <= countryCount, "Invalid Country.");
        require(
            _buddy != msg.sender,
            "You can't assign yourself as buddy for the deposit."
        );

        Deposit storage deposit = idToDeposit[_id];
        deposit.end += (_sec * 1 seconds) - (600 seconds);
        deposit.buddy = _buddy;
        deposit.countryId = _countryId;
        deposit.status = Status.LOCKED;

        // if this fails, then show an alert saying
        // "Seems like some error occured, you can withdraw your deposit after 10 mins of deposit time."
    }

    function makeWithdraw(uint256 _id)
        public
        notWithdrawn(_id)
        onlyDepositorHavingId(_id)
    {
        require(
            block.timestamp >= idToDeposit[_id].end,
            "Cannot withdraw deposit right now. If in an emergency, ask buddy(if assigned) to unlock the deposit."
        );

        Deposit storage deposit = idToDeposit[_id];
        payable(deposit.depositor).transfer(deposit.amount);

        deposit.isWithdrawn = true;
        deposit.status = Status.DEBIT_BY_SELF;
    }

    function unlockFund(uint256 _id)
        public
        notWithdrawn(_id)
        onlyBuddyForDepositId(_id)
    {
        Deposit storage deposit = idToDeposit[_id];

        deposit.end = block.timestamp;
        deposit.status = Status.UNLOCKED_BY_BUDDY;
    }

    function unlockFundAndDebit(uint256 _id)
        public
        notWithdrawn(_id)
        onlyBuddyForDepositId(_id)
    {
        Deposit storage deposit = idToDeposit[_id];

        payable(deposit.depositor).transfer(deposit.amount);

        deposit.isWithdrawn = true;
        deposit.end = block.timestamp;
        deposit.status = Status.DEBITED_BY_BUDDY;
    }

    function unlockByAdminAndDebit(Deposit storage deposit) internal onlyAdmin {
        payable(deposit.depositor).transfer(deposit.amount);

        deposit.isWithdrawn = true;
        deposit.status = Status.DEBITED_BY_ADMIN;
    }

    function unlockByCountryId(uint16 _countryId) public onlyAdmin {
        for (uint256 i = 1; i <= depositCount; i++) {
            if (
                idToDeposit[i].countryId == _countryId &&
                idToDeposit[i].isWithdrawn == false
            ) {
                unlockByAdminAndDebit(idToDeposit[i]);
            }
        }
    }

    function extendTenure(
        uint256 _id,
        uint256 _sec,
        bool baseNow
    ) public notWithdrawn(_id) {
        require(
            idToDeposit[_id].status != Status.PENDING,
            "Processing deposit. Please Wait."
        );

        Deposit storage deposit = idToDeposit[_id];

        if (baseNow) {
            require(
                _sec > deposit.end - block.timestamp,
                "Cannot reduce the deposit tenure. Choose longer time."
            );

            deposit.end = block.timestamp + (_sec * 1 seconds);
        } else {
            deposit.end += (_sec * 1 seconds);
        }
    }
}
