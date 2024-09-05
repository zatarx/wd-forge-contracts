// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct GroupExpenseItem {
    address borrower;
    uint amount;
}

struct NamedGroupExpenses {
    string name;
    GroupExpenseItem[] groupExpenses;
}

struct LenderGroupExpenses {
    address lender;
    NamedGroupExpenses[] namedGroupExpenses;
}

struct Expense {
    address lender; // who funds will be transfered to (msg.sender, aka owner of the expense)
    address borrower; // who funds will be deducted from
    uint256 amount;
}