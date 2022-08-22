// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

/// Adapted from UniswapV3's Oracle

import "./math/Math.sol";

library OracleLib {
    using Math for uint256;

    struct Observation {
        uint32 blockTimestamp;
        uint128 lnImpliedRateCumulative;
        bool initialized;
    }

    struct OracleData {
        uint16 index;
        uint16 cardinality;
        uint16 cardinalityNext;
        OracleLib.Observation[65535] observations;
    }

    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        uint96 lnImpliedRate
    ) private pure returns (Observation memory) {
        return
            Observation({
                blockTimestamp: blockTimestamp,
                lnImpliedRateCumulative: last.lnImpliedRateCumulative +
                    uint128(lnImpliedRate) *
                    (blockTimestamp - last.blockTimestamp),
                initialized: true
            });
    }

    function initialize(OracleData storage self, uint32 time) external {
        self.observations[0] = Observation({
            blockTimestamp: time,
            lnImpliedRateCumulative: 0,
            initialized: true
        });
        (self.cardinality, self.cardinalityNext) = (1, 1);
    }

    function write(
        OracleData storage self,
        uint32 blockTimestamp,
        uint96 lnImpliedRate
    ) external {
        (uint16 index, uint16 cardinality, uint16 cardinalityNext) = (
            self.index,
            self.cardinality,
            self.cardinalityNext
        );

        Observation memory last = self.observations[index];

        // early return if we've already written an observation this block
        if (last.blockTimestamp == blockTimestamp) return;

        uint16 cardinalityUpdated;
        // if the conditions are right, we can bump the cardinality
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        uint16 indexUpdated = (index + 1) % cardinalityUpdated;

        self.observations[indexUpdated] = transform(last, blockTimestamp, lnImpliedRate);
        (self.index, self.cardinality) = (indexUpdated, cardinalityUpdated);
    }

    function grow(OracleData storage self, uint16 newCardinalityNext) external returns (uint16) {
        uint16 current = self.cardinalityNext;
        uint16 next = newCardinalityNext;

        require(current != 0, "uninitialized");
        // no-op if the passed next value isn't greater than the current next value
        if (next <= current) return current;
        // store in each slot to prevent fresh SSTOREs in swaps
        // this data will not be used because the initialized boolean is still false
        for (uint16 i = current; i != next; ) {
            self.observations[i].blockTimestamp = 1;
            unchecked {
                ++i;
            }
        }

        self.cardinalityNext = next;
        return next;
    }

    function binarySearch(
        Observation[65535] storage self,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // oldest observation
        uint256 r = l + cardinality - 1; // newest observation
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // we've landed on an uninitialized observation, keep searching higher (more recently)
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = beforeOrAt.blockTimestamp <= target;

            // check if we've found the answer!
            if (targetAtOrAfter && target <= atOrAfter.blockTimestamp) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    function getSurroundingObservations(
        Observation[65535] storage obv,
        uint32 target,
        uint96 lnImpliedRate,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // optimistically set before to the newest observation
        beforeOrAt = obv[index];

        // if the target is chronologically at or after the newest observation, we can early return
        if (beforeOrAt.blockTimestamp <= target) {
            if (beforeOrAt.blockTimestamp == target) {
                // if newest observation equals target, we're in the same block, so we can ignore atOrAfter
                return (beforeOrAt, atOrAfter);
            } else {
                // otherwise, we need to transform
                return (beforeOrAt, transform(beforeOrAt, target, lnImpliedRate));
            }
        }

        // now, set beforeOrAt to the oldest observation
        beforeOrAt = obv[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = obv[0];

        // ensure that the target is chronologically at or after the oldest observation
        require(beforeOrAt.blockTimestamp <= target, "target too old for observation");

        // if we've reached this point, we have to binary search
        return binarySearch(obv, target, index, cardinality);
    }

    function observeSingle(
        Observation[65535] storage obv,
        uint32 time,
        uint32 secondsAgo,
        uint96 lnImpliedRate,
        uint16 index,
        uint16 cardinality
    ) private view returns (uint128 lnImpliedRateCumulative) {
        if (secondsAgo == 0) {
            Observation memory last = obv[index];
            if (last.blockTimestamp != time) {
                return transform(last, time, lnImpliedRate).lnImpliedRateCumulative;
            }
            return last.lnImpliedRateCumulative;
        }

        uint32 target = time - secondsAgo;

        (Observation memory beforeOrAt, Observation memory atOrAfter) = getSurroundingObservations(
            obv,
            target,
            lnImpliedRate,
            index,
            cardinality
        );

        if (target == beforeOrAt.blockTimestamp) {
            // we're at the left boundary
            return beforeOrAt.lnImpliedRateCumulative;
        } else if (target == atOrAfter.blockTimestamp) {
            // we're at the right boundary
            return atOrAfter.lnImpliedRateCumulative;
        } else {
            // we're in the middle
            return (beforeOrAt.lnImpliedRateCumulative +
                uint128(
                    (uint256(
                        atOrAfter.lnImpliedRateCumulative - beforeOrAt.lnImpliedRateCumulative
                    ) * (target - beforeOrAt.blockTimestamp)) /
                        (atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp)
                ));
        }
    }

    function observe(
        OracleData storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        uint96 lnImpliedRate
    ) public view returns (uint128[] memory lnImpliedRateCumulative) {
        require(self.cardinality != 0, "cardinality must be positive");

        lnImpliedRateCumulative = new uint128[](secondsAgos.length);
        for (uint256 i = 0; i < lnImpliedRateCumulative.length; ) {
            lnImpliedRateCumulative[i] = observeSingle(
                self.observations,
                time,
                secondsAgos[i],
                lnImpliedRate,
                self.index,
                self.cardinality
            );
            unchecked {
                ++i;
            }
        }
    }

    function consult(
        OracleData storage self,
        uint32 time,
        uint32 secondsAgo,
        uint96 lnImpliedRate
    ) external view returns (uint96 lnImpliedRateMean) {
        require(secondsAgo != 0, "time range is zero");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        uint128[] memory lnImpliedRateCumulatives = observe(
            self,
            time,
            secondsAgos,
            lnImpliedRate
        );

        return
            (uint256(lnImpliedRateCumulatives[1] - lnImpliedRateCumulatives[0]) / secondsAgo)
                .Uint96();
    }
}
