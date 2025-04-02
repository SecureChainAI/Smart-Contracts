
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract CoreTeamVesting is Ownable
{
    struct investorData
    {
        uint256 lockedAmount;
        uint256 claimedAmount;
        uint256 releasePerPeriod;
        uint256 lastClaimTime;
        uint256 releaseTime;       
    }
    uint256 public releasePeriod = 30 days;
    mapping(address=> investorData) public investorDetails;
    uint256 public totalLocked;
    address[] public investors;

    event ClaimEV(address indexed user, uint256 indexed amount);
    event LockEV(address[] indexed user, uint256[] indexed amount);


    receive() external payable { }
    /*
        ** _investors - array of investors
        ** amounts - array of amounts to be locked for investors
    */
    function lockAmounts(address[] memory _investors, uint256[] memory amounts) external onlyOwner payable
    {
        require(_investors.length == amounts.length, "Invalid array");
        uint256 totalCoins;
        for(uint i = 0 ; i< _investors.length ; i++ )
        {
            if(investorDetails[_investors[i]].lastClaimTime == 0)
            {
                investors.push(_investors[i]);
            }
            if(investorDetails[_investors[i]].lockedAmount == 0)
            {
                investorDetails[_investors[i]].lastClaimTime = block.timestamp ;
            }
            investorDetails[_investors[i]].lockedAmount += amounts[i];
            investorDetails[_investors[i]].releaseTime = block.timestamp ;

            investorDetails[_investors[i]].releasePerPeriod += amounts[i]/ 100;           
            totalLocked += amounts[i];
            totalCoins += amounts[i];
        }
        require(totalCoins <= msg.value,"Invalid amount to lock");
        emit LockEV(investors, amounts);
    }
    function rescuLockedCoins(bool onlyUnLocked) external onlyOwner
    {
        uint256 rescueCoins = address(this).balance;
        if(onlyUnLocked){
            rescueCoins -= totalLocked;
        }
        require(rescueCoins > 0, "No coins to rescue");
        payable(msg.sender).transfer(rescueCoins);
    }
    function claim() external
    {
        require(investorDetails[msg.sender].lockedAmount > 0,"No locked coins");
        (uint256 claimableAmount, uint interval) = claimableCoins(msg.sender);
        require(claimableAmount > 0,"No coins to claim");
        require(address(this).balance >= claimableAmount,"Contract does not have enough coins");
        investorDetails[msg.sender].lockedAmount -= claimableAmount;
        if(investorDetails[msg.sender].lockedAmount == 0)
        {
            investorDetails[msg.sender].releasePerPeriod = 0;
        }
        investorDetails[msg.sender].claimedAmount += claimableAmount;
        totalLocked -= claimableAmount;
        investorDetails[msg.sender].lastClaimTime  += releasePeriod * interval; //block.timestamp;
        payable(msg.sender).transfer(claimableAmount);
        emit ClaimEV(msg.sender, claimableAmount);
    }

    function claimableCoins(address _investor) public view returns(uint256 claimableAmount, uint interval)
    {
        if(investorDetails[_investor].releaseTime <= block.timestamp && investorDetails[_investor].releasePerPeriod >=0 && investorDetails[_investor].lastClaimTime > 0 && (block.timestamp - investorDetails[_investor].lastClaimTime > releasePeriod))
        {
            
            uint256 timePeriod = block.timestamp - investorDetails[_investor].lastClaimTime;
            interval = (timePeriod/releasePeriod);
            claimableAmount = investorDetails[_investor].releasePerPeriod *  interval ;
           
            if(investorDetails[_investor].lockedAmount < claimableAmount)
            {
                claimableAmount = investorDetails[_investor].lockedAmount ;
            }
        }
    }
    function getAllInvestorInfo() external view returns(uint256 totalInvestorCount,uint256 totalLockedCoins,address[] memory, uint256[] memory)
    {
        totalInvestorCount = investors.length;
        uint256[] memory coinsArray = new uint256[](totalInvestorCount);
        for(uint i = 0 ;i < investors.length; i++)
        {
            coinsArray[i] = investorDetails[investors[i]].lockedAmount;
            totalLockedCoins += investorDetails[investors[i]].lockedAmount;
        }
        return(totalInvestorCount, totalLockedCoins, investors, coinsArray);
    }
}
