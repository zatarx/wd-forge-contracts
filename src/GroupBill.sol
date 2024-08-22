// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {SigUtils} from "./SigUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPermit2} from "./Utils.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

error GroupBill__NotParticipant(address sender);
error GroupBill__NotExpenseOwner(address sender);
error GroupBill__HasNotVoted(address sender);
error GroupBill__ParticipantsEmpty();
error GroupBill__NotAllowedToJoin(address sender);
error GroupBill__AddressIsNotTrusted(address sender);
error GroupBill__InvalidToken(address token);

struct Expense {
    address lender; // who funds will be transfered to (msg.sender, aka owner of the expense)
    address borrower; // who funds will be deducted from
    uint256 amount;
}

contract GroupBill is Ownable {
    enum GroupBillState {
        OPEN,
        PRUNING_IN_PROGRESS,
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
    IPermit2 private i_permit2;
    string private s_name;
    bytes32 private s_expensesHash;
    IERC20 private immutable i_coreToken; // participants can only donate in this token (gets set once)
    address private immutable i_consumerEOA;
    uint private s_expensesCount;
    mapping(uint => Expense) private s_expenses;
    uint private s_prunedExpensesLength;
    mapping(uint => Expense) private s_prunedExpenses;
    address[] private s_participants;
    mapping(address => JoinState) private s_isParticipant;
    mapping(address => bool) private s_hasVoted;

    event ExpensePruningRequested(bytes32 indexed expensesHash);
    event ExpensePruningResultSubmitted(bytes32 indexed expensesHash);
    event ExpenseSettlementCompleted();

    error GroupBill__DifferentGroupBillStateExpected(
        GroupBillState currentState,
        GroupBillState[] expectedStates
    );
    error GroupBill__ExpensesHashMismatch(
        bytes32 currentExpensesHash,
        bytes32 expenseHash
    );
    error GroupBill__StateActionForbidden(GroupBillState state, address sender);

    constructor(
        address initialOwner,
        IERC20 coreToken,
        address[] memory initialParticipants,
        address consumerEOA,
        IPermit2 permit2
    ) Ownable(initialOwner) {
        s_state = GroupBillState.OPEN;
        s_expensesCount = 0;
        i_coreToken = IERC20(coreToken);
        i_consumerEOA = consumerEOA;
        s_isParticipant[initialOwner] = JoinState.JOINED;
        i_permit2 = permit2;

        assignParticipants(initialParticipants);
    }

    function assignParticipants(address[] memory participants) private {
        if (participants.length == 0) {
            revert GroupBill__ParticipantsEmpty();
        }
        for (uint256 i = 0; i < participants.length; i++) {
            if (s_isParticipant[participants[i]] != JoinState.JOINED) {
                s_isParticipant[participants[i]] = JoinState.PENDING;
            }
        }
    }

    function addParticipants(
        address[] memory participants
    ) public isParticipant {
        assignParticipants(participants);
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
        address borrower,
        uint256 amount
    ) public isParticipant returns (Expense memory addedExpense) {
        if (s_isParticipant[borrower] == JoinState.UKNOWN) {
            revert GroupBill__NotParticipant(borrower);
        }
        Expense memory expense = Expense(msg.sender, borrower, amount);
        s_expenses[s_expensesCount] = expense;
        s_expensesCount++;
        addedExpense = expense;
    }

    function editExpense(
        uint256 expenseIndex,
        address borrower,
        uint256 amount
    )
        public
        isExpenseLender(expenseIndex)
        returns (Expense memory updatedExpense)
    {
        s_expenses[expenseIndex] = Expense({
            lender: msg.sender,
            borrower: borrower,
            amount: amount
        });
        updatedExpense = s_expenses[expenseIndex];
    }

    function deleteExpense(
        uint256 expenseIndex
    ) public isExpenseLender(expenseIndex) {
        delete s_expenses[expenseIndex];
    }

    function submitExpensesAfterPruning(
        Expense[] memory prunedExpenses,
        bytes32 expensesHash
    ) public onlyConsumerEOA {
        if (s_expensesHash != expensesHash) {
            revert GroupBill__ExpensesHashMismatch(
                s_expensesHash,
                expensesHash
            );
        }
        if (s_prunedExpensesLength != 0) {
            for (uint i = 0; i < s_prunedExpensesLength; i++) {
                delete s_prunedExpenses[i];
            }
            s_prunedExpensesLength = 0;
        }

        for (uint i = 0; i < prunedExpenses.length; i++) {
            s_prunedExpenses[i] = prunedExpenses[i];
        }
        s_prunedExpensesLength = prunedExpenses.length;
        s_state = GroupBillState.READY_TO_SETTLE;
        emit ExpensePruningResultSubmitted(expensesHash);
    }

    function requestExpensePruning() public isParticipant {
        bytes32 newExpensesHash = sha256(abi.encode(getAllExpenses()));
        if (
            !(s_state == GroupBillState.OPEN ||
                s_state == GroupBillState.READY_TO_SETTLE)
        ) {
            revert GroupBill__StateActionForbidden(s_state, msg.sender);
        }
        // } else if (s_expensesHash != newExpensesHash) {
        //     revert GroupBill__ExpensesHashMismatch(
        //         s_expensesHash,
        //         newExpensesHash
        //     );
        // }

        s_expensesHash = newExpensesHash;
        emit ExpensePruningRequested(s_expensesHash);
        // TODO: uncomment when finished testing
        s_state = GroupBillState.PRUNING_IN_PROGRESS;
    }

    function getAllExpenses() public view returns (Expense[] memory) {
        Expense[] memory currentExpenses = new Expense[](s_expensesCount);
        for (uint i = 0; i < s_expensesCount; i++) {
            currentExpenses[i] = s_expenses[i];
        }
        return currentExpenses;
    }

    function getAllExpenses(
        bytes32 expensesHash
    ) public view returns (Expense[] memory) {
        if (expensesHash != s_expensesHash) {
            revert GroupBill__ExpensesHashMismatch(
                s_expensesHash,
                expensesHash
            );
        }
        return getAllExpenses();
    }

    function getExpensesHash() public view returns (bytes32) {
        return s_expensesHash;
    }

    function getName() public view returns (string memory) {
        return s_name;
    }

    function getSenderTotalLoan() public view isParticipant returns (uint256) {
        if (s_state != GroupBillState.READY_TO_SETTLE) {
            revert GroupBill__StateActionForbidden(s_state, msg.sender);
        }
        uint256 totalAmount = 0;
        for (uint i = 0; i < s_prunedExpensesLength; i++) {
            totalAmount += s_prunedExpenses[i].borrower == msg.sender
                ? s_prunedExpenses[i].amount
                : 0;
        }
        return totalAmount;
    }

    function getTxFee(
        IERC20 token,
        uint256 amount
    ) public pure returns (uint256) {
        // chainlink calls??
        // for now just mocking it to 1e18
        return 2200000 gwei; // 55gwei_per_gas * 50000gas
    }

    function setName(string memory gbName) public isParticipant {
        s_name = gbName;
    }

    function approveTokenSpend(uint160 totalAmount) public isParticipant {
        i_coreToken.approve(address(i_permit2), uint256(totalAmount));
        // i_permit2.approve(address(i_coreToken), address(i_permit2), totalAmount, block.timestamp + 1 days);
    }

    function permit2Ex(
        address owner,
        IAllowanceTransfer.PermitSingle memory singlePermit,
        bytes memory signature
    ) public isParticipant {
        if (address(singlePermit.details.token) != address(i_coreToken)) {
            revert GroupBill__InvalidToken(singlePermit.details.token);
        }

        // owner - the user themselves (borrower)
        // spender - address(this) aka current group bill (integrating contract)
        // transferFrom should be triggered by this groupBill to corresponding s_prunedExpenses participants
        // anyone can trigger local transfer method, but the address(this) will be calling permit2 which checks out

        i_permit2.permit(owner, singlePermit, signature);
        s_hasVoted[owner] = true;

        // require(
        //     permitToken.allowance(_permit.owner, address(this)) == 1e18 + 1e17,
        //     "allowance not found"
        // );
        // require(permitToken.nonces(_permit.owner) == 1, "nonce is not 1"); // next nonce is 1, means that 0 is already taken
        // console.log(
        //     "Onchain log: Group bill token balance before the transfer:"
        // );
        // console.logUint(permitToken.balanceOf(address(this)));
        // permitToken.transferFrom(
        //     _permit.owner,
        //     address(this),
        //     borrowerLoan + txFee
        // );
        // console.log("Onchain log: New group bill token balance");
        // console.logUint(permitToken.balanceOf(address(this)));
    }

    // function permit(
    //     SigUtils.Permit memory _permit,
    //     uint8 v,
    //     bytes32 r,
    //     bytes32 s
    // ) public isParticipant {
    //     // TODO: when this method is called, the user should allow the contract
    //     // to operate on N amount of funds on user's behalf (signing process) (*deadline*: for 5 min??)
    //     // SIGNING MUST TAKE PLACE!!!
    //     // s_hasVoted[msg.sender] = true;
    //     // _hasVoted = s_hasVoted[msg.sender];
    //     // hasVoted
    //     uint borrowerLoan = getSenderTotalLoan();
    //     uint txFee = getTxFee(i_coreToken, borrowerLoan);
    //     ERC20Permit permitToken = ERC20Permit(address(i_coreToken));
    //     console.log("contract permit and deadline");
    //     console.logUint(_permit.deadline);
    //     console.logUint(block.timestamp);

    //     permitToken.permit(
    //         _permit.owner,
    //         address(this),
    //         borrowerLoan + txFee,
    //         _permit.deadline,
    //         v,
    //         r,
    //         s
    //     );

    //     require(
    //         permitToken.allowance(_permit.owner, address(this)) == 1e18 + 1e17,
    //         "allowance not found"
    //     );
    //     require(permitToken.nonces(_permit.owner) == 1, "nonce is not 1"); // next nonce is 1, means that 0 is already taken
    //     console.log(
    //         "Onchain log: Group bill token balance before the transfer:"
    //     );
    //     console.logUint(permitToken.balanceOf(address(this)));
    //     permitToken.transferFrom(
    //         _permit.owner,
    //         address(this),
    //         borrowerLoan + txFee
    //     );
    //     console.log("Onchain log: New group bill token balance");
    //     console.logUint(permitToken.balanceOf(address(this)));
    // }

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
        // all participants have signed off (voted) -> initiate share destribution
    }

    function getState() public view returns (GroupBillState) {
        return s_state;
    }

    function getCoreToken() public view returns (address) {
        return address(i_coreToken);
    }

    function getConsumerEOA() public view returns (address) {
        return i_consumerEOA;
    }

    function getParticipantState() public view returns (JoinState) {
        return s_isParticipant[msg.sender];
    }

    modifier isParticipant() {
        if (s_isParticipant[msg.sender] != JoinState.JOINED) {
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

    modifier onlyConsumerEOA() {
        if (msg.sender != i_consumerEOA) {
            revert GroupBill__AddressIsNotTrusted(msg.sender);
        }
        _;
        // for (uint i = 0; i < i_trustedEOAs.length; i++) {
        //     if (i_trustedEOAs[i] == msg.sender) {
        //         _;
        //         return;
        //     }
        // }
    }
}
