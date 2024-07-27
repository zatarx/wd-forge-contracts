// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error GroupBill__NotParticipant(address sender);
error GroupBill__NotExpenseOwner(address sender);
error GroupBill__HasNotVoted(address sender);
error GroupBill__ParticipantsEmpty();
error GroupBill__NotAllowedToJoin(address sender);
error GroupBill__AddressIsNotTrusted(address sender);

struct Expense {
    address lender; // who funds will be transfered to (msg.sender, aka owner of the expense)
    address borrower; // who funds will be deducted from
    uint256 amount;
}

struct ExpenseBody {
    address borrower;
    uint256 amount;
}

contract GroupBill is Ownable {
    enum GroupBillState {
        OPEN,
        // PRUNING_REQUIRED,
        READY_TO_SETTLE,
        SETTLEMENT_IN_PROGRESS,
        SETTLED
    }

    enum JoinState {
        UKNOWN,
        PENDING,
        JOINED
    }

    GroupBillState private s_state;
    bytes32 private s_expensesHash;
    IERC20 private i_coreToken; // participants can only donate in this token (gets set once)
    address[] private i_trustedEOAs;
    uint private s_expensesCount;
    mapping(uint => Expense) private s_expenses;
    uint private s_prunedExpensesLength;
    mapping(uint => Expense) private s_prunedExpenses;
    address[] private s_participants;
    mapping(address => JoinState) private s_isParticipant;
    mapping(address => bool) private s_hasVoted;

    event ExpensePruningRequested(Expense[] expenses);
    event ExpensePruningSubmitted(Expense[] expenses);

    error GroupBill__DifferentGroupBillStateExpected(
        GroupBillState currentState,
        GroupBillState[] expectedStates
    );

    constructor(
        address initialOwner,
        IERC20 coreToken,
        address[] memory initialParticipants,
        address[] memory trustedEOAs
    ) Ownable(initialOwner) {
        s_state = GroupBillState.OPEN;
        s_expensesCount = 0;
        i_coreToken = IERC20(coreToken);
        i_trustedEOAs = trustedEOAs;
        addParticipants(initialParticipants);
    }

    function addParticipants(address[] memory participants) public onlyOwner {
        if (participants.length == 0) {
            revert GroupBill__ParticipantsEmpty();
        }
        for (uint256 i = 0; i < participants.length; i++) {
            if (s_isParticipant[s_participants[i]] != JoinState.JOINED) {
                s_isParticipant[s_participants[i]] = JoinState.PENDING;
            }
        }
    }

    function join() public returns (JoinState joinState) {
        if (s_isParticipant[msg.sender] != JoinState.PENDING) {
            revert GroupBill__NotAllowedToJoin(msg.sender);
        }
        s_isParticipant[msg.sender] = JoinState.JOINED;
        s_participants.push(msg.sender);
        joinState = s_isParticipant[msg.sender];
    }

    function addExpense(
        ExpenseBody memory newExpense
    ) public isParticipant returns (Expense memory addedExpense) {
        Expense memory expense = Expense(
            msg.sender,
            newExpense.borrower,
            newExpense.amount
        );
        s_expenses[s_expensesCount] = expense;
        s_expensesCount++;
        addedExpense = expense;
    }

    function editExpense(
        uint256 expenseIndex,
        ExpenseBody memory newExpense
    )
        public
        isExpenseLender(expenseIndex)
        returns (Expense memory updatedExpense)
    {
        s_expenses[expenseIndex] = Expense({
            lender: msg.sender,
            borrower: newExpense.borrower,
            amount: newExpense.amount
        });
        updatedExpense = s_expenses[expenseIndex];
    }

    function deleteExpense(
        uint256 expenseIndex
    ) public isExpenseLender(expenseIndex) {
        delete s_expenses[expenseIndex];
    }

    function submitExpensesAfterPruning(
        Expense[] memory prunedExpenses
    ) public onlyTrustedEOAs {
        for (uint i = 0; i < prunedExpenses.length; i++) {
            s_prunedExpenses[i] = prunedExpenses[i];
        }
        s_prunedExpensesLength = prunedExpenses.length;
        emit ExpensePruningSubmitted(prunedExpenses);
    }

    function getAllExpenses() public view returns (Expense[] memory) {
        Expense[] memory currentExpenses = new Expense[](s_expensesCount);
        for (uint i = 0; i < s_expensesCount; i++) {
            currentExpenses[i] = s_expenses[i];
        }
        return currentExpenses;
    }
    
    function requestExpensePruning() public isParticipant {
        bytes32 newExpensesHash = sha256(abi.encode(getAllExpenses()));

        if (
            s_expensesHash != newExpensesHash &&
            s_state == GroupBillState.READY_TO_SETTLE
        ) {
            s_expensesHash = newExpensesHash;
            emit ExpensePruningRequested(getAllExpenses());
            s_state = GroupBillState.SETTLEMENT_IN_PROGRESS;
        }
    }

    function vote() public isParticipant returns (bool _hasVoted) {
        // TODO: when this method is called, the user should allow the contract
        // to operate on N amount of funds on user's behalf (signing process) (*deadline*: for 5 min??)
        // SIGNING MUST TAKE PLACE!!!
        s_hasVoted[msg.sender] = true;
        _hasVoted = s_hasVoted[msg.sender];
        // produce an event
    }

    function recallVote()
        public
        isParticipant
        hasVoted
        returns (bool _hasVoted)
    {
        // TODO: user recalls their signature
        // ext. Is it even possible to revoke the signature??
        // If not, then friendly ux must be considered
        s_hasVoted[msg.sender] = false;
        _hasVoted = s_hasVoted[msg.sender];
        // produce an event
    }

    function settle()
        public
        isParticipant
        returns (address settlementTransaction)
    {
        // all participants have voted -> initiate share destribution
    }

    function getState() public view returns (GroupBillState) {
        return s_state;
    }

    modifier isParticipant() {
        if (s_isParticipant[msg.sender] == JoinState.JOINED) {
            revert GroupBill__NotParticipant(msg.sender);
        }
        _;
    }

    modifier isExpenseLender(uint256 expenseIndex) {
        if (s_expenses[expenseIndex].lender != msg.sender) {
            revert GroupBill__NotExpenseOwner(msg.sender);
        }
        _;
    }

    modifier hasVoted() {
        if (!s_hasVoted[msg.sender]) {
            revert GroupBill__HasNotVoted(msg.sender);
        }
        _;
    }

    modifier onlyTrustedEOAs() {
        bool trusted = false;
        for (uint i = 0; i < i_trustedEOAs.length; i++) {
            if (i_trustedEOAs[i] == msg.sender) {
                _;
                return;
            }
        }
        revert GroupBill__AddressIsNotTrusted(msg.sender);
    }
}
