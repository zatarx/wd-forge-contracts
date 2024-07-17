// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

    struct NodeWrapper {
        bool visited;
        address[] destNodes;
        mapping(address => uint256) destNodeCost;
    }

    function simplify(
        mapping(address => NodeWrapper) storage s_graph,  // empty graph reference
        Expenses.Expense[] storage expenses,
        address[] storage participants
    ) 
        public 
        pure 
    {
        // bool[] visited = new bool[](participants.length); // should be all false
        // build a graph
        for (uint i = 0; i < expenses.length; i++) {
            if (!s_graph[expenses[i].lender.destNodes && s_graph[expenses[i].lender].visit) {
                // try to spend (borrower => lender) amount by eliminating other
            }
            s_graph[expenses[i].borrower].destNodeCost
        }        

        // build a graph
        // mapping(borrower => (lender, amount)) where borrower and lender are nodes of the graph
        // and amount is the weight
    }
}