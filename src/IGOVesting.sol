// SPDX-License-Identifier: MIT
//** DCB vesting Contract */

pragma solidity ^0.8.17;

import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IIGOVesting} from "./interfaces/IIGOVesting.sol";

/**
 * @title IGOVesting
 * @dev This contract manages the vesting of tokens, whitelist functionality, and other related features for crowdfunding.
 */
contract IGOVesting is IIGOVesting, AccessControlUpgradeable {
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
    address public paymentReceiver;
    uint256 public platformFee;
    uint256 public decimals;

    IERC20Upgradeable public vestedToken;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant INNOVATOR_ROLE = keccak256("INNOVATOR_ROLE");

    modifier userInWhitelist(address _wallet) {
        require(vestingPool.hasWhitelist[_wallet].active, "Not in whitelist");
        _;
    }

    /**
     * @dev Initializes the crowdfunding and vesting contract with the provided configuration.
     * @param c ContractSetup struct containing crowdfunding setup parameters.
     * @param p VestingSetup struct containing vesting strategy parameters.
     */
    function initializeCrowdfunding(
        ContractSetup calldata c,
        VestingSetup calldata p
    ) external override initializer {
        __AccessControl_init();

        paymentReceiver = c._paymentReceiver;
        vestedToken = IERC20Upgradeable(c._vestedToken);
        gracePeriod = c._gracePeriod;
        totalTokenOnSale = c._totalTokenOnSale;
        platformFee = c._platformFee;
        decimals = c._decimals;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(INNOVATOR_ROLE, c._innovator);
        _setRoleAdmin(INNOVATOR_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, c._admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);

        _addVestingStrategy(
            p._cliff,
            p._startTime,
            p._duration,
            p._initialUnlockPercent
        );

        emit CrowdfundingInitialized(c, p);
    }

    /**
     * @dev Sets the vesting start time.
     * @param _newStart New vesting start time (in seconds since the epoch).
     */
    function setVestingStartTime(
        uint32 _newStart
    ) external override onlyRole(ADMIN_ROLE) {
        require(
            block.timestamp < vestingPool.start,
            "Vesting already started"
        );
        uint32 cliff = vestingPool.cliff - vestingPool.start;
        vestingPool.start = _newStart;
        vestingPool.cliff = _newStart + cliff;

        emit SetVestingStartTime(_newStart);
    }

    /**
     * @dev Sets the token contract address.
     * @param _token Address of the new token contract.
     */
    function setToken(address _token) external override onlyRole(ADMIN_ROLE) {
        require(_token != address(0), "Invalid token");
        require(
            block.timestamp < vestingPool.start,
            "Vesting already started"
        );
        vestedToken = IERC20Upgradeable(_token);
        emit SetToken(_token);
    }

    /**
     * @dev Initiates a refund for a user.
     * @param _tagId Identifier for the user's refund tag.
     */
    function refund(
        string calldata _tagId
    ) external override userInWhitelist(msg.sender) {
        _refund(msg.sender, _tagId);
    }

    /**
     * @dev Claims the raised funds from the crowdfunding for a specific payment token.
     * @param _paymentToken Address of the payment token used to raise funds.
     */
    function claimRaisedFunds(
        address _paymentToken
    ) external override onlyRole(INNOVATOR_ROLE) {
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

        // amount of project tokens to return = amount not sold + amount refunded
        uint256 amountTokenToReturn = totalReturnedToken;

        // transfer payment + refunded tokens to project
        if (amountTokenToReturn > 0) {
            totalReturnedToken = 0;
            vestedToken.safeTransfer(msg.sender, amountTokenToReturn);
        }

        // calculate fee
        if (platformFee > 0) {
            uint256 fee = (amountPayment * platformFee) / decimals;
            amountPayment -= fee;
            IERC20Upgradeable(_paymentToken).safeTransfer(
                paymentReceiver,
                fee
            );
        }

        if (amountPayment > 0) {
            IERC20Upgradeable(_paymentToken).safeTransfer(
                msg.sender,
                amountPayment
            );
        }

        emit RaisedFundsClaimed(amountPayment, amountTokenToReturn);
    }

    /**
     * @dev Claims the distributed vested tokens for the caller.
     * @return A boolean indicating success and the amount of vested tokens claimed.
     */
    function claimDistribution() external override returns (bool, uint256) {
        uint256 releaseAmount = _updateStorageOnDistribution(msg.sender);

        emit Claim(msg.sender, releaseAmount, block.timestamp);

        vestedToken.safeTransfer(msg.sender, releaseAmount);

        return (true, releaseAmount);
    }

    /**
     * @dev Sets the whitelist status for a user's wallet and payment details.
     * Only the contract owner can call this function.
     * @param _tagId Identifier for the user's refund tag.
     * @param _wallet Address of the user's wallet.
     * @param _paymentAmount Payment amount in the payment token.
     * @param _paymentToken Address of the payment token.
     * @param _tokenAmount Amount of tokens to be vested.
     * @param _refundFee Refund fee in percentage.
     */
    function setCrowdfundingWhitelist(
        string calldata _tagId,
        address _wallet,
        uint256 _paymentAmount,
        address _paymentToken,
        uint256 _tokenAmount,
        uint256 _refundFee
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
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

    /**
     * @dev Retrieves the whitelist information for a specific wallet address.
     * @param _wallet Address of the wallet for which whitelist information is requested.
     * @return WhitelistInfo struct containing whitelist details.
     */
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

    /**
     * @dev Checks if a wallet address is in the whitelist.
     * @param _wallet Address to check for whitelist status.
     * @return true if the address is in the whitelist, otherwise false.
     */
    function hasWhitelist(
        address _wallet
    ) external view override returns (bool) {
        return vestingPool.hasWhitelist[_wallet].active;
    }

    /**
     * @dev Retrieves the vested amount for a specific wallet address.
     * @param _wallet Address of the wallet for which vested amount is requested.
     * @return Vested token amount for the wallet.
     */
    function getVestAmount(
        address _wallet
    ) external view override returns (uint256) {
        return _calculateVestAmount(_wallet);
    }

    /**
     * @dev Retrieves the releasable vested amount for a specific wallet address.
     * @param _wallet Address of the wallet for which releasable amount is requested.
     * @return Releasable vested token amount for the wallet.
     */
    function getReleasableAmount(
        address _wallet
    ) external view override returns (uint256) {
        return _calculateReleasableAmount(_wallet);
    }

    /**
     * @dev Retrieves a batch of whitelist information starting from a specific index.
     * @param start Index to start retrieving whitelist information.
     * @param count Number of whitelist entries to retrieve.
     * @return Array of WhitelistInfo structs containing whitelist details.
     */
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

    /**
     * @dev Retrieves the vesting strategy details.
     * @return VestingInfo struct containing vesting strategy parameters.
     */
    function getVestingInfo()
        external
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

    /**
     * @dev Transfers ownership of the contract to a new owner.
     * @param newOwner Address of the new owner.
     */
    function transferOwnership(
        address newOwner
    ) public virtual override(IIGOVesting) onlyRole(DEFAULT_ADMIN_ROLE) {
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
    }

    /**
     * @dev Adds a vesting strategy to the contract.
     * @param _cliff Duration (in seconds) of the cliff.
     * @param _start Start time (in seconds since the epoch) for vesting.
     * @param _duration Total duration (in seconds) of the vesting schedule.
     * @param _initialUnlockPercent Percentage of tokens initially unlocked.
     */
    function _addVestingStrategy(
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

    /**
     * @dev Initiates the refund process for a user's wallet based on a refund tag.
     * @param wallet Address of the wallet to be refunded.
     * @param _tagId Identifier for the user's refund tag.
     */
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

    /**
     * @dev Updates storage and claims vested tokens for a user's wallet.
     * @param _wallet Address of the wallet to claim vested tokens for.
     * @return releaseAmount Amount of vested tokens claimed.
     */
    function _updateStorageOnDistribution(
        address _wallet
    ) internal returns (uint256 releaseAmount) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        WhitelistInfo storage whitelist = vestingPool.whitelistPool[idx];

        require(whitelist.amount != 0, "user already refunded");

        releaseAmount = _calculateReleasableAmount(_wallet);

        require(releaseAmount > 0, "Zero amount");

        whitelist.distributedAmount =
            whitelist.distributedAmount +
            releaseAmount;
    }

    /**
     * @dev Calculates the vested token amount for a wallet based on the vesting strategy.
     * @param _wallet Address of the wallet for which vested amount is calculated.
     * @return amount Vested token amount for the wallet.
     */
    function _calculateVestAmount(
        address _wallet
    ) internal view userInWhitelist(_wallet) returns (uint256 amount) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        uint256 _amount = vestingPool.whitelistPool[idx].amount;

        if (block.timestamp < vestingPool.start) {
            return 0;
        } else if (
            block.timestamp >= vestingPool.start &&
            block.timestamp < vestingPool.cliff
        ) {
            return (_amount * vestingPool.initialUnlockPercent) / 1000;
        } else if (block.timestamp >= vestingPool.cliff) {
            return _calculateVestAmountForLinear(_amount);
        }
    }

    /**
     * @dev Calculates the vested token amount for a wallet using a linear vesting strategy.
     * @param _amount Total token amount to be vested.
     * @return Vested token amount based on linear vesting.
     */
    function _calculateVestAmountForLinear(
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 initial = (_amount * vestingPool.initialUnlockPercent) / 1000;

        uint256 remaining = _amount - initial;

        if (block.timestamp >= vestingPool.cliff + vestingPool.duration) {
            return _amount;
        } else {
            return
                initial +
                (remaining * (block.timestamp - vestingPool.cliff)) /
                vestingPool.duration;
        }
    }

    /**
     * @dev Calculates the releasable vested token amount for a wallet.
     * @param _wallet Address of the wallet for which releasable amount is calculated.
     * @return Releasable vested token amount for the wallet.
     */
    function _calculateReleasableAmount(
        address _wallet
    ) internal view userInWhitelist(_wallet) returns (uint256) {
        uint256 idx = vestingPool.hasWhitelist[_wallet].arrIdx;
        return
            _calculateVestAmount(_wallet) -
            vestingPool.whitelistPool[idx].distributedAmount;
    }
}
