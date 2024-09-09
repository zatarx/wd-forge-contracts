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
import {LenderAmount, NamedBorrowerAmounts, LenderNamedExpense, Expense, PostPruningBorrowerExpense, PostPruningTotalAmount, BorrowerAmount} from "./helpers/Expenses.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

error GroupBill__NotParticipant(address sender);
error GroupBill__NotExpenseOwner(address sender);
error GroupBill__HasNotVoted(address sender);
error GroupBill__ParticipantsEmpty();
error GroupBill__NotAllowedToJoin(address sender);
error GroupBill__AddressIsNotTrusted(address sender);
error GroupBill__InvalidToken(address token);
error GroupBill__SettlementPermitNotValid(
    address owner,
    address token,
    address spender
);
error GroupBill__SettlementPermitExpired(
    address owner,
    address spender,
    uint expiration
);
error GroupBill__NotSufficientPermitAmount(
    address sender,
    uint256 amount,
    uint256 amountNeeded
);

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

    GroupBillState public s_state;
    string public s_name;

    bytes32 private s_expensesHash;
    uint private s_expensesCount;
    mapping(uint => Expense) private s_expenses;

    mapping(address => mapping(string => BorrowerAmount[]))
        private s_lenderNamedExpenses;
    mapping(address => string[]) private s_lenderExpenseNames;

    address[] private s_postPruningBorrowers;
    mapping(address => PostPruningTotalAmount)
        private s_postPruningBorrowerExpenses;

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
        bytes32 expensesHash
    );
    error GroupBill__StateActionForbidden(GroupBillState state, address sender);
    error GroupBill__TransferFromFailed(address participant, bytes reason);

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

    function getParticipantState() public view returns (JoinState) {
        return s_isParticipant[msg.sender];
    }

    function getParticipants() public view returns (address[] memory) {
        return s_participants;
    }

    function getConsumerEOA() public view returns (address) {
        return i_consumerEOA;
    }

    /// @dev returns expense tree view [{<lender> -> [{<expenseName> -> [{<borrower>, <amount>}]}]}]
    /// This method is expected to be called by the clients
    function getLenderNamedExpensesHierarchy()
        public
        view
        returns (LenderNamedExpense[] memory)
    {
        LenderNamedExpense[] memory expenseHierarchy = new LenderNamedExpense[](
            s_participants.length
        );

        for (uint i = 0; i < s_participants.length; i++) {
            address lender = s_participants[i];
            expenseHierarchy[i] = LenderNamedExpense({
                lender: lender,
                namedBorrowerAmounts: new NamedBorrowerAmounts[](
                    s_lenderExpenseNames[lender].length
                )
            });

            for (uint j = 0; j < s_lenderExpenseNames[lender].length; j++) {
                string memory currentExpenseName = s_lenderExpenseNames[lender][
                    j
                ];

                expenseHierarchy[i].namedBorrowerAmounts[
                    j
                ] = NamedBorrowerAmounts({
                    name: currentExpenseName,
                    borrowerAmounts: s_lenderNamedExpenses[lender][
                        currentExpenseName
                    ]
                });
            }
        }

        return expenseHierarchy;
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
        BorrowerAmount[] memory borrowerAmountItems,
        string memory expenseName
    ) public isParticipant {
        // validation of groupExpenseItems is happening on the client
        s_lenderNamedExpenses[msg.sender][expenseName] = borrowerAmountItems;

        for (uint i = 0; i < s_lenderExpenseNames[msg.sender].length; i++) {
            bytes32 expenseNameHash = keccak256(
                abi.encode(s_lenderExpenseNames[msg.sender][i])
            );
            bytes32 parameterExpensesHash = keccak256(abi.encode(expenseName));

            if (expenseNameHash == parameterExpensesHash) {
                return;
            }
        }
        s_lenderExpenseNames[msg.sender].push(expenseName);
    }

    function deleteGroupExpense(
        string memory expenseName
    ) public isParticipant {
        delete s_lenderNamedExpenses[msg.sender][expenseName];

        for (uint i = 0; i < s_lenderExpenseNames[msg.sender].length; i++) {
            bytes32 expenseNameHash = keccak256(
                abi.encode(s_lenderExpenseNames[msg.sender][i])
            );
            bytes32 parameterGroupExpensesHash = keccak256(
                abi.encode(expenseName)
            );

            if (expenseNameHash == parameterGroupExpensesHash) {
                delete s_lenderExpenseNames[msg.sender][i];
                break;
            }
        }
    }

    function submitExpensesAfterPruning(
        Expense[] memory prunedExpenses,
        bytes32 expensesHash
    ) public {
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

    function submitPostPruningBorrowerExpenses(
        PostPruningBorrowerExpense[] memory borrowerExpenseHierarchy,
        bytes32 expensesHash
    ) public {
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

        for (uint i = 0; i < s_postPruningBorrowers.length; i++) {
            delete s_postPruningBorrowerExpenses[s_postPruningBorrowers[i]];
        }
        delete s_postPruningBorrowers;

        for (uint i = 0; i < borrowerExpenseHierarchy.length; i++) {
            PostPruningBorrowerExpense memory be = borrowerExpenseHierarchy[i];

            s_postPruningBorrowers.push(be.borrower);
            s_postPruningBorrowerExpenses[
                be.borrower
            ] = PostPruningTotalAmount({
                totalAmount: be.totalAmount,
                lenderAmounts: be.lenderAmounts
            });
        }
        s_state = GroupBillState.READY_TO_SETTLE;
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

    function getPostPruningSenderTotalLoan()
        public
        view
        isParticipant
        returns (uint256)
    {
        if (s_state != GroupBillState.READY_TO_SETTLE) {
            revert GroupBill__StateActionForbidden(s_state, msg.sender);
        }
        return s_postPruningBorrowerExpenses[msg.sender].totalAmount;
    }

    /// @dev hardcoded for now, i_coreToken is expected to be dai/usdt alike
    function getTxFee(uint256 amount) public pure returns (uint256) {
        return 5 * 1e17;
    }

    function getCoreTokenBalance() public view returns (uint256) {
        return i_coreToken.balanceOf(address(this));
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
        // Users recall their signatures using the client app (acquiring the permit2 contract)
    }

    function settle()
        public
        isParticipant
        returns (bool settlementCompleted)
    {
        if (s_state != GroupBillState.READY_TO_SETTLE) {
            revert GroupBill__StateActionForbidden(s_state, msg.sender);
        }
        s_state = GroupBillState.SETTLEMENT_IN_PROGRESS;
        settlementCompleted = settleCollectively();
    }

    function settleCollectively() public isParticipant returns (bool settlementCompleted) {
        // all participants have signed off (voted) -> initiate share destribution
        // check that all the participants have signatures that are indeed valid
        // if they are -> proceed to calling transferFrom on participants
        /// @dev ensure that every participant has allocated sufficient amount
        for (uint i = 0; i < s_participants.length; i++) {
            address borrower = s_participants[i];
            (uint160 amount, uint48 expiration, ) = i_permit2.allowance(
                borrower,
                address(i_coreToken),
                address(this)
            );
            if (s_postPruningBorrowerExpenses[borrower].totalAmount == 0) {
                continue;
            } else if (
                amount < s_postPruningBorrowerExpenses[borrower].totalAmount
            ) {
                revert GroupBill__NotSufficientPermitAmount(
                    borrower,
                    amount,
                    s_postPruningBorrowerExpenses[borrower].totalAmount
                );
            }

            if (block.timestamp > expiration) {
                revert GroupBill__SettlementPermitExpired(
                    s_participants[i],
                    address(this),
                    expiration
                );
            } else if (amount == 0) {
                revert GroupBill__SettlementPermitNotValid(
                    s_participants[i],
                    address(i_coreToken),
                    address(this)
                );
            }
        }

        /// @notice transferFrom happens only once per borrower in order to reduce amount of txs
        for (
            uint borrowerIndex = 0;
            borrowerIndex < s_postPruningBorrowers.length;
            borrowerIndex++
        ) {
            address borrower = s_postPruningBorrowers[borrowerIndex];
            PostPruningTotalAmount
                memory borrowerExpense = s_postPruningBorrowerExpenses[
                    borrower
                ];

            try
                i_permit2.transferFrom(
                    borrower,
                    address(this),
                    uint160(
                        borrowerExpense.totalAmount +
                            getTxFee(borrowerExpense.totalAmount)
                    ),
                    address(i_coreToken)
                )
            {} catch (bytes memory reason) {
                // todo: make a more meaningful error reporting, insufficient balance can be encountered
                s_state = GroupBillState.READY_TO_SETTLE;
                settlementCompleted = false;
                revert GroupBill__TransferFromFailed(borrower, reason);
            }

            for (
                uint lenderIndex = 0;
                lenderIndex <
                s_postPruningBorrowerExpenses[borrower].lenderAmounts.length;
                lenderIndex++
            ) {
                LenderAmount
                    memory lenderAmount = s_postPruningBorrowerExpenses[
                        borrower
                    ].lenderAmounts[lenderIndex];

                i_coreToken.transfer(lenderAmount.lender, lenderAmount.amount);
            }
        }
        settlementCompleted = true;
        s_state = GroupBillState.SETTLED;
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
            for (uint j = 0; j < s_lenderExpenseNames[lender].length; j++) {
                string memory currentExpenseName = s_lenderExpenseNames[lender][
                    j
                ];
                flatExpensesLength += s_lenderNamedExpenses[lender][
                    currentExpenseName
                ].length;
            }
        }

        Expense[] memory currentExpenses = new Expense[](flatExpensesLength);
        uint256 flatExpensesCount = 0;
        for (uint i = 0; i < s_participants.length; i++) {
            address lender = s_participants[i];

            for (uint j = 0; j < s_lenderExpenseNames[lender].length; j++) {
                string memory currentExpenseName = s_lenderExpenseNames[lender][
                    j
                ];
                BorrowerAmount[] memory borrowerAmounts = s_lenderNamedExpenses[
                    lender
                ][currentExpenseName];

                for (uint z = 0; z < borrowerAmounts.length; z++) {
                    currentExpenses[flatExpensesCount] = Expense({
                        lender: lender,
                        borrower: borrowerAmounts[z].borrower,
                        amount: borrowerAmounts[z].amount
                    });
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
