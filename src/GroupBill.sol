// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Expenses} from "./Expenses.sol";

error GroupBill__NotParticipant(address sender);
error GroupBill__NotExpenseOwner(address sender);
error GroupBill__HasNotVoted(address sender);
error GroupBill__ParticipantsEmpty();
error GroupBill__NotAllowedToJoin(address sender);

contract GroupBill is Ownable {
    enum GroupBillState {
        OPEN,
        SIMPLIFICATION_REQUIRED,
        READY_TO_SETTLE,
        SETTLED
    }

    enum JoinState {
        UKNOWN,
        PENDING,
        JOINED
    }

    mapping(address => Expenses.DestinationNode[]) private s_graph;
    GroupBillState private s_state;
    IERC20 private i_coreToken; // participants can only donate in this token (gets set once)
    Expenses.Expense[] private s_expenses;
    address[] private participants;
    mapping(address => JoinState) private s_isParticipant;
    mapping(address => bool) private s_hasVoted;

    constructor(address initialOwner, address coreToken, address[] memory initialParticipants) Ownable(initialOwner) {
        s_state = GroupBillState.OPEN;
        s_expenses = new Expenses.Expense[](0);
        i_coreToken = IERC20(coreToken);
        addParticipants(initialParticipants);
    }

    function addParticipants(address[] memory participants) public onlyOwner {
        if (!participants.length) {
            revert GroupBill__ParticipantsEmpty();
        }
        for (uint256 i = 0; i < participants.length; i++) {
            if (s_isParticipant[participants[i]] != JoinState.JOINED) {
                s_isParticipant[participants[i]] = JoinState.PENDING;
            }
        }
    }

    function join() public returns (JoinState joinState) {
        if (s_isParticipant[msg.sender] != JoinState.PENDING) {
            revert GroupBill__NotAllowedToJoin(msg.sender);
        }
        s_isParticipant[msg.sender] = JoinState.JOINED;
        participants.push(msg.sender);
        joinState = s_isParticipant[msg.sender];
    }

    function triggerGraphCalculations() public {
        Expenses.simplify(s_graph, s_expenses); // empty mapping and all expenses passed by reference
        // calculations
    }

    function addExpense(Expenses.ExpenseBody memory newExpense)
        public
        isParticipant
        returns (Expenses.Expense memory addedExpense)
    {
        Expenses.Expense memory expense =
            Expenses.Expense(msg.sender, newExpense.borrower, newExpense.amount);
        s_expenses.push(expense);
        addedExpense = s_expenses[s_expenses.length - 1];

        s_state = GroupBillState.SIMPLIFICATION_REQUIRED;
    }

    function editExpense(uint256 expenseIndex, Expenses.ExpenseBody memory newExpense)
        public
        isExpenseLender(expenseIndex)
        returns (Expenses.Expense memory updatedExpense)
    {
        s_expenses[expenseIndex] = Expenses.Expense({
            lender: msg.sender,
            borrower: newExpense.borrower,
            amount: newExpense.amount
        });
        updatedExpense = s_expenses[expenseIndex];
        s_state = GroupBillState.SIMPLIFICATION_REQUIRED;
    }

    function deleteExpense(uint256 expenseIndex) public isExpenseLender(expenseIndex) {
        delete s_expenses[expenseIndex];
        s_state = GroupBillState.SIMPLIFICATION_REQUIRED;
    }

    function vote() public isParticipant returns (bool _hasVoted) {
        // TODO: when this method is called, the user should allow the contract
        // to operate on N amount of funds on user's behalf (signing process) (*deadline*: for 5 min??)
        // SIGNING MUST TAKE PLACE!!!
        s_hasVoted[msg.sender] = true;
        _hasVoted = s_hasVoted[msg.sender];
        // produce an event
    }

    function recallVote() public isParticipant hasVoted returns (bool _hasVoted) {
        // TODO: user recalls their signature 
        // ext. Is it even possible to revoke the signature??
        // If not, then friendly ux must be considered
        s_hasVoted[msg.sender] = false;
        _hasVoted = s_hasVoted[msg.sender];
        // produce an event
    }

    function settle() public isParticipant returns (address settlementTransaction) {
        // all participants have voted
        // TRIGGER GRAPH COMPUTATION
        // Oracles to get the prices???
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
}
