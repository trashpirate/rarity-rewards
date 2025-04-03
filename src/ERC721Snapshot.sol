// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*//////////////////////////////////////////////////////////////
                                IMPORTS
//////////////////////////////////////////////////////////////*/

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/interfaces/IERC721Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ERC721Snapshot
 * @author Nadina Oates
 * @notice Contract to take holder snapshots of an ERC721 token.
 */
contract ERC721Snapshot is Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 constant MIN_FREQUENCY = 1 days;

    address private immutable i_collection;
    uint256 private immutable i_firstTokenId;

    uint256 private s_latestSnapshotId;

    mapping(uint256 snapshotId => mapping(address owner => uint256[] tokenIds)) private s_snapshots;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ERC721Snapshot__NoTokensMinted();

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address collection) Ownable(msg.sender) {
        i_collection = collection;
        s_latestSnapshotId = 0;
    }

    function update(uint256 firstTokenId) external {
        uint256 totalSupply = IERC721Enumerable(i_collection).totalSupply();
        if (totalSupply == 0) {
            revert ERC721Snapshot__NoTokensMinted();
        }

        totalSupply += firstTokenId;
        uint256 snapShotId = ++s_latestSnapshotId;
        IERC721Metadata collection = IERC721Metadata(i_collection);

        for (uint256 i = firstTokenId; i < 50;) {
            s_snapshots[snapShotId][collection.ownerOf(i)].push(i);
            unchecked {
                i++;
            }
        }
    } //124940050

    function getSnapshot(address tokenOwner) external view returns (uint256[] memory tokenIds) {
        uint256 totalSupply = IERC721Enumerable(i_collection).totalSupply();
        if (totalSupply == 0) {
            revert ERC721Snapshot__NoTokensMinted();
        }

        totalSupply += i_firstTokenId;
        IERC721Metadata collection = IERC721Metadata(i_collection);

        tokenIds = new uint256[](collection.balanceOf(tokenOwner));
        uint256 tokenIdsIndex = 0;
        for (uint256 i = i_firstTokenId; i < totalSupply;) {
            if (collection.ownerOf(i) == tokenOwner) {
                tokenIds[tokenIdsIndex] = i;
                unchecked {
                    tokenIdsIndex++;
                }
            }
            unchecked {
                i++;
            }
        }

        return tokenIds;
    }
}
