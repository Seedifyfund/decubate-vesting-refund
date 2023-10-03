// SPDX-License-Identifier: MIT
//** DCB vesting Contract */

pragma solidity ^0.8.17;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin-contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import {IIGOVesting} from "./interfaces/IIGOVesting.sol";

contract IGOVesting is OwnableUpgradeable, IIGOVesting {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    VestingPool public vestingPool;

    // refund total values
    mapping(address => uint256) public totalRaisedValue;
    mapping(address => uint256) public totalRefundedValue;

    mapping(string => address) public paymentToken;
    mapping(string => mapping(address => UserTag)) public userTag;

    uint256 public totalVestedToken;
    uint256 public totalReturnedToken;
    uint256 public totalTokenOnSale;

    uint256 public gracePeriod;
    address public innovator;
    address public paymentReceiver;
    uint256 public platformFee;
    uint256 public decimals;

    IERC20Upgradeable public vestedToken;
    address public admin;

    modifier onlyInnovator() {
        require(msg.sender == innovator, "Invalid access");
        _;
    }

    modifier userInWhitelist(address _wallet) {
        require(vestingPool.hasWhitelist[_wallet].active, "Not in whitelist");
        _;
    }

    function initializeCrowdfunding(
        ContractSetup calldata c,
        VestingSetup calldata p
    ) external override initializer {
        innovator = c._innovator;
        paymentReceiver = c._paymentReceiver;
        admin = c._admin;
        vestedToken = IERC20Upgradeable(c._vestedToken);
        gracePeriod = c._gracePeriod;
        totalTokenOnSale = c._totalTokenOnSale;
        platformFee = c._platformFee;
        decimals = c._decimals;

        _transferOwnership(msg.sender);
        addVestingStrategy(
            p._cliff,
            p._startTime,
            p._duration,
            p._initialUnlockPercent
        );

        emit CrowdfundingInitialized(c, p);
    }

    function addVestingStrategy(
        uint32 _cliff,
        uint32 _start,
        uint32 _duration,
        uint16 _initialUnlockPercent
    ) internal {
        vestingPool.cliff = _start + _cliff;
        vestingPool.start = _start;
        vestingPool.duration = _duration;
        vestingPool.initialUnlockPercent = _initialUnlockPercent;

        emit VestingStrategyAdded(
            _cliff,
            _start,
            _duration,
            _initialUnlockPercent
        );
    }

    function setVestingStartTime(uint32 _newStart) external override {
        require(msg.sender == admin, "Only admin");
        require(
            block.timestamp < vestingPool.start,
            "Vesting already started"
        );
        uint32 cliff = vestingPool.cliff - vestingPool.start;
        vestingPool.start = _newStart;
        vestingPool.cliff = _newStart + cliff;

        emit SetVestingStartTime(_newStart);
    }

    function setToken(address _token) external override {
        require(msg.sender == admin, "Only admin");
        require(_token != address(0), "Invalid token");
        require(
            block.timestamp < vestingPool.start,
            "Vesting already started"
        );
        vestedToken = IERC20Upgradeable(_token);
    }

    function refund(
        string calldata _tagId
    ) external override userInWhitelist(msg.sender) {
        _refund(msg.sender, _tagId);
    }

    function transferOwnership(
        address newOwner
    ) public virtual override(OwnableUpgradeable, IIGOVesting) onlyOwner {
        super.transferOwnership(newOwner);
    }

    function claimRaisedFunds(
        address _paymentToken
    ) external override onlyInnovator {
        require(
            block.timestamp > gracePeriod + vestingPool.start,
            "grace period in progress"
        );
        require(
            _paymentToken != address(vestedToken),
            "invalid payment token"
        );

        // payment amount = total value - total refunded
        uint256 amountPayment = totalRaisedValue[_paymentToken] -
            totalRefundedValue[_paymentToken];
        // calculate fee
        uint256 fee = (amountPayment * platformFee) / decimals;

        amountPayment -= fee;

        // amount of project tokens to return = amount not sold + amount refunded
        uint256 amountTokenToReturn = totalReturnedToken;

        if (amountPayment > 0) {
            IERC20Upgradeable(_paymentToken).safeTransfer(
                innovator,
                amountPayment
            );
        }

        // transfer crowdfunding fee to payment receiver wallet
        if (platformFee > 0) {
            IERC20Upgradeable(_paymentToken).safeTransfer(
                paymentReceiver,
                fee
            );
        }

        // transfer payment + refunded tokens to project
        if (amountTokenToReturn > 0) {
            totalReturnedToken = 0;
            vestedToken.safeTransfer(innovator, amountTokenToReturn);
        }

        emit RaisedFundsClaimed(amountPayment, amountTokenToReturn);
    }

    function getWhitelist(
        address _wallet
    )
        external
        view
        override
        userInWhitelist(_wallet)
        returns (WhitelistInfo memory)
    {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        return vestingPool.whitelistPool[idx];
    }

    function hasWhitelist(
        address _wallet
    ) external view override returns (bool) {
        return vestingPool.hasWhitelist[_wallet].active;
    }

    function getVestAmount(
        address _wallet
    ) external view override returns (uint256) {
        return calculateVestAmount(_wallet);
    }

    function getReleasableAmount(
        address _wallet
    ) external view override returns (uint256) {
        return calculateReleasableAmount(_wallet);
    }

    function getWhitelistPool(
        uint256 start,
        uint256 count
    ) external view override returns (WhitelistInfo[] memory) {
        unchecked {
            uint256 len = count > vestingPool.whitelistPool.length - start
                ? vestingPool.whitelistPool.length - start
                : count;
            WhitelistInfo[] memory _whitelist = new WhitelistInfo[](len);
            uint256 end = start + len;
            for (uint256 i = start; i < end; ++i) {
                _whitelist[i - start] = vestingPool.whitelistPool[i];
            }
            return _whitelist;
        }
    }

    function claimDistribution() public override returns (bool, uint256) {
        uint256 releaseAmount = _updateStorageOnDistribution(msg.sender);

        emit Claim(msg.sender, releaseAmount, block.timestamp);

        vestedToken.safeTransfer(msg.sender, releaseAmount);

        return (true, releaseAmount);
    }

    function setCrowdfundingWhitelist(
        string calldata _tagId,
        address _wallet,
        uint256 _paymentAmount,
        address _paymentToken,
        uint256 _tokenAmount,
        uint256 _refundFee
    ) public override onlyOwner {
        HasWhitelist storage whitelist = vestingPool.hasWhitelist[_wallet];
        UserTag storage uTag = userTag[_tagId][_wallet];

        //Payment token constant per tag
        if (paymentToken[_tagId] == address(0)) {
            paymentToken[_tagId] = _paymentToken;
        }

        if (!whitelist.active) {
            whitelist.active = true;
            whitelist.arrIdx = vestingPool.whitelistPool.length;

            vestingPool.whitelistPool.push(
                WhitelistInfo({
                    wallet: _wallet,
                    amount: _tokenAmount,
                    distributedAmount: 0,
                    joinDate: uint32(block.timestamp)
                })
            );
        } else {
            WhitelistInfo storage w = vestingPool.whitelistPool[
                whitelist.arrIdx
            ];

            w.amount += _tokenAmount;
        }

        totalRaisedValue[_paymentToken] += _paymentAmount;
        totalVestedToken += _tokenAmount;
        uTag.paymentAmount += _paymentAmount;
        uTag.tokenAmount += _tokenAmount;
        uTag.refundFee = _refundFee;

        emit SetWhitelist(_wallet, _tokenAmount, _paymentAmount);
    }

    function getVestingInfo()
        public
        view
        override
        returns (VestingInfo memory)
    {
        return
            VestingInfo({
                cliff: vestingPool.cliff,
                start: vestingPool.start,
                duration: vestingPool.duration,
                initialUnlockPercent: vestingPool.initialUnlockPercent
            });
    }

    function calculateVestAmount(
        address _wallet
    ) internal view userInWhitelist(_wallet) returns (uint256 amount) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        uint256 _amount = vestingPool.whitelistPool[idx].amount;
        VestingPool storage vest = vestingPool;

        // initial unlock
        uint256 initial = (_amount * vest.initialUnlockPercent) / 1000;

        if (block.timestamp < vest.start) {
            return 0;
        } else if (
            block.timestamp >= vest.start && block.timestamp < vest.cliff
        ) {
            return initial;
        } else if (block.timestamp >= vest.cliff) {
            return calculateVestAmountForLinear(_amount, vest);
        }
    }

    function calculateVestAmountForLinear(
        uint256 _amount,
        VestingPool storage vest
    ) internal view returns (uint256) {
        uint256 initial = (_amount * vest.initialUnlockPercent) / 1000;

        uint256 remaining = _amount - initial;

        if (block.timestamp >= vest.cliff + vest.duration) {
            return _amount;
        } else {
            return
                initial +
                (remaining * (block.timestamp - vest.cliff)) /
                vest.duration;
        }
    }

    function calculateReleasableAmount(
        address _wallet
    ) internal view userInWhitelist(_wallet) returns (uint256) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        return
            calculateVestAmount(_wallet) -
            vestingPool.whitelistPool[idx].distributedAmount;
    }

    function _refund(address wallet, string memory _tagId) internal {
        uint256 idx = vestingPool.hasWhitelist[wallet].arrIdx;
        WhitelistInfo storage whitelist = vestingPool.whitelistPool[idx];
        UserTag storage tag = userTag[_tagId][wallet];

        require(
            block.timestamp < vestingPool.start + gracePeriod &&
                block.timestamp > vestingPool.start,
            "Not in grace period"
        );
        require(tag.refunded == 0, "user already refunded");
        require(whitelist.distributedAmount == 0, "user already claimed");

        uint256 fee = (tag.paymentAmount * tag.refundFee) / decimals;
        uint256 refundAmount = tag.paymentAmount - fee;

        tag.refunded = 1;
        tag.refundDate = uint32(block.timestamp);
        totalRefundedValue[paymentToken[_tagId]] += tag.paymentAmount;
        totalReturnedToken += tag.tokenAmount;
        whitelist.amount -= tag.tokenAmount;

        // Transfer payment token to user
        IERC20Upgradeable(paymentToken[_tagId]).safeTransfer(
            wallet,
            refundAmount
        );
        // Send fee to payment receiver
        IERC20Upgradeable(paymentToken[_tagId]).safeTransfer(
            paymentReceiver,
            fee
        );

        emit Refund(wallet, refundAmount);
    }

    function _updateStorageOnDistribution(
        address _wallet
    ) internal returns (uint256 releaseAmount) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        WhitelistInfo storage whitelist = vestingPool.whitelistPool[idx];

        require(whitelist.amount != 0, "user already refunded");

        releaseAmount = calculateReleasableAmount(_wallet);

        require(releaseAmount > 0, "Zero amount");

        whitelist.distributedAmount =
            whitelist.distributedAmount +
            releaseAmount;
    }
}
