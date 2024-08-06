import { Web3 } from "web3";
require("dotenv").config();
import groupbillFactoryContract from "../out/GroupBillFactory.sol/GroupBillFactory.json";
import groupBillContractFile from "../out/GroupBill.sol/GroupBill.json";

const web3 = new Web3(process.env.RPC_URL);
const factoryContractId: string = process.env.GROUP_BILL_FACTORY_CONRACT_ID;

function subscribe() {
    const factoryContract = new web3.eth.Contract(groupbillFactoryContract.abi, factoryContractId);

    const factorySub = factoryContract.events.GroupBillCreation();
    const groupBillSub = factoryContract.events.ExpensePruningRequested();

    factorySub.on("data", (contractId) => {
        console.log(contractId);
    });
};

subscribe();