// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {Box} from "../src/Box.sol";

contract MyGovernorTest is Test {
    GovToken token;
    TimeLock timelock;
    MyGovernor governor;
    Box box;

    uint256 public constant MIN_DELAY = 3600; // 1 hour - after a vote passes, you have 1 hour before you can enact
    uint256 public constant QUORUM_PERCENTAGE = 4; // Need 4% of voters to pass
    uint256 public constant VOTING_PERIOD = 50400; // This is how long voting lasts
    uint256 public constant VOTING_DELAY = 1; // How many blocks till a proposal vote becomes active

    address[] proposers;
    address[] executors;

    bytes[] functionCalls;
    address[] addressToCall;
    uint256[] values;

    address public constant VOTER = address(1);

    function setUp() public {
        token = new GovToken();
        token.mint(VOTER, 100e18);

        vm.prank(VOTER);
        // Delegate votes from the sender to `delegatee`.
        token.delegate(VOTER);

        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(token, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        // AccessControl, Grants `role` to `account`.
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        // Revokes `role` from `account`.
        timelock.revokeRole(adminRole, msg.sender);

        box = new Box();
        // Transfers ownership of the contract to a new account (`newOwner`). Can only be called by the current owner.
        box.transferOwnership(address(timelock));
    }

    function testCanUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        // "Ownable: caller is not the owner"
        box.store(1);
    }

    function testGovernanceUpdateBox() public {
        uint256 valueToStore = 777;
        string memory description = "store 1 in box";
        bytes memory encodedFuntionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        addressToCall.push(address(box));
        values.push(0);
        functionCalls.push(encodedFuntionCall);

        // 1. Propose to the DAO
        // hash
        uint256 proposalId = governor.propose(addressToCall, values, functionCalls, description);

        /* 
        enum ProposalState {
            Pending, 0
            Active,  1
            Canceled,  2
            Defeated,  3 
            Succeeded,  4
            Queued,  5
            Expired,  6
            Executed  7
        }
        */
        console.log(">>> Proposal State: ", uint256(governor.state(proposalId)));
        // governor.proposalSnapshot(proposalId);
        // governor.proposalDeadline(proposalId);

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log(">>> Proposal State: ", uint256(governor.state(proposalId)));

        // 2. vote
        string memory reason = "I like it";
        // 0 = Against, 1 = For, 2 = Abstain
        uint8 voteWay = 1;
        vm.prank(VOTER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console.log(">>> Proposal State: ", uint256(governor.state(proposalId)));

        // 3. Queue
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        // queue a proposal to the timelock
        governor.queue(addressToCall, values, functionCalls, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        console.log(">>> Proposal State: ", uint256(governor.state(proposalId)));

        // 4. Execute
        governor.execute(addressToCall, values, functionCalls, descriptionHash);

        console.log(">>> Proposal State: ", uint256(governor.state(proposalId)));

        assert(box.retrieve() == valueToStore);
    }
}
