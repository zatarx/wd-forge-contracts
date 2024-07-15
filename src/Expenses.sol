// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library Expenses {
    struct Expense {
        address lender; // who funds will be transfered to (msg.sender, aka owner of the expense)
        address borrower; // who funds will be deducted from
        uint256 amount;
        address token;
    }

    struct ExpenseBody {
        address borrower;
        uint256 amount;
        address token;
    }
}