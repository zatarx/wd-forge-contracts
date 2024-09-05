// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct GroupExpenseItemV2 {
    address borrower;
    uint amount;
}

struct NamedGroupExpensesV2 {
    string name;
    GroupExpenseItemV2[] groupExpenses;
}

struct LenderGroupExpensesV2 {
    address lender;
    NamedGroupExpensesV2[] namedGroupExpenses;
}
