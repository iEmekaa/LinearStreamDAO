// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {StreamDAO} from "../src/StreamDAO.sol";

contract DeployStreamDAO is Script {
    function run() external returns (StreamDAO) {
        vm.startBroadcast();
        StreamDAO streamDAO = new StreamDAO();
        vm.stopBroadcast();
        return streamDAO;
    }
}
