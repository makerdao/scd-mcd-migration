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

import {SaiTubLike, ManagerLike, JoinLike, GemLike, VatLike} from "./Interfaces.sol";

contract ScdMcdMigration {
    SaiTubLike      public tub;
    address         public vat;
    ManagerLike     public cdpManager;
    JoinLike        public saiJoin;
    JoinLike        public ethJoin;
    JoinLike        public daiJoin;
    bytes32         public saiIlk;
    bytes32         public ethIlk;
    address         public proxyCalls;

    constructor(
        address tub_,
        address vat_,
        address cdpManager_,
        address saiJoin_,
        address ethJoin_,
        address daiJoin_,
        bytes32 saiIlk_,
        bytes32 ethIlk_
    ) public {
        tub = SaiTubLike(tub_);
        vat = vat_;
        cdpManager = ManagerLike(cdpManager_);
        saiJoin = JoinLike(saiJoin_);
        ethJoin = JoinLike(ethJoin_);
        daiJoin = JoinLike(daiJoin_);
        saiIlk = saiIlk_;
        ethIlk = ethIlk_;
        tub.gov().approve(address(tub), uint(-1));
        tub.skr().approve(address(tub), uint(-1));
        tub.sai().approve(address(tub), uint(-1));
        tub.sai().approve(address(saiJoin), uint(-1));
        ethJoin.gem().approve(address(ethJoin), uint(-1));
        daiJoin.dai().approve(address(daiJoin), uint(-1));
        VatLike(vat).hope(address(daiJoin));
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    function swapSaiToDai(
        uint wad
    ) public {
        saiJoin.gem().transferFrom(msg.sender, address(this), wad);
        saiJoin.join(address(this), wad);
        VatLike(vat).frob(bytes32(saiIlk), address(this), address(this), address(this), toInt(wad), toInt(wad));
        daiJoin.exit(msg.sender, wad);
    }

    function swapDaiToSai(
        uint wad
    ) public {
        daiJoin.dai().transferFrom(msg.sender, address(this), wad);
        daiJoin.join(address(this), wad);
        VatLike(vat).frob(bytes32(saiIlk), address(this), address(this), address(this), -toInt(wad), -toInt(wad));
        saiJoin.exit(msg.sender, wad);
    }

    function migrate(
        bytes32 cup
    ) public returns (uint cdp) {
        // Get values
        uint debtAmt = tub.tab(cup); // CDP SAI debt
        uint pethAmt = tub.ink(cup); // CDP locked collateral
        uint ethAmt = tub.bid(pethAmt); // CDP locked collateral equiv in ETH

        // Take SAI out
        VatLike(vat).frob(
            bytes32(saiIlk),
            address(this),
            address(this),
            address(this),
            -toInt(debtAmt),
            0
        ); // This is only possible if Liquidation ratio is lower than 100%
        saiJoin.exit(address(this), debtAmt);

        // Shut SAI CDP and get native ETH back
        tub.shut(cup);
        tub.exit(pethAmt);

        // Open future user's CDP in MCD
        cdp = ManagerLike(cdpManager).open(ethIlk);

        // Join ETH to Adapter
        // IMPORTANT: It assumes the WETH contract is the same for SCD than MCD, otherwise it should withdraw in one and deposit in the other
        ethJoin.join(ManagerLike(cdpManager).urns(cdp), ethAmt);

        // Lock ETH in future user's CDP, generate debt and take DAI
        (, uint rate,,,) = VatLike(vat).ilks(ethIlk);
        ManagerLike(cdpManager).frob(
            cdp,
            toInt(ethAmt),
            toInt(mul(debtAmt, 10 ** 27) / rate + 1)
        );
        ManagerLike(cdpManager).move(cdp, address(this), mul(debtAmt, 10 ** 27));

        // Re-balance Migration contract's CDP
        VatLike(vat).frob(
            bytes32(saiIlk),
            address(this),
            address(this),
            address(this),
            0,
            -toInt(debtAmt)
        );

        // Set ownership of CDP to the user
        ManagerLike(cdpManager).give(cdp, msg.sender);
    }

    function() external payable {}
}
