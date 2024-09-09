// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct BorrowerAmount {
    address borrower;
    uint amount;
}

struct NamedBorrowerAmounts {
    string name;
    BorrowerAmount[] borrowerAmounts;
}

struct LenderNamedExpense {
    address lender;
    NamedBorrowerAmounts[] namedBorrowerAmounts;
}

struct Expense {
    address lender; // who funds will be transfered to (msg.sender, aka owner of the expense)
    address borrower; // who funds will be deducted from
    uint256 amount;
}

struct LenderAmount {
    address lender;
    uint amount;
}

struct PostPruningBorrowerExpense {
    address borrower;
    uint totalAmount;
    LenderAmount[] lenderAmounts;
}

struct PostPruningTotalAmount {
    uint totalAmount;
    LenderAmount[] lenderAmounts;
}
