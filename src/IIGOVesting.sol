// SPDX-License-Identifier: MIT
//** DCB Vesting Interface */

pragma solidity ^0.8.17;

interface IIGOVesting {
    struct VestingInfo {
        uint32 start;
        uint32 cliff;
        uint32 duration;
        uint16 initialUnlockPercent;
    }

    struct VestingPool {
        uint32 start;
        uint32 cliff;
        uint32 duration;
        uint16 initialUnlockPercent;
        WhitelistInfo[] whitelistPool;
        mapping(address => HasWhitelist) hasWhitelist;
    }

    /**
     *
     * @dev WhiteInfo is the struct type which store whitelist information
     *
     */
    struct WhitelistInfo {
        uint8 refunded;
        address wallet;
        uint32 joinDate;
        uint32 refundDate;
        uint256 amount;
        uint256 distributedAmount;
        uint256 value; // price * amount in decimals of payment token
    }

    struct HasWhitelist {
        uint256 arrIdx;
        bool active;
    }

    struct ContractSetup {
        address _innovator;
        address _paymentReceiver;
        address _vestedToken;
        address _paymentToken;
        address _tiers;
        uint256 _totalTokenOnSale;
        uint256 _gracePeriod;
    }

    struct VestingSetup {
        uint32 _startTime;
        uint32 _cliff;
        uint32 _duration;
        uint16 _initialUnlockPercent;
    }

    struct BuybackSetup {
        address router;
        address[] path;
    }

    event Claim(address indexed token, uint256 amount, uint256 time);

    event SetWhitelist(address indexed wallet, uint256 amount, uint256 value);

    event Refund(address indexed wallet, uint256 amount);

    function initializeCrowdfunding(
        ContractSetup memory c,
        VestingSetup memory p
    ) external;

    function setToken(address _token) external;

    function setCrowdfundingWhitelist(
        address _wallet,
        uint256 _amount,
        uint256 _value
    ) external;

    function claimDistribution(address _wallet) external returns (bool);

    function getWhitelist(
        address _wallet
    ) external view returns (WhitelistInfo memory);

    function getWhitelistPool(
        uint256 start,
        uint256 count
    ) external view returns (WhitelistInfo[] memory);

    function transferOwnership(address _newOwner) external;

    function setVestingStartTime(uint32 _newStart) external;

    function getVestAmount(address _wallet) external view returns (uint256);

    function getReleasableAmount(
        address _wallet
    ) external view returns (uint256);

    function getVestingInfo() external view returns (VestingInfo memory);
}
