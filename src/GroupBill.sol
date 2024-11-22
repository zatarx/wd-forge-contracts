// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "./helpers/Errors.sol";
import "./helpers/Expenses.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {GroupBillAccessControl} from "./GroupBillAccessControl.sol";
import {SigUtils} from "./SigUtils.sol";
import {IPermit2} from "./Utils.sol";
import {MsgSigner} from "./MsgSigner.sol";


/**
 * @dev Contract that encapsulates all the group settlement logic
*/
contract GroupBill is Ownable, MsgSigner {
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

    GroupBillAccessControl private immutable i_ac;
    IPermit2 public immutable i_permit2;
    IERC20 public immutable i_coreToken; // participants can only donate in this token (gets set once)
    address public immutable i_consumerEOA;

    GroupBillState public s_state;
    string public s_name;

    bytes32 private s_expensesHash;
    uint private s_expensesCount;
    mapping(uint => Expense) private s_expenses;

    mapping(address => mapping(string => BorrowerAmount[])) private s_lenderNamedExpenses;
    mapping(address => string[]) private s_lenderExpenseNames;

    address[] private s_postPruningBorrowers;
    mapping(address => PostPruningTotalAmount) private s_postPruningBorrowerExpenses;

    address[] public s_participants;
    mapping(address => JoinState) public s_isParticipant;

    event ExpensePruningRequested(bytes32 indexed expensesHash);
    event ExpensePruningResultSubmitted(bytes32 indexed expensesHash);
    event ExpenseSettlementCompleted();

    error GroupBill__DifferentGroupBillStateExpected(GroupBillState currentState, GroupBillState[] expectedStates);
    error GroupBill__ExpensesHashMismatch(bytes32 currentExpensesHash, bytes32 expensesHash);
    error GroupBill__StateActionForbidden(GroupBillState state, address sender);
    error GroupBill__TransferFromFailed(address participant, bytes reason);

    constructor(
        address initialOwner,
        IERC20 coreToken,
        address[] memory initialParticipants,
        address consumerEOA,
        address gbAccount,
        GroupBillAccessControl ac,
        IPermit2 permit2
    ) Ownable(initialOwner) MsgSigner(gbAccount) {
        s_state = GroupBillState.OPEN;
        s_expensesCount = 0;
        i_coreToken = IERC20(coreToken);
        i_consumerEOA = consumerEOA;
        i_ac = GroupBillAccessControl(ac);
        addParticipant(initialOwner, JoinState.JOINED);
        i_permit2 = permit2;

        addPendingParticipants(initialParticipants);
    }

    function getParticipantState() public view returns (JoinState) {
        return s_isParticipant[s_msgSigner];
    }

    function getParticipants() public view returns (address[] memory) {
        return s_participants;
    }

    function getConsumerEOA() public view returns (address) {
        return i_consumerEOA;
    }

    /// @dev returns expense tree view [{<lender> -> [{<expenseName> -> [{<borrower>, <amount>}]}]}]
    /// Method is to be called by the dapp
    function getLenderNamedExpensesHierarchy() public view returns (LenderNamedExpense[] memory) {
        LenderNamedExpense[] memory expenseHierarchy = new LenderNamedExpense[](s_participants.length);

        for (uint participantIndex = 0; participantIndex < s_participants.length; participantIndex++) {
            address lender = s_participants[participantIndex];
            expenseHierarchy[participantIndex] = LenderNamedExpense({
                lender: lender,
                namedBorrowerAmounts: new NamedBorrowerAmounts[](s_lenderExpenseNames[lender].length)
            });

            for (uint nameIndex = 0; nameIndex < s_lenderExpenseNames[lender].length; nameIndex++) {
                string memory currentExpenseName = s_lenderExpenseNames[lender][nameIndex];

                expenseHierarchy[participantIndex].namedBorrowerAmounts[nameIndex] = NamedBorrowerAmounts({
                    name: currentExpenseName,
                    borrowerAmounts: s_lenderNamedExpenses[lender][currentExpenseName]
                });
            }
        }

        return expenseHierarchy;
    }

    function addParticipant(address participant, JoinState state) private {
        s_isParticipant[participant] = state;
        s_participants.push(participant);
    }

    function addParticipants(address[] memory participants) public onlyTrustedAccount {
        addPendingParticipants(participants);
    }

    function join() onlyTrustedAccount public returns (JoinState joinState) {
        if (s_isParticipant[s_msgSigner] != JoinState.PENDING) {
            revert GroupBill__NotAllowedToJoin(s_msgSigner);
        }
        s_isParticipant[s_msgSigner] = JoinState.JOINED;
        joinState = s_isParticipant[s_msgSigner];

        /// @dev once role of participant is granted, it never gets revoked (POC feature)
        i_ac.grantGBParticipantRole(s_msgSigner, address(this));
    }

    /// @dev validation of groupExpenseItems is happening on the client
    function submitExpense(
        BorrowerAmount[] memory borrowerAmountItems,
        string memory expenseName
    ) public isParticipant onlyTrustedAccount {
        s_lenderNamedExpenses[s_msgSigner][expenseName] = borrowerAmountItems;

        for (uint nameId = 0; nameId < s_lenderExpenseNames[s_msgSigner].length; nameId++) {
            bytes32 expenseNameHash = keccak256(abi.encode(s_lenderExpenseNames[s_msgSigner][nameId]));
            bytes32 parameterExpensesHash = keccak256(abi.encode(expenseName));

            if (expenseNameHash == parameterExpensesHash) {
                return;
            }
        }
        s_lenderExpenseNames[s_msgSigner].push(expenseName);
    }

    function deleteGroupExpense(string memory expenseName) public isParticipant onlyTrustedAccount {
        delete s_lenderNamedExpenses[s_msgSigner][expenseName];

        for (uint nameId = 0; nameId < s_lenderExpenseNames[s_msgSigner].length; nameId++) {
            bytes32 expenseNameHash = keccak256(abi.encode(s_lenderExpenseNames[s_msgSigner][nameId]));
            bytes32 parameterGroupExpensesHash = keccak256(abi.encode(expenseName));

            if (expenseNameHash == parameterGroupExpensesHash) {
                delete s_lenderExpenseNames[s_msgSigner][nameId];
                break;
            }
        }
    }

    function submitPostPruningBorrowerExpenses(
        PostPruningBorrowerExpense[] memory borrowerExpenseHierarchy,
        bytes32 expensesHash
    ) public onlyConsumerEOA {
        if (s_expensesHash != expensesHash) {
            revert GroupBill__ExpensesHashMismatch(s_expensesHash, expensesHash);
        }

        for (uint borrowerId = 0; borrowerId < s_postPruningBorrowers.length; borrowerId++) {
            delete s_postPruningBorrowerExpenses[s_postPruningBorrowers[borrowerId]];
        }
        delete s_postPruningBorrowers;

        for (uint expenseId = 0; expenseId < borrowerExpenseHierarchy.length; expenseId++) {
            PostPruningBorrowerExpense memory be = borrowerExpenseHierarchy[expenseId];

            s_postPruningBorrowers.push(be.borrower);
            s_postPruningBorrowerExpenses[be.borrower] = PostPruningTotalAmount({
                totalAmount: be.totalAmount,
                lenderAmounts: be.lenderAmounts
            });
        }
        s_state = GroupBillState.READY_TO_SETTLE;
    }

    function requestExpensePruning() public isParticipant onlyTrustedAccount {
        bytes32 newExpensesHash = sha256(abi.encode(getFlatExpenses()));
        if (!(s_state == GroupBillState.OPEN || s_state == GroupBillState.READY_TO_SETTLE)) {
            revert GroupBill__StateActionForbidden(s_state, s_msgSigner);
        }

        s_expensesHash = newExpensesHash;
        emit ExpensePruningRequested(s_expensesHash);
        s_state = GroupBillState.PRUNING_IN_PROGRESS;
    }

    function getFlatExpenses(bytes32 expensesHash) public view returns (Expense[] memory) {
        if (expensesHash != s_expensesHash) {
            revert GroupBill__ExpensesHashMismatch(s_expensesHash, expensesHash);
        }
        return getFlatExpenses();
    }

    function getExpensesHash() public view returns (bytes32) {
        return s_expensesHash;
    }

    function getName() public view returns (string memory) {
        return s_name;
    }

    function getPostPruningSenderTotalLoan() public view isParticipant returns (uint256) {
        if (s_state != GroupBillState.READY_TO_SETTLE) {
            revert GroupBill__StateActionForbidden(s_state, s_msgSigner);
        }
        return s_postPruningBorrowerExpenses[s_msgSigner].totalAmount;
    }

    /// @dev hardcoded for now, i_coreToken should be dai/usdc-like
    function getTxFee() public pure returns (uint256) {
        return 5 * 1e17;
    }

    function getCoreTokenBalance() public view returns (uint256) {
        return i_coreToken.balanceOf(address(this));
    }

    function setName(string memory gbName) public isParticipant onlyTrustedAccount {
        s_name = gbName;
    }

    function permit(
        IAllowanceTransfer.PermitSingle memory singlePermit,
        bytes calldata signature
    ) public isParticipant onlyTrustedAccount {
        if (address(singlePermit.details.token) != address(i_coreToken)) {
            revert GroupBill__InvalidToken(singlePermit.details.token);
        }
        if (singlePermit.spender != address(this)) {
            revert GroupBill__InvalidToken(address(0));
        }

        i_permit2.permit(s_msgSigner, singlePermit, signature);

        console.log("Group Bill token balance");
        console.logUint(i_coreToken.balanceOf(address(this)));
    }

    function settle() public isParticipant onlyTrustedAccount returns (bool settlementCompleted) {
        if (s_state != GroupBillState.READY_TO_SETTLE) {
            revert GroupBill__StateActionForbidden(s_state, s_msgSigner);
        }
        s_state = GroupBillState.SETTLEMENT_IN_PROGRESS;
        settlementCompleted = settleCollectively();
    }

    function settleCollectively() public isParticipant onlyTrustedAccount returns (bool settlementCompleted) {
        /// @dev ensure that every participant has allocated sufficient amount
        for (uint participatnId = 0; participatnId < s_participants.length; participatnId++) {
            address borrower = s_participants[participatnId];
            (uint160 amount, uint48 expiration, ) = i_permit2.allowance(borrower, address(i_coreToken), address(this));
            if (s_postPruningBorrowerExpenses[borrower].totalAmount == 0) {
                continue;
            } else if (amount < s_postPruningBorrowerExpenses[borrower].totalAmount) {
                revert GroupBill__NotSufficientPermitAmount(
                    borrower,
                    amount,
                    s_postPruningBorrowerExpenses[borrower].totalAmount
                );
            }

            if (block.timestamp > expiration) {
                revert GroupBill__SettlementPermitExpired(borrower, address(this), expiration);
            }
        }

        /// @notice transferFrom happens only once per borrower in order to reduce amount of txs
        for (uint borrowerId = 0; borrowerId < s_postPruningBorrowers.length; borrowerId++) {
            address borrower = s_postPruningBorrowers[borrowerId];
            PostPruningTotalAmount memory borrowerExpense = s_postPruningBorrowerExpenses[borrower];
            console.log("test address this log");
            console.logAddress(address(this));

            console.log("borrower address");
            console.log(borrower);
            console.logAddress(borrower);

            try
                i_permit2.transferFrom(
                    borrower,
                    address(this),
                    uint160(borrowerExpense.totalAmount + getTxFee()),
                    address(i_coreToken)
                )
            {} catch (bytes memory reason) {
                // todo: make a more meaningful error reporting, insufficient balances can be encountered
                s_state = GroupBillState.READY_TO_SETTLE;
                settlementCompleted = false;
                revert GroupBill__TransferFromFailed(borrower, reason);
            }
            
            console.log("after transferFrom method to -group bill address");

            for (
                uint lenderId = 0;
                lenderId < s_postPruningBorrowerExpenses[borrower].lenderAmounts.length;
                lenderId++
            ) {
                LenderAmount memory lenderAmount = s_postPruningBorrowerExpenses[borrower].lenderAmounts[lenderId];

                i_coreToken.transfer(lenderAmount.lender, lenderAmount.amount);
            }
        }
        settlementCompleted = true;
        s_state = GroupBillState.SETTLED;

        // TODO: revoke old PARTICIPANT permissions ??
    }

    function addPendingParticipants(address[] memory participants) private {
        if (participants.length == 0) {
            revert GroupBill__ParticipantsEmpty();
        }
        for (uint256 participantId = 0; participantId < participants.length; participantId++) {
            if (s_isParticipant[participants[participantId]] != JoinState.JOINED) {
                addParticipant(participants[participantId], JoinState.PENDING);
            }
        }
    }

    function getFlatExpenses() public view returns (Expense[] memory) {
        uint256 flatExpensesLength = 0;

        for (uint participantId = 0; participantId < s_participants.length; participantId++) {
            address lender = s_participants[participantId];
            for (uint nameId = 0; nameId < s_lenderExpenseNames[lender].length; nameId++) {
                string memory currentExpenseName = s_lenderExpenseNames[lender][nameId];
                flatExpensesLength += s_lenderNamedExpenses[lender][currentExpenseName].length;
            }
        }

        Expense[] memory currentExpenses = new Expense[](flatExpensesLength);
        uint256 flatExpensesCount = 0;
        for (uint participantId = 0; participantId < s_participants.length; participantId++) {
            address lender = s_participants[participantId];

            for (uint nameId = 0; nameId < s_lenderExpenseNames[lender].length; nameId++) {
                string memory currentExpenseName = s_lenderExpenseNames[lender][nameId];
                BorrowerAmount[] memory borrowerAmounts = s_lenderNamedExpenses[lender][currentExpenseName];

                for (uint borrowerAmountId = 0; borrowerAmountId < borrowerAmounts.length; borrowerAmountId++) {
                    currentExpenses[flatExpensesCount] = Expense({
                        lender: lender,
                        borrower: borrowerAmounts[borrowerAmountId].borrower,
                        amount: borrowerAmounts[borrowerAmountId].amount
                    });
                    flatExpensesCount++;
                }
            }
        }
        return currentExpenses;
    }

    modifier isParticipant() {
        if (s_isParticipant[s_msgSigner] != JoinState.JOINED) {
            revert GroupBill__NotParticipant(s_msgSigner);
        }
        _;
    }

    // modifier isExpenseLender(uint256 expenseIndex) {
    //     if (s_expenses[expenseIndex].lender != msg.sender) {
    //         revert GroupBill__NotExpenseOwner(msg.sender);
    //     }
    //     _;
    // }

    modifier onlyConsumerEOA() {
        if (s_msgSigner != i_consumerEOA) {
            revert GroupBill__AddressIsNotTrusted(s_msgSigner);
        }
        _;
    }
}
