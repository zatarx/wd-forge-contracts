import json
from types import SimpleNamespace
from collections import defaultdict
from attrs import define, field

@define
class Expense:
    lender: str
    borrower: str
    amount: int


class mdefaultdict(dict):
    def __init__(self, *args, **kwargs):
        self.default_factory, self.assign_empty = kwargs.pop("default_factory"), kwargs.pop("assign_empty", False)
        # super().__init__(*args, **kwargs)

    def __missing__(self, key):
        # if not self.get(key):
        if self.assign_empty:
            self[key] = self.default_factory()
            return self[key]
        
        return self.default_factory()


class SettlementGraph:
    # Graph can't have zero value edges
    # Edge gets created when the valude of graph[node_a][node_b] gets incremented
    # Edge gets deleted when the value of graph[node_a][node_b] falls down to zero

    def __build_graph(self, expenses):
        graph = mdefaultdict(assign_empty=True, default_factory=lambda: mdefaultdict(default_factory=int))
        flipped_graph = mdefaultdict(assign_empty=True, default_factory=lambda: mdefaultdict(default_factory=int))
        for expense in expenses:
            graph[expense.borrower][expense.lender] += expense.amount
            flipped_graph[expense.lender][expense.borrower] = graph[expense.borrower][expense.lender]

        return graph, flipped_graph

    def __prune_edge(self, borrower, lender):
        del self.graph[borrower][lender]
        del self.flipped_graph[lender][borrower]

    def __prune_bideractional_edge(self, node_a, node_b):
        if not self.graph[node_a][node_b] or not self.graph[node_b][node_a]:
            return

        same_edge_diff = self.graph[node_a][node_b] - self.graph[node_b][node_a]

        if same_edge_diff == 0:
            self.__prune_edge(node_a, node_b)
            self.__prune_edge(node_b, node_a)
        elif same_edge_diff > 0:
            self.__prune_edge(node_b, node_a)
            self.__reset_edge_amount(node_a, node_b, same_edge_diff)
        elif same_edge_diff < 0:
            self.__prune_edge(node_a, node_b)
            self.__reset_edge_amount(node_b, node_a, abs(same_edge_diff))

    def __reset_edge_amount(self, borrower, lender, new_amount):
        if new_amount == 0:
            self.__prune_edge(borrower, lender)
            return

        self.graph[borrower][lender] = new_amount
        self.flipped_graph[lender][borrower] = new_amount

    def __process_triplet(self, borrower, lender, lenders_lender):
        # borrower: Address, lender: Address, lenders_lender: address
        cost_diff = self.graph[borrower][lender] - self.graph[lender][lenders_lender]
        if (cost_diff >= 0):
            # 1. borrower -> lenders_lender : +/=(lender -> lenders_lender) gets created
            # 2. borrower -> lender : cost_diff gets adjusted 
            # 3. lender -> lenders_lender edge gets deleted

            # Potentially creating an oppositely pointed edge
            self.__reset_edge_amount(
                borrower, lenders_lender, self.graph[borrower][lenders_lender] + self.graph[lender][lenders_lender]
            )
            self.__prune_bideractional_edge(borrower, lenders_lender)
            # self.graph[borrower][lenders_lender] += self.graph[lender][lenders_lender]
            # self.flipped_graph[lenders_lender][borrower] += self.flipped_graph[lenders_lender][lender]

            # Nerfing the existing edge
            self.__reset_edge_amount(borrower, lender, cost_diff)
            # self.graph[borrower][lender] = cost_diff
            # self.flipped_graph[lender][borrower] = cost_diff

            self.__prune_edge(lender, lenders_lender)
            # del self.graph[lender][lenders_lender]
            # del self.flipped_graph[lenders_lender][lender]

        else:
            # 1. borrower -> lenders_lender : +/=(borrower -> lender)
            # 2. lender -> lenders_lender : cost_diff
            # 3. borrower -> lender gets deleted
            
            # Potentially creating an oppositely pointed edge
            self.__reset_edge_amount(
                borrower, lenders_lender, self.graph[borrower][lenders_lender] + self.graph[borrower][lender]
            )

            self.__prune_bideractional_edge(borrower, lenders_lender)

            # Nerfing the existing edge
            self.__reset_edge_amount(lender, lenders_lender, abs(cost_diff))
            # self.graph[lender][lenders_lender] = abs(cost_diff)
            # self.flipped_graph[lenders_lender][lender] = abs(cost_diff)

            self.__prune_edge(borrower, lender)
            # del self.graph[borrower][lender]
            # del self.flipped_graph[lender][borrower]
        
    def traverse(self, borrower_address):
        # borrower: address -> ({lender: [lender's_lender...]})
        graph_pruned = True
        while graph_pruned:

            graph_pruned = False
            nodes = list(self.graph.keys())
            for lender in (lender for lender in nodes if self.graph[lender].keys()):
                if borrower := next(iter(self.flipped_graph[lender].keys()), None):
                    self.__process_triplet(borrower=borrower, lender=lender, lenders_lender=list(self.graph[lender].keys())[0])
                    graph_pruned = True
        
        return self.graph
           
    def __init__(self, expenses):
        self.graph, self.flipped_graph = self.__build_graph(expenses)
        result = self.traverse(list(self.graph.keys())[0])


def main():
    with open("poc/expenses.json", "r") as expenses_fp:
        expenses = [Expense(**item) for item in json.load(expenses_fp)]

    graph = SettlementGraph(expenses)
    pruned_graph = graph.traverse()
    print(pruned_graph)


if __name__ == "__main__":
    main()

    # Looks good, solution is in the flipped graph (it considers loose droopy nodes as well)