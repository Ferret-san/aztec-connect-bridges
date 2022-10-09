// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
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
    event ListedRecipient(address donee, uint64 index);
    /// @notice Struct that defines an NFT
    struct NFT {
        address collectionAddress;
        uint256 tokenId;
    }
    // Address for some NFT marketplace
    address public immutable marketplace;
    // Mapping from a nonce to a collection
    mapping(uint256 => NFT) public ownership;
    // Starts at 1 to revert if user forgets to provide auxdata.
    uint64 public nextRecipient = 1;
    // Mapping for recipietns
    mapping(uint64 => address) public recipients;
    // Starts at 1 to revert if user forgets to provide auxdata.
    uint256 public nextCollection = 1;
    // Mapping for NFT collections
    mapping(uint256 => address) public collections;

    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor, address _marketplace) BridgeBase(_rollupProcessor) {
        marketplace = _marketplace;
    }

    /**
     * @notice Lists a new Recipient on the bridge
     * @param _recipient The address to add as a recipient
     * @return id The id of the new donee
     */
    function listRecipient(address _recipient) public returns (uint256) {
        if (_recipient == address(0)) revert InvalidRecipientAddress();
        uint64 id = nextRecipient++;
        recipients[id] = _recipient;
        emit ListedRecipient(_recipient, id);
        return id;
    }

    /**
     * @notice Lists a new Recipient on the bridge
     * @param _collection The address to add as a recipient
     * @return id The id of the new donee
     */
    function listCollection(address _collection) public returns (uint256) {
        if (_collection == address(0)) revert InvalidRecipientAddress();
        uint256 id = nextCollection++;
        collections[id] = _collection;
        emit ListedRecipient(_collection, id);
        return id;
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

            // Purchase logic (i.e get the NFT)

            outputValueA = 1;
        } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL && _totalInputValue == 1) {
            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED) {
                _exit(_inputAssetA, _auxData);
                outputValueA = 0;
            } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // Sale Logic

                // Set output value
                // get ETH from purchase and return it as outputValueA
                outputValueA = 0;
            } else revert ErrorLib.InvalidOutputA();
        }
    }

    // Internal / Helper functions

    /**
     * @notice Withdraws an NFT to some recipient
     * @param _inputAsset The inputAsset being withdrawn
     * @param _auxData auxiliary data used for the withdrawl
     */
    function _exit(AztecTypes.AztecAsset calldata _inputAsset, uint64 _auxData) private {
        address recipient = recipients[_auxData];
        NFT memory nft = ownership[_inputAsset.id];
        delete ownership[_inputAsset.id];
        IERC721(nft.collectionAddress).safeTransferFrom(address(this), recipient, nft.tokenId);
    }
}
