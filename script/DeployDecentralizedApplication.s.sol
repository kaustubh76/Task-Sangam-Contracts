// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { UserManagement } from "../src/UserManagement.sol";
import { JobPosting } from "../src/JobPosting.sol";
import { ProposalManagement} from "../src/ProposalManagement.sol";
import { WorkSubmission } from "../src/WorkSubmission.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DeployWeb3Upwork is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log('deployer: ', deployerAddress);

        UserManagement userManagement = new UserManagement();
        console.log("UserManagement deployed to:", address(userManagement));

        ERC20Mock paymentToken = new ERC20Mock();

        JobPosting jobPosting = new JobPosting(address(userManagement), address(paymentToken));
        console.log("JobPosting deployed to:", address(jobPosting));

        ProposalManagement proposalManagement = new ProposalManagement(address(userManagement), address(jobPosting));
        console.log("ProposalManagement deployed to:", address(proposalManagement));

        WorkSubmission workSubmission = new WorkSubmission(address(userManagement), address(jobPosting), address(proposalManagement));
        console.log("WorkSubmission deployed to:", address(workSubmission));

        console.log("Post-deployment configuration completed");

        vm.stopBroadcast();
    }
}