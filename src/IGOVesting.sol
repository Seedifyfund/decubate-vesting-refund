// SPDX-License-Identifier: MIT
//** DCB vesting Contract */

pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "openzeppelin-contracts/utils/math/SafeMath.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";

import {IIGOVesting} from "./IIGOVesting.sol";

contract IGOVesting is Ownable, Initializable, IIGOVesting {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    VestingPool public vestingPool;

    // refund total values
    uint256 public totalVestedValue;
    uint256 public totalRefundedValue;
    uint256 public totalVestedToken;
    uint256 public totalReturnedToken;
    uint256 public totalTokenOnSale;

    uint256 public gracePeriod;
    address public innovator;
    address public paymentReceiver;
    bool public claimed;

    IERC20 public vestedToken;
    IERC20 public paymentToken;
    address public factory;

    event CrowdfundingInitialized(ContractSetup c, VestingSetup p);
    event TokenClaimInitialized(address _token, VestingSetup p);
    event VestingStrategyAdded(
        uint256 _cliff,
        uint256 _start,
        uint256 _duration,
        uint256 _initialUnlockPercent
    );
    event RaisedFundsClaimed(uint256 payment, uint256 remaining);
    event BuybackAndBurn(uint256 amount);
    event SetVestingStartTime(uint256 _newStart);

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
    ) external initializer {
        innovator = c._innovator;
        paymentReceiver = c._paymentReceiver;
        vestedToken = IERC20(c._vestedToken);
        paymentToken = IERC20(c._paymentToken);
        gracePeriod = c._gracePeriod;
        totalTokenOnSale = c._totalTokenOnSale;

        _transferOwnership(msg.sender);
        factory = msg.sender;

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
    ) internal returns (bool) {
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
        return true;
    }

    function setVestingStartTime(uint32 _newStart) external {
        require(msg.sender == factory, "Only factory");
        uint32 cliff = vestingPool.cliff - vestingPool.start;
        vestingPool.start = _newStart;
        vestingPool.cliff = _newStart + cliff;

        emit SetVestingStartTime(_newStart);
    }

    function setToken(address _token) external {
        require(msg.sender == factory, "Only factory");
        vestedToken = IERC20(_token);
    }

    function refund() external userInWhitelist(msg.sender) {
        uint256 idx = vestingPool.hasWhitelist[msg.sender].arrIdx;
        WhitelistInfo storage whitelist = vestingPool.whitelistPool[idx];

        require(
            block.timestamp < vestingPool.start + gracePeriod &&
                block.timestamp > vestingPool.start,
            "Not in grace period"
        );
        require(whitelist.refunded == 0, "user already refunded");
        require(whitelist.distributedAmount == 0, "user already claimed");

        // (, uint256 tier, uint256 multi) = tiers.getTierOfUser(msg.sender);
        // (,, uint256 refundFee) = tiers.tierInfo(tier);

        // if (multi > 1) {
        //     uint256 multiReduction = (multi - 1) * 50;
        //     refundFee = refundFee > multiReduction ? refundFee - multiReduction : 0;
        // }

        // uint256 fee = whitelist.value * refundFee / 10_000;
        uint256 refundAmount = whitelist.value; // - fee;

        whitelist.refunded = 1;
        whitelist.refundDate = uint32(block.timestamp);
        totalRefundedValue += whitelist.value;
        totalReturnedToken += whitelist.amount;

        // Transfer BUSD to user sub some percent of fee
        paymentToken.safeTransfer(msg.sender, refundAmount);

        emit Refund(msg.sender, refundAmount);
    }

    function transferOwnership(
        address newOwner
    ) public override(Ownable, IIGOVesting) onlyOwner {
        super.transferOwnership(newOwner);
    }

    function claimRaisedFunds() external onlyInnovator {
        require(
            block.timestamp > gracePeriod + vestingPool.start,
            "grace period in progress"
        );
        require(!claimed, "already claimed");

        // payment amount = total value - total refunded
        uint256 amountPayment = totalVestedValue - totalRefundedValue;
        // calculate fee of 5%
        uint256 platformFee = (amountPayment * 5) / 100;

        amountPayment -= platformFee;

        // amount of project tokens to return = amount not sold + amount refunded
        uint256 amountTokenToReturn = totalTokenOnSale -
            totalVestedToken +
            totalReturnedToken;

        claimed = true;

        // transfer payment + refunded tokens to project
        if (amountPayment > 0) {
            paymentToken.safeTransfer(innovator, amountPayment);
        }
        if (amountTokenToReturn > 0) {
            vestedToken.safeTransfer(innovator, amountTokenToReturn);
        }

        // transfer crowdfunding fee to payment receiver wallet
        if (platformFee > 0) {
            paymentToken.safeTransfer(paymentReceiver, platformFee);
        }

        emit RaisedFundsClaimed(amountPayment, amountTokenToReturn);
    }

    function getWhitelist(
        address _wallet
    ) external view userInWhitelist(_wallet) returns (WhitelistInfo memory) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        return vestingPool.whitelistPool[idx];
    }

    function getTotalToken(address _addr) external view returns (uint256) {
        IERC20 _token = IERC20(_addr);
        return _token.balanceOf(address(this));
    }

    function hasWhitelist(address _wallet) external view returns (bool) {
        return vestingPool.hasWhitelist[_wallet].active;
    }

    function getVestAmount(address _wallet) external view returns (uint256) {
        return calculateVestAmount(_wallet);
    }

    function getReleasableAmount(
        address _wallet
    ) external view returns (uint256) {
        return calculateReleasableAmount(_wallet);
    }

    function getWhitelistPool(
        uint256 start,
        uint256 count
    ) external view returns (WhitelistInfo[] memory) {
        WhitelistInfo[] memory _whitelist = new WhitelistInfo[](count);
        uint256 end = start + count;
        for (uint256 i = start; i < end; i++) {
            _whitelist[i - start] = vestingPool.whitelistPool[i];
        }
        return _whitelist;
    }

    function claimDistribution(address _wallet) public returns (bool) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        WhitelistInfo storage whitelist = vestingPool.whitelistPool[idx];

        require(whitelist.refunded == 0, "user already refunded");

        uint256 releaseAmount = calculateReleasableAmount(_wallet);

        require(releaseAmount > 0, "Zero amount");

        whitelist.distributedAmount = whitelist.distributedAmount.add(
            releaseAmount
        );

        vestedToken.safeTransfer(_wallet, releaseAmount);

        emit Claim(_wallet, releaseAmount, block.timestamp);

        return true;
    }

    function setCrowdfundingWhitelist(
        address _wallet,
        uint256 _tokenAmount,
        uint256 _paymentAmount
    ) public onlyOwner {
        uint256 paymentAmount = !vestingPool.hasWhitelist[_wallet].active
            ? _paymentAmount
            : _paymentAmount -
                vestingPool
                    .whitelistPool[vestingPool.hasWhitelist[_wallet].arrIdx]
                    .value;
        paymentToken.safeTransferFrom(_wallet, address(this), paymentAmount);
        _setWhitelist(_wallet, _tokenAmount, _paymentAmount);
    }

    function _setWhitelist(
        address _wallet,
        uint256 _amount,
        uint256 _value
    ) internal {
        HasWhitelist storage whitelist = vestingPool.hasWhitelist[_wallet];

        if (!whitelist.active) {
            whitelist.active = true;
            whitelist.arrIdx = vestingPool.whitelistPool.length;

            vestingPool.whitelistPool.push(
                WhitelistInfo({
                    wallet: _wallet,
                    amount: _amount,
                    distributedAmount: 0,
                    value: _value,
                    joinDate: uint32(block.timestamp),
                    refundDate: 0,
                    refunded: 0
                })
            );

            totalVestedValue += _value;
            totalVestedToken += _amount;
        } else {
            WhitelistInfo storage w = vestingPool.whitelistPool[
                whitelist.arrIdx
            ];

            totalVestedValue += _value - w.value;
            totalVestedToken += _amount - w.amount;

            w.amount = _amount;
            w.value = _value;
        }

        emit SetWhitelist(_wallet, _amount, _value);
    }

    function getVestingInfo() public view returns (VestingInfo memory) {
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
        uint256 initial = _amount.mul(vest.initialUnlockPercent).div(1000);

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
        uint256 initial = _amount.mul(vest.initialUnlockPercent).div(1000);

        uint256 remaining = _amount.sub(initial);

        if (block.timestamp >= vest.cliff + vest.duration) {
            return _amount;
        } else {
            return
                initial +
                remaining.mul(block.timestamp.sub(vest.cliff)).div(
                    vest.duration
                );
        }
    }

    function calculateReleasableAmount(
        address _wallet
    ) internal view userInWhitelist(_wallet) returns (uint256) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        return
            calculateVestAmount(_wallet).sub(
                vestingPool.whitelistPool[idx].distributedAmount
            );
    }
}
