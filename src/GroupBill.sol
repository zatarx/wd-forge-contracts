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
import {GroupExpenseItem, NamedGroupExpenses, LenderGroupExpenses, Expense} from "./helpers/Expenses.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

error GroupBill__NotParticipant(address sender);
error GroupBill__NotExpenseOwner(address sender);
error GroupBill__HasNotVoted(address sender);
error GroupBill__ParticipantsEmpty();
error GroupBill__NotAllowedToJoin(address sender);
error GroupBill__AddressIsNotTrusted(address sender);
error GroupBill__InvalidToken(address token);


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

    IPermit2 public immutable i_permit2;
    IERC20 public immutable i_coreToken; // participants can only donate in this token (gets set once)
    address public immutable i_consumerEOA;
    
    GroupBillState private s_state;
    string private s_name;

    bytes32 private s_expensesHash;
    uint private s_expensesCount;
    mapping(uint => Expense) private s_expenses;

    mapping(address => mapping(string => GroupExpenseItem[])) private s_groupExpenses;
    mapping(address => string[]) private s_groupExpenseNames;

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
        addParticipant(initialOwner, JoinState.JOINED);
        i_permit2 = permit2;

        addPendingParticipants(initialParticipants);
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

    function getParticipants() public view returns(address[] memory) {
        return s_participants;
    }

    function getPermit2() public view returns (IPermit2 permit2) {
        permit2 = i_permit2;
    }

    /// @dev returns expense tree view [{<lender> -> [{<expenseName> -> [{<borrower>, <amount>}]}]}]
    /// This method is expected to be called by the clients
    function getAllExpenseHierarchy() public view returns (LenderGroupExpenses[] memory) {
        LenderGroupExpenses[] memory lenderGroupExpenses = new LenderGroupExpenses[](s_participants.length);

        for (uint i = 0; i < s_participants.length; i++) {
            address lender = s_participants[i];
            lenderGroupExpenses[i] = LenderGroupExpenses({
                lender: lender,
                namedGroupExpenses: new NamedGroupExpenses[](s_groupExpenseNames[lender].length)
            });

            for (uint j = 0; j < s_groupExpenseNames[lender].length; j++) {
                string memory currentExpenseName = s_groupExpenseNames[lender][j];

                lenderGroupExpenses[i].namedGroupExpenses[j] = NamedGroupExpenses({
                    name: currentExpenseName,
                    groupExpenses: s_groupExpenses[lender][currentExpenseName]
                });
            }
        }

        return lenderGroupExpenses;
    }

    function addParticipant(address participant, JoinState state) private {
        s_isParticipant[participant] = state; 
        s_participants.push(participant);
    }

    function addParticipants(
        address[] memory participants
    ) public isParticipant {
        addPendingParticipants(participants);
    }

    function join() public returns (JoinState joinState) {
        if (s_isParticipant[msg.sender] != JoinState.PENDING) {
            revert GroupBill__NotAllowedToJoin(msg.sender);
        }
        s_isParticipant[msg.sender] = JoinState.JOINED;
        joinState = s_isParticipant[msg.sender];
    }

    function submitGroupExpenses(
        GroupExpenseItem[] memory groupExpenseItems,
        string memory expenseName
    ) public isParticipant {
        // validation of groupExpenseItems is happening on the client
        s_groupExpenses[msg.sender][expenseName] = groupExpenseItems;

        for (uint i = 0; i < s_groupExpenseNames[msg.sender].length; i++) {
            bytes32 groupExpenseNameHash = keccak256(
                abi.encode(s_groupExpenseNames[msg.sender][i])
            );
            bytes32 parameterGroupExpenseHash = keccak256(
                abi.encode(expenseName)
            );

            if (groupExpenseNameHash == parameterGroupExpenseHash) {
                return;
            }
        }
        s_groupExpenseNames[msg.sender].push(expenseName);
    }

    function deleteGroupExpense(
        string memory expenseName
    ) public isParticipant {
        delete s_groupExpenses[msg.sender][expenseName];

        for (uint i = 0; i < s_groupExpenseNames[msg.sender].length; i++) {
            bytes32 groupExpenseNameHash = keccak256(
                abi.encode(s_groupExpenseNames[msg.sender][i])
            );
            bytes32 parameterGroupExpenseHash = keccak256(
                abi.encode(expenseName)
            );

            if (groupExpenseNameHash == parameterGroupExpenseHash) {
                delete s_groupExpenseNames[msg.sender][i];
                break;
            }
        }
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
        bytes32 newExpensesHash = sha256(abi.encode(getFlatExpenses()));
        if (
            !(s_state == GroupBillState.OPEN ||
                s_state == GroupBillState.READY_TO_SETTLE)
        ) {
            revert GroupBill__StateActionForbidden(s_state, msg.sender);
        } 
        // else if (s_expensesHash != newExpensesHash) {
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

    function getFlatExpenses(
        bytes32 expensesHash
    ) public view returns (Expense[] memory) {
        if (expensesHash != s_expensesHash) {
            revert GroupBill__ExpensesHashMismatch(
                s_expensesHash,
                expensesHash
            );
        }
        return getFlatExpenses();
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

    function permit(
        address owner,
        IAllowanceTransfer.PermitSingle memory singlePermit,
        bytes calldata signature
    ) public isParticipant {
        if (address(singlePermit.details.token) != address(i_coreToken)) {
            revert GroupBill__InvalidToken(singlePermit.details.token);
        }
        if (singlePermit.spender != address(this)) {
            revert GroupBill__InvalidToken(address(0));
        }

        i_permit2.permit(msg.sender, singlePermit, signature);

        console.log("Group Bill token balance");
        console.logUint(i_coreToken.balanceOf(address(this)));

        // i_permit2.transferFrom(
        //     msg.sender,
        //     address(this),
        //     singlePermit.details.amount,
        //     address(i_coreToken)
        // );
        // console.logUint(i_coreToken.balanceOf(address(this)));
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
        // all participants have signed off (voted) -> initiate share destribution
    }


    function addPendingParticipants(address[] memory participants) private {
        if (participants.length == 0) {
            revert GroupBill__ParticipantsEmpty();
        }
        for (uint256 i = 0; i < participants.length; i++) {
            if (s_isParticipant[participants[i]] != JoinState.JOINED) {
                addParticipant(participants[i], JoinState.PENDING);
            }
        }
    }

    function getFlatExpenses() public view returns (Expense[] memory) {
        uint256 flatExpensesLength = 0;

        for (uint i = 0; i < s_participants.length; i++) {
            address lender = s_participants[i];
            for (uint j = 0; j < s_groupExpenseNames[lender].length; j++) {
                string memory currentExpenseName = s_groupExpenseNames[lender][
                    j
                ];
                flatExpensesLength += s_groupExpenses[lender][
                    currentExpenseName
                ].length;
            }
        }

        Expense[] memory currentExpenses = new Expense[](flatExpensesLength);
        uint flatExpensesCount = 0;
        for (uint i = 0; i < s_participants.length; i++) {
            address lender = s_participants[i];

            for (uint j = 0; j < s_groupExpenseNames[lender].length; j++) {
                string memory currentExpenseName = s_groupExpenseNames[lender][j];
                GroupExpenseItem[] memory ges = s_groupExpenses[lender][currentExpenseName];

                for (uint z = 0; z < ges.length; z++) {
                    currentExpenses[flatExpensesCount] = Expense({lender: lender, borrower: ges[z].borrower, amount: ges[z].amount});
                    flatExpensesCount++;
                }
            }
        }
        return currentExpenses;
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
