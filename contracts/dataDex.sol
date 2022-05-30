//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./ItheumToken.sol";
import "./dataPack.sol";
import "./dataNFT.sol";
import "./SharedStructs.sol";


contract DataDex is Ownable, Pausable {

    uint8 public buyerFeeInPercent = 2;
    uint8 public sellerFeeInPercent = 2;

    ItheumToken public itheumToken;
    ItheumDataPack public itheumDataPack;
    ItheumDataNFT public itheumDataNFT;

    modifier whenItheumDataPackIsSet() {
        require(address(itheumDataPack) != address(0), 'ItheumDataPack contract must be set first');
        _;
    }

    modifier whenItheumDataNFTIsSet() {
        require(address(itheumDataNFT) != address(0), 'ItheumDataNFT contract must be set first');
        _;
    }

    constructor(ItheumToken _itheumToken) {
        itheumToken = _itheumToken;
    }

    function setItheumDataNFT(ItheumDataNFT _itheumDataNFT) external onlyOwner returns(bool) {
        itheumDataNFT = _itheumDataNFT;

        return true;
    }

    function setItheumDataPack(ItheumDataPack _itheumDataPack) external onlyOwner returns(bool) {
        itheumDataPack = _itheumDataPack;

        return true;
    }

    function setItheumDataPackAndDataNFT(ItheumDataPack _itheumDataPack, ItheumDataNFT _itheumDataNFT) external onlyOwner returns(bool) {
        itheumDataPack = _itheumDataPack;
        itheumDataNFT = _itheumDataNFT;

        return true;
    }

    function setBuyerFeeInPercent(uint8 _buyerFee) external onlyOwner returns(bool) {
        require(_buyerFee < 11, "Maximum buyer fee is 10%");

        buyerFeeInPercent = _buyerFee;

        return true;
    }

    function setSellerFeeInPercent(uint8 _sellerFee) external onlyOwner returns(bool) {
        require(_sellerFee < 11, "Maximum seller fee is 10%");

        sellerFeeInPercent = _sellerFee;

        return true;
    }

    function setBuyerAndSellerFeeInPercent(uint8 _buyerFee, uint8 _sellerFee) external onlyOwner returns(bool) {
        require(_buyerFee < 11, "Maximum buyer fee is 10%");
        require(_sellerFee < 11, "Maximum seller fee is 10%");

        buyerFeeInPercent = _buyerFee;
        sellerFeeInPercent = _sellerFee;

        return true;
    }

    function buyDataPack(address _from, address _to, string calldata _dataPackId) external whenItheumDataPackIsSet {
        require(!itheumDataPack.checkAccess(_dataPackId), "You already have bought this dataPack");

        address dataPackFeeTreasury = itheumToken.dataPackFeeTreasury();

        require(dataPackFeeTreasury != address(0x0), 'DataPack fee treasury isn\'t set in ITHEUM token contract');

        (address seller, , uint256 priceInItheum) = itheumDataPack.dataPacks(_dataPackId);

        require(_from == seller, "'from' is not 'seller'");

        require(seller != address(0), "You can't buy a non-existing data pack");

        (uint256 sellerFee, uint256 buyerFee) = getSellerAndBuyerFee(priceInItheum);

        // check the balance of $ITHEUM for buyer
        uint256 itheumOfBuyer = itheumToken.balanceOf(msg.sender);
        require(itheumOfBuyer >= priceInItheum + buyerFee, "You don't have sufficient ITHEUM to proceed");

        // check the allowance of $ITHEUM for this contract to spend from buyer
        uint256 allowance = itheumToken.allowance(msg.sender, address(this));
        require(allowance >= priceInItheum + buyerFee, "Allowance in ITHEUM contract is too low");

        // transfer $ITHEUM to data pack fee treasury and to seller
        itheumToken.transferFrom(msg.sender, seller, priceInItheum - sellerFee);
        itheumToken.transferFrom(msg.sender, dataPackFeeTreasury, sellerFee + buyerFee);

        itheumDataPack.buyDataPack(_dataPackId, _to, priceInItheum + buyerFee);
    }

    function buyDataNFT(address _from, address _to, uint256 _tokenId, bytes memory _data) external whenItheumDataNFTIsSet {
        require(itheumDataNFT.ownerOf(_tokenId) == _from, "'from' and 'ownerOf(tokenId)' doesn't match");

        address dataNFTFeeTreasury = itheumToken.dataNFTFeeTreasury();

        require(dataNFTFeeTreasury != address(0x0), 'DataNFT fee treasury isn\'t set in ITHEUM token contract');

        SharedStructs.DataNFT memory dataNFT = itheumDataNFT.dataNFTs(_tokenId);

        require(dataNFT.transferable, "DataNFT is currently not transferable");
        require(itheumDataNFT.getApproved(_tokenId) == address(this), "DataDex contract must be approved to transfer the NFT");

        uint256 priceInItheum = dataNFT.priceInItheum;
        uint256 royaltyInItheum = priceInItheum * dataNFT.royaltyInPercent / 100;

        (uint256 sellerFee, uint256 buyerFee) = getSellerAndBuyerFee(priceInItheum);

        // check the balance of $ITHEUM for buyer
        uint256 balance = itheumToken.balanceOf(msg.sender);
        require(balance >= priceInItheum + royaltyInItheum + buyerFee, "You don't have sufficient ITHEUM to proceed");

        // check the allowance of $ITHEUM for this contract to spend from buyer
        uint256 allowance = itheumToken.allowance(msg.sender, address(this));
        require(allowance >= priceInItheum + royaltyInItheum + buyerFee, "Allowance in ITHEUM contract is too low");

        // transfer $ITHEUM to data nft fee treasury, owner and to creator
        itheumToken.transferFrom(msg.sender, dataNFTFeeTreasury, sellerFee + buyerFee);
        itheumToken.transferFrom(msg.sender, _from, priceInItheum - sellerFee);
        itheumToken.transferFrom(msg.sender, dataNFT.creator, royaltyInItheum);

        itheumDataNFT.buyDataNFT(_tokenId, _to, priceInItheum, royaltyInItheum, _data);
    }

    function getSellerAndBuyerFee(uint256 _priceInItheum) view internal returns(uint256 sellerFee, uint256 buyerFee) {
        sellerFee = _priceInItheum * sellerFeeInPercent / 100;
        buyerFee = _priceInItheum * buyerFeeInPercent / 100;
    }
}