pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./ERC721.sol";

contract PTP {
    error notEnoughCollateral();
    error idDoesNotExist();

    event lendingOptionCreated(uint256 newID, uint256 _wantedAmount);
    event lendingOptionDeleted(uint256 id, uint256 when);
    event lendingDeleted(uint256 id, uint256 when);
    event payment(uint256 id, uint256 when);

    uint256 nftsID;
    uint256 s_tradeID = 1;
    uint256 s_LendingOfferID = 1;
    address public owner;
    address public nftAddress;

    // mapping(uint => uint[]) private nftsId;
    mapping(uint256 => lendingOption) public lendingOffer;
    mapping(uint256 => lendingAccepted) public lendingByID;
    mapping(uint256 => uint) public lendingByNFT;

    constructor() {
        owner = msg.sender;
    }

    struct lendingOption {
        uint256 interest_O;
        uint256 timelap_O;
        uint256 paymentCount_O;
        uint256 wantedCollateral;
        uint256 amountForBorrow;
        address borrowedToken;
        address owner;
    }

    struct lendingAccepted {
        uint256 deadLine; // total deadline
        uint256 deadlineNextPayment; // deadline from the next payment
        uint256 timelap; // Time between each payment
        uint256 paymentsCount; // Time between each payment
        uint256 paymentsLeft; // Time between each payment
        uint256 paymentPerTime;
        uint256 collateral; // which collateral is using
        uint256 debt; // missing debt
        uint256 borrowedAmount; // Total Debt
        uint256 interest; // interest every payment
        address borrowedToken;
        uint256[] bothSides; // [0] == debtor || [1] == borrower
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert();
        }
        _;
    }

    function createLendingOption(
        uint256 _interest,
        uint256 _timelap,
        uint256 _paymentsCount,
        uint256 _wantedCollateral,
        uint256 amountToBorrow,
        address borrowToken
    ) public {
        if (
            _paymentsCount == 0 ||
            // _timelap < 7 days  ||
            _wantedCollateral == 0
        ) {
            revert();
        }

        IERC20 erc20 = IERC20(borrowToken);
        erc20.transferFrom(msg.sender, address(this), amountToBorrow);

        lendingOffer[s_LendingOfferID] = lendingOption(
            _interest,
            _timelap,
            _paymentsCount,
            _wantedCollateral,
            amountToBorrow,
            borrowToken,
            msg.sender
        );
        s_LendingOfferID++;

        emit lendingOptionCreated(s_LendingOfferID, _wantedCollateral);
    }

    function cancelLendingOption(uint256 lendingOfferID) public {
        if (msg.sender != lendingOffer[lendingOfferID].owner) {
            revert();
        }

        lendingOption memory lendingO = lendingOffer[lendingOfferID];
        delete lendingOffer[lendingOfferID];
        IERC20 erc20 = IERC20(lendingO.borrowedToken);
        erc20.transfer(lendingO.owner, lendingO.amountForBorrow);
        emit lendingOptionDeleted(lendingOfferID, block.timestamp);
    }

    function acceptLendingOption(uint256 lendingOfferID) public payable {
        lendingOption memory lendingO = lendingOffer[lendingOfferID];
        delete lendingOffer[lendingOfferID];

        if (msg.sender == lendingO.owner) {
            revert();
        }

        if (msg.value < lendingO.wantedCollateral) {
            revert notEnoughCollateral();
        }

        if (lendingO.paymentCount_O == 0) {
            revert idDoesNotExist();
        }
        IERC20 erc20 = IERC20(lendingO.borrowedToken);
        erc20.transfer(msg.sender, lendingO.amountForBorrow);

        for (uint256 i; i < 2; i++) {
            NFT nftContract = NFT(nftAddress);
            nftContract.mint();

            if (i == 0) {
                nftContract.transferFrom(address(this), msg.sender, nftsID);
                lendingByNFT[nftsID] = s_tradeID;
            } else {
                nftContract.transferFrom(address(this), lendingO.owner, nftsID);
                lendingByNFT[nftsID] = s_tradeID;

            }
            nftsID++;
        }

        uint256[] memory wallets = new uint256[](2);
        wallets[0] = nftsID - 2;
        wallets[1] = nftsID - 1;
        uint256 calculatedDeadLine = lendingO.timelap_O *
            lendingO.paymentCount_O;
        uint256 basePayment = lendingO.amountForBorrow /
            lendingO.paymentCount_O;
        uint256 paymentEachTime = ((100 + lendingO.interest_O) * basePayment) /
            100;
        uint256 totalPayment = lendingO.paymentCount_O * paymentEachTime;

        lendingByID[s_tradeID] = lendingAccepted(
            calculatedDeadLine,
            lendingO.timelap_O + block.timestamp,
            lendingO.timelap_O,
            lendingO.paymentCount_O,
            lendingO.paymentCount_O,
            paymentEachTime,
            msg.value,
            totalPayment,
            lendingO.amountForBorrow,
            lendingO.interest_O,
            lendingO.borrowedToken,
            wallets
        );

        s_tradeID++;
    }

    function claimCollateral(uint256 lendingOfferID) public {
        lendingAccepted memory m_lendingAccepted = lendingByID[lendingOfferID];
        NFT nftcontract = NFT(nftAddress);
        address ownerOfID = nftcontract.ownerOf(m_lendingAccepted.bothSides[1]);

        if (ownerOfID != msg.sender) {
            revert();
        }

        if (block.timestamp < m_lendingAccepted.deadlineNextPayment) {
            revert();
        }

        if (m_lendingAccepted.debt == 0) {
            revert();
        }

        delete lendingByID[lendingOfferID].debt;
        delete lendingByID[lendingOfferID].collateral;

        (bool success, ) = ownerOfID.call{value: m_lendingAccepted.collateral}(
            ""
        );

        if (!success) {
            revert();
        }
    }

    function payDebt(uint256 lendingOfferID) public {
        lendingAccepted memory m_lendingAccepted = lendingByID[lendingOfferID];
        NFT nftcontract = NFT(nftAddress);
        address ownerOfID = nftcontract.ownerOf(m_lendingAccepted.bothSides[0]);
        address borrower = nftcontract.ownerOf(m_lendingAccepted.bothSides[1]);

        if (
            ownerOfID != msg.sender ||
            m_lendingAccepted.deadlineNextPayment < block.timestamp ||
            m_lendingAccepted.paymentPerTime > m_lendingAccepted.debt
        ) {
            revert();
        }

        IERC20 erc20 = IERC20(m_lendingAccepted.borrowedToken);
        erc20.transferFrom(
            msg.sender,
            borrower,
            m_lendingAccepted.paymentPerTime
        );
        lendingByID[lendingOfferID].debt -= m_lendingAccepted.paymentPerTime;
        lendingByID[lendingOfferID].deadlineNextPayment =
            m_lendingAccepted.deadlineNextPayment +
            m_lendingAccepted.timelap;
        lendingByID[lendingOfferID].paymentsLeft--;

        if (lendingByID[lendingOfferID].debt == 0) {
            delete lendingByID[lendingOfferID].collateral;
            (bool success, ) = msg.sender.call{
                value: m_lendingAccepted.collateral
            }("");
            if (!success) {
                revert();
            }
        }

        emit payment(lendingOfferID, m_lendingAccepted.paymentPerTime);
    }

    function setERC721(address newAddress) public onlyOwner {
        nftAddress = newAddress;
    }

    function allLendingOffers() public view returns(lendingOption[] memory) {

      uint totalIds = s_LendingOfferID;
      lendingOption[] memory lendings = new lendingOption[](totalIds);

      for(uint i; i < totalIds; i++) {
       lendings[i] = lendingOffer[i];
      }

      return lendings;
    }

    function allBorrows(address addressWallet) public view returns (lendingAccepted[] memory) {
        NFT erc20 = NFT(nftAddress);
        uint[] memory ids = new uint[](6);
        uint z;

        for(uint i; i < nftsID; i++) {
          address _owner = erc20.ownerOf(i);
          if(_owner == addressWallet) {
            ids[z] = i;
            z++;
          }
        }
       lendingAccepted[] memory allLending = new lendingAccepted[](z);

        for(uint i; i < z; i++) {
        allLending[i] =  lendingByID[lendingByNFT[ids[i]]];
        }

        return allLending;

    }
}
