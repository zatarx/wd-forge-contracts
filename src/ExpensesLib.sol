// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// contract SettlementGraph {
//     Expenses.Expense[] public s_expenses;

//     address[] public s_borrowers;
//     mapping(address => address[]) public s_isBorrower;
//     mapping(address => address[]) s_borrowerLenders;
//     mapping(address => mapping(address => bool)) s_borrowerLenderIds;

//     mapping(address => mapping(address => uint)) public s_borrowerLenderGraph;

//     address[] public s_lenders;
//     mapping(address => bool) public s_isLender;
//     mapping(address => address[]) public s_lenderBorrowers;
//     mapping(address => mapping(address => uint)) public s_lenderBorrowerIds;

//     mapping(address => mapping(address => uint)) public s_lenderBorrowerGraph;

//     constructor(Expenses.Expense[] memory expenses) public {
//         s_expenses = expenses;
//     }

//     function buildGraphs(Expenses[] storage expenses) internal {
//         for (uint i = 0; i < expenses.length; i++) {
//             Expenses.Expense expense = expenses[i];

//             if (!s_isBorrower[expense.borrower]) {
//                 s_borrowers.push(expense.borrower);
//                 s_isBorrower[expense.borrower] = true;
//             }

//             // Guaranteed to have only one pair of values borrower -> lender connection
//             s_borrowerLenders[expense.borrower].push(expense.lender);
//             s_borrowerLenderIndex[expense.borrower][expense.lender] =
//                 s_borrowerLenders[expense.borrower].length -
//                 1;

//             s_borrowerLenderGraph[expense.borrower][expense.lender] += expense
//                 .amount;

//             if (!s_isLender[expense.lender]) {
//                 s_lenders.push(expense.lender);
//                 s_isLender[expense.lender] = true;
//             }

//             // Guaranteed to be a unique pair lender -> borrower
//             s_lenderBorrowers[expense.lender].push(expense.borrower);
//             s_lenderBorrowerIndex[expense.lender][expense.borrower] =
//                 s_lenderBorrowers[expense.lender].length -
//                 1;

//             s_lenderBorrowerGraph[expense.lender][expense.borrower] += expense
//                 .amount;
//         }
//     }

//     // function getGraphs()
//     //     public
//     //     returns ()
//     // // mapping(address => mapping(address => uint)) memory _s_graph,
//     // // mapping(address => mapping(address => uint)) memory _s_flippedGraph
//     // {
//     //     // _s_graph = s_graph;
//     //     // _s_reveresedGraph = reversedGraph;
//     // }

//     function pruneEdge(address borrower, address lender) public {
//         // 1. delete borrower -> lender graph amount
//         // 2. delete lender item from s_borrowerLenders
//         // 3. delete index from s_borrowerLenderIds which corresponds to
//         delete s_borrowerLenderGraph[borrower][lender];
//         delete s_lenderBorrowerGraph[lender][borrower];

//         // clear the s_borrowerLenders and s_lenderBorrowers
//         uint borrowerLenderId = s_borrowerLenderIds[borrower][lender];
//         uint lenderBorrowerId = s_lenderBorrowerIds[lender][borrower];

//         s_borrowerLenders[borrower][borrowerLenderId] = s_borrowerLenders[
//             borrower
//         ][s_borrowerLenders[borrower].length - 1];
//         s_borrowerLenders[borrower].pop();

//         delete s_borrowerLenderIds[borrower][lender];

//         s_lenderBorrowers[lender][lenderBorrowerId] = s_lenderBorrowers[lender][
//             s_lenderBorrowers[lender].length - 1
//         ];
//         s_lenderBorrowers[lender].pop();

//         delete s_lenderBorrowerIds[lender][borrower];
//     }

//     function pruneBideractionalEdge(address node_a, address node_b) {

//     }

//     function resetEdgeAmount(
//         address borrower,
//         address lender,
//         uint newAmount
//     ) public {
//         if (newAmount == 0) {
//             pruneEdge(borrower, lender);
//         }

//         if (s_borrowerLenderGraph[lender][borrower] > 0) {
//             // prune bideractional edge
//         }

//         s_borrowerLenderGraph[borrower][lender] = newAmount;
//         s_borrowerLenderIds[borrower].push(lender);

//         s_lenderBorrowerGraph[lender][borrower] = newAmount;
//         s_lenderBorrowerIds[lender].push(borrower);
//     }

//     function processTriplet(
//         address borrower,
//         address lender,
//         address lendersLender
//     ) public {
//         uint costDiff = s_borrowerLenderGraph[borrower][lender] -
//             s_borrowerLenderGraph[lender][lendersLender];
//         if (costDiff >= 0) {

//         } else {

//         }
//     }

//     function collapseGraph() public {
//         // bool[] visited = new bool[](participants.length); // should be all false
//         // __build_graph and flipped_graph
//         //
//         bool graphPruned = true;

//         buildGraphs();

//         while (graphPruned) {
//             graphPruned = false;

//             // Pick a potential lender from the list of nodes
//             for (uint lenderId = 0; lenderId < s_borrowers.length; lenderId++) {
//                 for (
//                     uint borrowerId = 0;
//                     borrowerId < s_lenderBorrowers[s_borrowers[lenderId]].length;
//                     borrowerId++
//                 ) {
//                     if (s_borrowerLenders[lenderId].length > 0) {
//                         address lenderAddress = s_borrowers[lenderId];
//                         address borrowerAddress = s_lenderBorrowers[lenderId][
//                             borrowerId
//                         ];
//                         address lendersLenderAddress = s_borrowerLenders[
//                             lenderId
//                         ][s_borrowerLenders[lenderId].length - 1]; // pick the very last lenders lender
//                         break;
//                     }
//                 }
//             }
//         }
//         // for (uint i = 0; i < expenses2.length; i++) {
//         //     if (!s_graph[expenses[i].lender.destNodes && s_graph[expenses[i].lender].visit) {
//         //         // try to spend (borrower => lender) amount by eliminating other
//         //     }
//         //     s_graph[expenses[i].borrower].destNodeCost
//         // }
//         // build a graph
//         // mapping(borrower => (lender, amount)) where borrower and lender are nodes of the graph
//         // and amount is the weight
//     }
// }

library Expenses {
    struct Expense {
        address lender; // who funds will be transfered to (msg.sender, aka owner of the expense)
        address borrower; // who funds will be deducted from
        uint256 amount;
    }

    struct ExpenseBody {
        address borrower;
        uint256 amount;
    }

    struct DestinationNode {
        address destinationNode;
        uint256 cost;
    }
}
