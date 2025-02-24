// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/automation/AutomationCompatible.sol";


/**
 * @title A sample lottery contract
 * @author Kimchii
 * @notice This contract is for creating a simple lottery
 * @dev Implements Chainlink VRFv2.5
 */
contract Lottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    /////////////////////////////
    ///   TYPE DECLARATIONS   ///
    /////////////////////////////
    enum LotteryState {
        OPEN,
        CALCULATING,
        CLOSED
    }

    /////////////////////////////
    ///    STATE VARIABLES    ///
    /////////////////////////////
    address payable[] private s_players;
    mapping (address => string) s_playersToName;
    address private s_lastWinner;
    string private s_lastWinnerName;
    uint256 private s_lastTimestamp;
    LotteryState private s_lotteryState;
    uint256 private s_entryFee;
    uint256 private s_interval;
    bool private s_nativePayment; // True: ETH, False: LINK
    uint16 private s_requestConfirmations;
    bytes32 private s_keyHash;
    uint32 private s_subscriptionId;
    uint32 private s_callbackGasLimit;

    uint32 private constant NUM_WORDS = 1; // We only need one random number

    /////////////////////////////
    ///        EVENTS         ///
    /////////////////////////////
    event EnteredLottery(address indexed player, string indexed playerName);
    event WinnerPicked(address indexed winner, string indexed winnerName);
    event RequestedLotteryWinner(uint256 indexed requestId);

    /////////////////////////////
    ///        ERRORS         ///
    /////////////////////////////
    error Lottery__NotEnoughEth(uint256 value);
    error Lottery__LotteryNotOpen();
    error Lottery__UpkeepNotNeeded(uint256 _contractBalance, uint256 _noOfPlayers, uint256 _lotteryState);

    /////////////////////////////
    ///       FUNCTIONS       ///
    /////////////////////////////
    constructor(
            address _vrfCoordinatorAddress,
            uint256 _entryFee,
            uint256 _interval,
            bool _nativePayment,
            uint16 _requestConfirmations,
            bytes32 _keyhash,
            uint32 _subscriptionId,
            uint32 _callbackGasLimit
        ) 
        VRFConsumerBaseV2Plus(_vrfCoordinatorAddress) 
    {
        s_entryFee = _entryFee;
        s_lastTimestamp = block.timestamp;
        s_lotteryState = LotteryState.OPEN;
        s_interval = _interval;
        s_nativePayment = _nativePayment;
        s_requestConfirmations = _requestConfirmations;
        s_keyHash = _keyhash;
        s_subscriptionId = _subscriptionId;
        s_callbackGasLimit = _callbackGasLimit;
    }

    receive() external payable {
        enterLottery("anonymous");
    }

    fallback() external payable {
        enterLottery("anonymous");
    }

    function enterLottery(string memory _nameOfPlayer) public payable {
        if (msg.value != s_entryFee) {
            revert Lottery__NotEnoughEth(msg.value);
        }
        if (s_lotteryState != LotteryState.OPEN) {
            revert Lottery__LotteryNotOpen();
        }
        s_players.push(payable(msg.sender));
        s_playersToName[msg.sender] = _nameOfPlayer;

        emit EnteredLottery(msg.sender, _nameOfPlayer);
    }

    function fulfillRandomWords(uint256 /*requestId*/, uint256[] calldata randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        string memory winnerName = s_playersToName[winner];

        s_lastWinner = winner;
        s_lastWinnerName = winnerName;
        s_lotteryState = LotteryState.OPEN;
        s_players = new address payable[](0); // resetting the array
        s_lastTimestamp = block.timestamp;

        emit WinnerPicked(s_lastWinner, winnerName);
    }

    function performUpkeep(bytes calldata /* performData */) external {
        // Check if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if(!upkeepNeeded) {
            revert Lottery__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_lotteryState));
        }

        s_lotteryState = LotteryState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: s_requestConfirmations,
                callbackGasLimit: s_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: s_nativePayment}))
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedLotteryWinner(requestId);
    }

    /////////////////////////////
    ///    VIEW FUNCTIONS     ///
    /////////////////////////////
    function checkUpkeep(
        bytes memory /* checkData */
    ) 
        public 
        view 
        returns (bool upkeepNeeded, bytes memory /*performData*/) 
    {
        bool timeHasPassed = block.timestamp - s_lastTimestamp >= s_interval;
        bool isOpen = (s_lotteryState == LotteryState.OPEN);
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    function lotteryBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function whoIsOwner() public view returns (address) {
        return owner();
    }

    function entryFee() public view returns (uint256) {
        return s_entryFee;
    }

    function lotteryState() public view returns (LotteryState) {
        return s_lotteryState;
    }

    function lastWinner() public view returns (address, string memory) {
        string memory lastWinnerName = s_lastWinnerName;
        return (s_lastWinner, lastWinnerName);
    }
    
    function timeTillNextRound() public view returns (uint256) {
        if (block.timestamp < s_lastTimestamp + s_interval) {
            return (s_lastTimestamp + s_interval) - block.timestamp;
        }
        return 0;
    }

    function players(uint256 indexOfPlayer) public view returns (address) {
        return s_players[indexOfPlayer];
    }

    function playerName(address playerAddress) public view returns (string memory) {
        return s_playersToName[playerAddress];
    }

    function lotteryInterval() public view returns (uint256) {
        return s_interval;
    }

    /////////////////////////////
    ///    OWNER FUNCTIONS    ///
    /////////////////////////////
    function changeVrfCoordinator(address newVrfCoordinatorAddress) external onlyOwner {
        this.setCoordinator(newVrfCoordinatorAddress);
    }

    function transferOwner(address _to) external onlyOwner {
        transferOwnership(_to);
    }

    function closeLottery() external onlyOwner {
        s_lotteryState = LotteryState.CLOSED;
    }

    function openLottery() external onlyOwner {
        s_lotteryState = LotteryState.OPEN;
    }

    function changeEntryFee(uint256 _newEntryFee) external onlyOwner {
        s_entryFee = _newEntryFee;
    }

    function changeLotteryInterval(uint256 _newLotteryInterval) external onlyOwner {
        s_interval = _newLotteryInterval;
    }

    function changePaymentMethod(bool _paymentMethod) external onlyOwner {
        s_nativePayment = _paymentMethod;
    }

    function changeRequestConfirmations(uint16 _requestConfimations) external onlyOwner {
        s_requestConfirmations = _requestConfimations;
    }

    function changeKeyHash(bytes32 _keyHash) external onlyOwner {
        s_keyHash = _keyHash;
    }

    function changeSubscriptionId(uint32 _subId) external onlyOwner {
        s_subscriptionId = _subId;
    }

    function changeCallbackGasLimit(uint32 _callbackGasLimit) external onlyOwner {
        s_callbackGasLimit = _callbackGasLimit;
    }
}