interface Expense {
    borrower: string;
    lender: string;
    amount: bigint;
}


function first(iterable) {
    for (var key in iterable) {
        return key;
    }
}


class SettlementGraph {
    private expenses: Expense[];
    private borrowerLenderGraph: { [key: string]: { [key: string]: bigint } } = {};
    private lenderBorrowerGraph: { [key: string]: { [key: string]: bigint } } = {};

    constructor(expenses: Expense[]) {
        this.expenses = expenses;
        this.buildGraph();
    }

    private buildGraph() {
        for (var expense of this.expenses) {

            // Set the default values for all (borrower <-> lender) pairs
            this.borrowerLenderGraph[expense.borrower] = (
                (this.borrowerLenderGraph[expense.borrower] === undefined) ? {} : this.borrowerLenderGraph[expense.borrower]
            );
            this.borrowerLenderGraph[expense.lender] = (
                (this.borrowerLenderGraph[expense.lender] === undefined) ? {} : this.borrowerLenderGraph[expense.lender]
            );
            this.lenderBorrowerGraph[expense.borrower] = (
                (this.lenderBorrowerGraph[expense.borrower] === undefined) ? {} : this.lenderBorrowerGraph[expense.borrower]
            );
            this.lenderBorrowerGraph[expense.lender] = (
                (this.lenderBorrowerGraph[expense.lender] === undefined) ? {} : this.lenderBorrowerGraph[expense.lender]
            );

            this.borrowerLenderGraph[expense.borrower][expense.lender] = expense.amount;
            this.lenderBorrowerGraph[expense.lender][expense.borrower] = expense.amount;
        }
    }

    private pruneEdge(borrower: string, lender: string) {
        delete this.borrowerLenderGraph[borrower][lender];
        delete this.lenderBorrowerGraph[lender][borrower];
    }

    private pruneBideractionalEdge(nodeA: string, nodeB: string) {
        if (!this.borrowerLenderGraph[nodeA][nodeB] || !this.borrowerLenderGraph[nodeB][nodeA]) {
            return;
        }

        const edgeDiff: bigint = this.borrowerLenderGraph[nodeA][nodeB] - this.borrowerLenderGraph[nodeB][nodeA];
        if (edgeDiff == 0n) {
            this.pruneEdge(nodeA, nodeB);
            this.pruneEdge(nodeB, nodeA);
        } else if (edgeDiff > 0n) {
            this.pruneEdge(nodeB, nodeA);
            this.resetEdgeAmount(nodeA, nodeB, edgeDiff);
        } else {
            this.pruneEdge(nodeA, nodeB);
            this.resetEdgeAmount(nodeB, nodeA, -edgeDiff);
        }
    }

    private resetEdgeAmount(borrower: string, lender: string, newAmount: bigint) {
        if (newAmount == 0n) {
            this.pruneEdge(borrower, lender);
            return;
        }

        this.borrowerLenderGraph[borrower][lender] = newAmount;
        this.lenderBorrowerGraph[lender][borrower] = newAmount;
    }

    private rearrangeTriplet(borrower: string, lender: string, lendersLender: string) {
        const costDiff: bigint = this.borrowerLenderGraph[borrower][lender] - this.borrowerLenderGraph[lender][lendersLender];
        if (costDiff >= 0n) {
            this.resetEdgeAmount(
                borrower, lendersLender,
                (this.borrowerLenderGraph[borrower][lendersLender] || 0n) + this.borrowerLenderGraph[lender][lendersLender]
            );

            this.pruneBideractionalEdge(borrower, lendersLender);
            this.resetEdgeAmount(borrower, lender, costDiff);
            this.pruneEdge(lender, lendersLender);
        } else {
            this.resetEdgeAmount(
                borrower, lendersLender,
                (this.borrowerLenderGraph[borrower][lendersLender] || 0n) + this.borrowerLenderGraph[borrower][lender]
            );
            this.pruneBideractionalEdge(borrower, lendersLender);
            this.resetEdgeAmount(lender, lendersLender, -costDiff);
            this.pruneEdge(borrower, lender);
        }
    }

    public collapseGraph() {
        let graphPruned: Boolean = true;
        while (graphPruned) {
            graphPruned = false;

            for (var lender in this.borrowerLenderGraph) {
                const borrower = first(this.lenderBorrowerGraph[lender]);
                const lendersLender = first(this.borrowerLenderGraph[lender]);
                if (!borrower || !lendersLender) {
                    continue;
                }
                this.rearrangeTriplet(borrower, lender, lendersLender);
                graphPruned = true;
            }
        }
    }
}

import expenses from "../expenses.json";
var newExpenses: Expense[] = [];
for (var expense of expenses) {
    newExpenses.push({...expense, amount: BigInt(expense["amount"])});
}

let graph = new SettlementGraph(newExpenses);
graph.collapseGraph();
console.log(expenses);