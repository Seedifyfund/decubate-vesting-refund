// SPDX-License-Identifier: MIT
//** DCB vesting Contract */

pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";

import {IIGOVesting} from "./interfaces/IIGOVesting.sol";

contract IGOVesting is Ownable, Initializable, IIGOVesting {
    //review: don't use SafeMath (since 0.8.0) - all operation is already with in-build overflow/underflow check

    //response: Fixed
    using SafeERC20 for IERC20;

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

    IERC20 public vestedToken;
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
        //review: should be added checks about correctnes of data:
        //1. innovatore shouldn't be a zero address
        //2. paymentReceiver shouldn't be a zero address
        //3. admin shouldn't be a zero address;
        //4. vested token shouldn't be a zero address
        //5. cliff shoudn't be more than 2 years (check with Sungur&Serhat)
        //6. duration shoudn't be more than 7 days (check with Sungur&Serhat)
        //7. check unlock percent not more than 100% (10^decimals)
        //8. initialUnlockPercent shouldn't be more than 100% (1000)

        //response: The entrypoint to this function is in IGO contract and I believe all necessary
        //checks are done there. IGO contract is the only contract that can call this function.
        innovator = c._innovator;
        paymentReceiver = c._paymentReceiver;
        admin = c._admin;
        vestedToken = IERC20(c._vestedToken);
        gracePeriod = c._gracePeriod;
        totalTokenOnSale = c._totalTokenOnSale;
        platformFee = c._platformFee;
        //review: what is decimals? Can it be read from vestedToken?

        //response: Decimal point used for calculating fees.
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
        //review: why we need returns if nobody checks result?

        //response: Agreed. Removing the return value.

        //review: unchecked{} can be used if we have diaposon check early

        //response: Unnecessary as the impact in gas savings is negligible.
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
        //review: move after vestingPool.start == ...
        //and add unchecked{} because by defaul overflow/underflow can't happen

        //response: Didn't understood what you meant by "move after vestingPool.start == ..."
        // Also, unncessary unchecked as the impact in gas savings is negligible.
        uint32 cliff = vestingPool.cliff - vestingPool.start;
        vestingPool.start = _newStart;
        vestingPool.cliff = _newStart + cliff;

        emit SetVestingStartTime(_newStart);
    }

    function setToken(address _token) external override {
        require(msg.sender == admin, "Only admin");
        require(_token != address(0), "Invalid token");
        //review: check for non zero address

        //response: Agreed. Added the check.
        vestedToken = IERC20(_token);
    }

    function refund(
        string calldata _tagId
    ) external override userInWhitelist(msg.sender) {
        uint256 idx = vestingPool.hasWhitelist[msg.sender].arrIdx;
        WhitelistInfo storage whitelist = vestingPool.whitelistPool[idx];
        UserTag storage tag = userTag[_tagId][msg.sender];
        //review: move to the first line

        //response: Following the design pattern of keeping the requires grouped together.
        require(
            block.timestamp < vestingPool.start + gracePeriod &&
                block.timestamp > vestingPool.start,
            "Not in grace period"
        );
        require(tag.refunded == 0, "user already refunded");
        //review: move to the after WhitelistInfo storage whitlist =...

        //response: Same as above.
        require(whitelist.distributedAmount == 0, "user already claimed");

        uint256 fee = (tag.paymentAmount * tag.refundFee) / decimals;
        //review: can be used unchecked{} if we check refundFee earlier

        //response: Unnecessary as the impact in gas savings is negligible.
        uint256 refundAmount = tag.paymentAmount - fee;

        tag.refunded = 1;
        tag.refundDate = uint32(block.timestamp);
        //review: check if paymentToken[_tagId] exists
        //can be used unchecked{} for next 2 lines

        //response: Unnecessary check as the function will revert anyway while attempting to transfer
        totalRefundedValue[paymentToken[_tagId]] += tag.paymentAmount;
        totalReturnedToken += tag.tokenAmount;
        //review: are we sure that underflow can't happen here?

        //response: Yes, we are sure. The amount is calculated in the setCrowdfundingWhitelist function
        //Its always going to be <= whitelist.amount
        whitelist.amount -= tag.tokenAmount;

        // Transfer payment token to user
        IERC20(paymentToken[_tagId]).safeTransfer(msg.sender, refundAmount);
        // Send fee to payment receiver
        IERC20(paymentToken[_tagId]).safeTransfer(paymentReceiver, fee);

        emit Refund(msg.sender, refundAmount);
    }

    function transferOwnership(
        address newOwner
    ) public override(Ownable, IIGOVesting) onlyOwner {
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
        // review: Do we sure that underflow can't happen here?

        //response: Yes, as totalRefundedValue will never exceed totalRaisedValue by the
        //same logic as users cannot refund more than they have invested.
        uint256 amountPayment = totalRaisedValue[_paymentToken] -
            totalRefundedValue[_paymentToken];
        // calculate fee
        uint256 fee = (amountPayment * platformFee) / decimals;

        amountPayment -= fee;

        // amount of project tokens to return = amount not sold + amount refunded
        uint256 amountTokenToReturn = totalReturnedToken;

        // transfer payment + refunded tokens to project
        if (amountPayment > 0) {
            IERC20(_paymentToken).safeTransfer(innovator, amountPayment);
        }
        if (amountTokenToReturn > 0) {
            vestedToken.safeTransfer(innovator, amountTokenToReturn);
            totalReturnedToken = 0;
        }

        // transfer crowdfunding fee to payment receiver wallet
        if (platformFee > 0) {
            IERC20(_paymentToken).safeTransfer(paymentReceiver, fee);
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

    //review: very unusual function - what sence here?
    //why we need to pass _addr?

    //response: Agreed. This was needed in the FE at some point, but
    //not anymore. Removed the function.

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
        //review: should be max(arraySize(vestingPool.whitelistPool) - start + 1, count)

        //response: Agreed. Changed the code accordingly.
        unchecked {
            uint256 len = count > vestingPool.whitelistPool.length - start
                ? vestingPool.whitelistPool.length - start
                : count;
            WhitelistInfo[] memory _whitelist = new WhitelistInfo[](len);
            uint256 end = start + len;
            //review: should use arraySize of vestingPool.whitelistPool
            //also unchecked can be applied
            //also ++i costs a little bit less gas if we compare with i++
            for (uint256 i = start; i < end; ++i) {
                _whitelist[i - start] = vestingPool.whitelistPool[i];
            }
            return _whitelist;
        }
    }

    //review: _wallet doesn't need here, should be used msg.sender, otherwise somebody can claim instead of user
    //and user will lose chance to make refund

    //response: Agreed. This was a requirement when we were using an aggregator for claiming, but
    // for this usecase, it actually acts as a bug and should be removed. Removed the _wallet parameter.

    //!!!! USER CAN CLAIM ALL POOL - DECREASING OF whitelist.amount is absent !!!!

    //response: That is a misunderstanding. If you look at the code, the distributed amount is
    //modified and while calculating the releasable amount, the distributed amount is subtracted
    function claimDistribution() public override {
        //review: function doesn't return false at all, we don't need a return value here

        //response: Agreed. Removed the return value.

        uint256 idx = vestingPool.hasWhitelist[msg.sender].arrIdx;
        WhitelistInfo storage whitelist = vestingPool.whitelistPool[idx];

        require(whitelist.amount != 0, "user already refunded");

        uint256 releaseAmount = calculateReleasableAmount(msg.sender);

        require(releaseAmount > 0, "Zero amount");

        whitelist.distributedAmount =
            whitelist.distributedAmount +
            releaseAmount;

        vestedToken.safeTransfer(msg.sender, releaseAmount);

        emit Claim(msg.sender, releaseAmount, block.timestamp);
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
}
