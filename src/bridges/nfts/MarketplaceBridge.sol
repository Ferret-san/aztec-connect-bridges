// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LSSVMRouter} from "lssvm/LSSVMRouter.sol";
import {LSSVMPair} from "lssvm/LSSVMPair.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

/**
 * @title An example bridge contract.
 * @author Aztec Team
 * @notice You can use this contract to immediately get back what you've deposited.
 * @dev This bridge demonstrates the flow of assets in the convert function. This bridge simply returns what has been
 *      sent to it.
 */
contract NftPurchaseBridge is BridgeBase {
    /// @notice Error for when someone attempts to add an invalid recipient
    error InvalidRecipientAddress();
    /// @notice Event emitted when a recipient is listed
    event ListedRecipient(address recipient, uint32 index);
    /// @notice Event emitted when a recipient is listed
    event ListedCollection(address collection, uint32 index);
    /// @notice Struct that defines an NFT
    struct NFT {
        address collectionAddress;
        uint256 tokenId;
    }
    /// @notice Struct for a collection and an LSSVMPair
    struct Collection {
        address collectionAddress;
        address pair;
    }
    // Address for some NFT marketplace
    address payable public immutable lssvm;
    // Mapping from a nonce to a collection
    mapping(uint256 => NFT) public ownership;
    // Starts at 1 to revert if user forgets to provide auxdata.
    uint32 public nextRecipient = 1;
    // Mapping for recipietns
    mapping(uint32 => address) public recipients;
    // Starts at 1 to revert if user forgets to provide auxdata.
    uint32 public nextCollection = 1;
    // Mapping for NFT collections
    mapping(uint32 => Collection) public collections;
    // Mapping for Collection to LSSVMPair
    mapping(address => mapping(uint256 => address)) public pairs;

    // Mapping for LSSVM pairs

    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor, address payable _lssvm) BridgeBase(_rollupProcessor) {
        lssvm = _lssvm;
    }

    /**
     * @notice Lists a new Recipient on the bridge
     * @param _recipient The address to add as a recipient
     * @return id The id of the new donee
     */
    function listRecipient(address _recipient) public returns (uint256) {
        if (_recipient == address(0)) revert InvalidRecipientAddress();
        uint32 id = nextRecipient++;
        recipients[id] = _recipient;
        emit ListedRecipient(_recipient, id);
        return id;
    }

    /**
     * @notice Lists a new Recipient on the bridge
     * @param _collection The address to add as a recipient
     * @return id The id of the new donee
     */
    function listCollection(address _collection, address _pair) public returns (uint256) {
        if (_collection == address(0)) revert InvalidRecipientAddress();
        uint32 id = nextCollection++;
        collections[id] = Collection(_collection, _pair);
        emit ListedCollection(_collection, id);
        return id;
    }

    /**
     * @notice returns data encoded in a uint64
     * @param _a param a
     * @param _b param b
     * @return uint64
     */
    function encode(uint64 _a, uint64 _b) public pure returns (uint64) {
        return (uint64(_b) << 32) | uint64(_a);
    }

    /**
     * @notice A function which returns an _totalInputValue amount of _inputAssetA
     * @param _inputAssetA - Arbitrary ERC20 token
     * @param _outputAssetA - Equal to _inputAssetA
     * @return outputValueA - the amount of output asset to return
     * @dev In this case _outputAssetA equals _inputAssetA
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            if (_outputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL) revert ErrorLib.InvalidOutputA();

            // decode data
            uint32 collectionId = uint32(_auxData);
            uint256 tokenId = uint256(_auxData >> 32);
            // get collection address and router address
            Collection memory collection = collections[collectionId];
            // Name it id because we are only interested in purchasing 1
            uint256[] memory nftId = new uint256[](1);
            nftId[0] = tokenId;
            LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
            swapList[0] = LSSVMRouter.PairSwapSpecific(LSSVMPair(collection.pair), nftId);
            // set ownership
            ownership[_interactionNonce] = NFT(collection.collectionAddress, tokenId);
            pairs[collection.collectionAddress][tokenId] = collection.pair;
            // purchase the NFT from a sudoswap pair
            LSSVMRouter(lssvm).swapETHForSpecificNFTs(
                swapList,
                payable(address(this)),
                address(this),
                block.timestamp + 100
            );

            outputValueA = 1;
        } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL && _totalInputValue == 1) {
            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED) {
                _exit(_inputAssetA, _auxData);
                outputValueA = 0;
            } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // Sale Logic
                NFT memory nft = ownership[_inputAssetA.id];
                // decode aux data
                uint32 recipientId = uint32(_auxData);
                uint256 minOutput = uint256(uint32(_auxData >> 32));
                // get recipient
                address recipient = recipients[recipientId];
                // get collection address and router address
                address pair = pairs[nft.collectionAddress][nft.tokenId];
                uint256[] memory nftId = new uint256[](1);
                nftId[0] = nft.tokenId;
                LSSVMRouter.PairSwapSpecific[] memory swapList = new LSSVMRouter.PairSwapSpecific[](1);
                swapList[0] = LSSVMRouter.PairSwapSpecific(LSSVMPair(pair), nftId);
                // Swap the NFT for ETH
                outputValueA = LSSVMRouter(lssvm).swapNFTsForToken(
                    swapList,
                    minOutput,
                    recipient,
                    block.timestamp + 100
                );
            } else revert ErrorLib.InvalidOutputA();
        }
    }

    /**
     * @notice Withdraws an NFT to some recipient
     * @param _inputAsset The inputAsset being withdrawn
     * @param _auxData auxiliary data used for the withdrawl
     */
    function _exit(AztecTypes.AztecAsset calldata _inputAsset, uint64 _auxData) private {
        address recipient = recipients[uint32(_auxData)];
        NFT memory nft = ownership[_inputAsset.id];
        delete ownership[_inputAsset.id];
        IERC721(nft.collectionAddress).safeTransferFrom(address(this), recipient, nft.tokenId);
    }

    /// @dev Callback for receiving ether when the calldata is empty
    receive() external payable {}
}
