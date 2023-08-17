// SPDX-License-Identifier: MIT
//** DCB Vesting Interface */

pragma solidity ^0.8.17;

interface IIGOVesting {
    struct ContractSetup {
        address _innovator;
        address _paymentReceiver;
        address _admin;
        address _vestedToken;
        uint256 _platformFee;
        uint256 _totalTokenOnSale;
        uint256 _gracePeriod;
        uint256 _decimals;
    }

    struct VestingSetup {
        uint32 _startTime;
        uint32 _cliff;
        uint32 _duration;
        uint16 _initialUnlockPercent;
    }

    struct UserTag {
        //review: refunded should be last item in struct, after refundDate
        //actually, better to delete "refunded" and use paymentAmount => if = 0 => funds were refunded
        uint8 refunded;
        uint32 refundDate;
        uint256 paymentAmount;
        uint256 tokenAmount;
        uint256 refundFee;
    }

    struct HasWhitelist {
        uint256 arrIdx;
        bool active;
    }

    struct VestingPool {
        uint32 start;
        uint32 cliff;
        uint32 duration;
        uint16 initialUnlockPercent;
        //review: move these 2 lines to the first place
        WhitelistInfo[] whitelistPool;
        mapping(address => HasWhitelist) hasWhitelist;
    }

    struct VestingInfo {
        uint32 start;
        uint32 cliff;
        uint32 duration;
        uint16 initialUnlockPercent;
    }

    struct WhitelistInfo {
        address wallet;
        //review: joinDate should be moved to the end
        uint32 joinDate;
        uint256 amount;
        uint256 distributedAmount;
    }

    event BuybackAndBurn(uint256 amount);
    event Claim(address indexed token, uint256 amount, uint256 time);
    //review: at least one parameter should be indexed
    event CrowdfundingInitialized(ContractSetup c, VestingSetup p);
    event RaisedFundsClaimed(uint256 payment, uint256 remaining);
    event Refund(address indexed wallet, uint256 amount);
    event SetVestingStartTime(uint256 _newStart);
    event SetWhitelist(address indexed wallet, uint256 amount, uint256 value);
    //review: at least one parameter should be indexed
    event TokenClaimInitialized(address _token, VestingSetup p);
    event VestingStrategyAdded(
        uint256 _cliff,
        uint256 _start,
        uint256 _duration,
        uint256 _initialUnlockPercent
    );
    //review: indexed
    function claimDistribution(address _wallet) external returns (bool);
    //review: indexed
    function claimRaisedFunds(address _paymentToken) external;

    function admin() external view returns (address);
    
    function getReleasableAmount(
        address _wallet
    ) external view returns (uint256);

    function getTotalToken(address _addr) external view returns (uint256);

    function getVestAmount(address _wallet) external view returns (uint256);

    function getVestingInfo() external view returns (VestingInfo memory);

    function getWhitelist(
        address _wallet
    ) external view returns (WhitelistInfo memory);

    function getWhitelistPool(
        uint256 start,
        uint256 count
    ) external view returns (WhitelistInfo[] memory);

    function gracePeriod() external view returns (uint256);

    function hasWhitelist(address _wallet) external view returns (bool);

    function initializeCrowdfunding(
        ContractSetup calldata c,
        VestingSetup calldata p
    ) external;

    function refund(string calldata _tagId) external;

    function setCrowdfundingWhitelist(
        string calldata _tagId,
        address _wallet,
        uint256 _paymentAmount,
        address _paymentToken,
        uint256 _tokenAmount,
        uint256 _refundFee
    ) external;

    function setToken(address _token) external;

    function setVestingStartTime(uint32 _newStart) external;

    function transferOwnership(address _newOwner) external;

    function vestingPool()
        external
        view
        returns (
            uint32 start,
            uint32 cliff,
            uint32 duration,
            uint16 initialUnlockPercent
        );
}
