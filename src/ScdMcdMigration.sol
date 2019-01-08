/// ScdMcdMigration.sol

// Copyright (C) 2018 Gonzalo Balabasquer <gbalabasquer@gmail.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0;

import {SaiTubLike, ManagerLike, EthJoinLike, JoinLike, GemLike, PitLike} from "./Interfaces.sol";

contract ScdMcdMigration {
    SaiTubLike      public tub;
    address         public pit;
    ManagerLike     public cdpManager;
    JoinLike        public saiJoin;
    EthJoinLike     public ethJoin;
    JoinLike        public daiJoin;
    address         public proxyCalls;

    constructor(
        address tub_,
        address pit_,
        address cdpManager_,
        address saiJoin_,
        address ethJoin_,
        address daiJoin_
    ) public {
        tub = SaiTubLike(tub_);
        pit = pit_;
        cdpManager = ManagerLike(cdpManager_);
        saiJoin = JoinLike(saiJoin_);
        ethJoin = EthJoinLike(ethJoin_);
        daiJoin = JoinLike(daiJoin_);
        tub.gov().approve(address(tub));
        tub.skr().approve(address(tub));
        tub.sai().approve(address(tub));
        tub.sai().approve(address(saiJoin));
        daiJoin.dai().approve(address(daiJoin));
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    function swapSaiToDai(
        uint wad
    ) public {
        bytes32 urn = bytes32(bytes20(address(this)));
        saiJoin.gem().transferFrom(msg.sender, address(this), wad);
        saiJoin.join(urn, wad);
        PitLike(pit).frob(bytes32("SAI"), urn, urn, urn, int(wad), int(wad));
        daiJoin.exit(urn, msg.sender, wad);
    }

    function swapDaiToSai(
        uint wad
    ) public {
        bytes32 urn = bytes32(bytes20(address(this)));
        daiJoin.dai().transferFrom(msg.sender, address(this), wad);
        daiJoin.join(urn, wad);
        PitLike(pit).frob(bytes32("SAI"), urn, urn, urn, -int(wad), -int(wad));
        saiJoin.exit(urn, msg.sender, wad);
    }

    function migrate(
        bytes32 cup
    ) public returns (bytes12 cdp) {
        // Verify the sender is the actual wrapper owner
        require(tub.lad(cup) == address(this), "cup-not-owned");

        // Get values
        uint debtAmt = tub.tab(cup); // CDP SAI debt
        uint pethAmt = tub.ink(cup); // CDP locked collateral
        uint ethAmt = tub.bid(pethAmt); // CDP locked collateral equiv in ETH

        bytes32 urn = bytes32(bytes20(address(this)));

        // Take SAI out
        PitLike(pit).frob(
            bytes32("SAI"),
            urn,
            urn,
            urn,
            -int(debtAmt),
            0
        ); // This is only possible if Liquidation ratio is lower than 100%
        saiJoin.exit(urn, address(this), debtAmt);

        // Shut SAI CDP and get native ETH back
        tub.shut(cup);
        tub.exit(pethAmt);
        tub.gem().withdraw(ethAmt);

        // Open future user's CDP in MCD
        cdp = ManagerLike(cdpManager).open();

        // Join ETH to Adapter
        ethJoin.join.value(ethAmt)(ManagerLike(cdpManager).getUrn(cdp));

        // Lock ETH in future user's CDP, generate debt and take DAI
        (uint take, uint rate) = PitLike(pit).vat().ilks("ETH");
        ManagerLike(cdpManager).frob(
            pit,
            cdp,
            "ETH",
            int(mul(ethAmt, 10 ** 27) / take),
            int(mul(debtAmt, 10 ** 27) / rate + 1)
        );
        ManagerLike(cdpManager).exit(address(daiJoin), cdp, address(this), debtAmt);
        daiJoin.join(urn, debtAmt);

        // Re-balance Migration contract's CDP 
        PitLike(pit).frob(
            bytes32("SAI"),
            urn,
            urn,
            urn,
            0,
            -int(debtAmt)
        );

        // Set ownership of CDP to the user
        ManagerLike(cdpManager).move(cdp, msg.sender);
    }

    function() external payable {}
}
