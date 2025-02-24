// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DepolyLottery is Script {
    uint16 public constant REQUEST_CONFIMATIONS = 5;
    bool public constant NATIVE_PAYMENT = false;

    function run() external {
        deployContract();
    }

    function deployContract() public returns (Lottery, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        
        if (config.subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subscriptionId, ) = createSubscription.createSubscription(config.vrfCoordinator, config.account);

            // fund the subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        }
        
        vm.startBroadcast(config.account);
        Lottery lottery = new Lottery(
            config.vrfCoordinator,
            config.entryFee,
            config.interval,
            NATIVE_PAYMENT,
            REQUEST_CONFIMATIONS,
            config.gasLane,
            uint32(config.subscriptionId),
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(lottery), config.vrfCoordinator, config.subscriptionId, config.account);

        return (lottery, helperConfig);
    }
}